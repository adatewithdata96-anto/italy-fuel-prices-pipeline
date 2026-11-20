# Step Functions runs ingestion, then dbt, with retries; on failure it sends an SNS alert.
# EventBridge Scheduler starts it every day.

locals {
  network_configuration = {
    AwsvpcConfiguration = {
      Subnets        = data.aws_subnets.default.ids
      SecurityGroups = [aws_security_group.tasks.id]
      AssignPublicIp = "ENABLED"
    }
  }

  task_retry = [{
    ErrorEquals     = ["States.TaskFailed"]
    IntervalSeconds = 120
    MaxAttempts     = 2
    BackoffRate     = 2
  }]

  task_catch = [{
    ErrorEquals = ["States.ALL"]
    ResultPath  = "$.error"
    Next        = "NotifyFailure"
  }]
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${local.name}-pipeline"
  role_arn = aws_iam_role.sfn.arn

  definition = jsonencode({
    Comment = "Daily Italy fuel prices pipeline: ingestion, then dbt"
    StartAt = "Ingest"
    States = {
      Ingest = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType           = "FARGATE"
          Cluster              = aws_ecs_cluster.this.arn
          TaskDefinition       = aws_ecs_task_definition.ingestion.arn
          NetworkConfiguration = local.network_configuration
        }
        Retry      = local.task_retry
        Catch      = local.task_catch
        ResultPath = null
        Next       = "Transform"
      }
      Transform = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType           = "FARGATE"
          Cluster              = aws_ecs_cluster.this.arn
          TaskDefinition       = aws_ecs_task_definition.dbt.arn
          NetworkConfiguration = local.network_configuration
        }
        Retry      = local.task_retry
        Catch      = local.task_catch
        ResultPath = null
        Next       = "Done"
      }
      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.alerts.arn
          Subject     = "Fuel prices pipeline failed"
          "Message.$" = "States.JsonToString($.error)"
        }
        Next = "Failed"
      }
      Failed = {
        Type  = "Fail"
        Error = "PipelineFailed"
      }
      Done = {
        Type = "Succeed"
      }
    }
  })
}

# --- Step Functions role -----------------------------------------------------------------------

resource "aws_iam_role" "sfn" {
  name = "${local.name}-sfn"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

data "aws_iam_policy_document" "sfn" {
  statement {
    sid     = "RunTasks"
    actions = ["ecs:RunTask"]
    resources = [
      aws_ecs_task_definition.ingestion.arn_without_revision,
      "${aws_ecs_task_definition.ingestion.arn_without_revision}:*",
      aws_ecs_task_definition.dbt.arn_without_revision,
      "${aws_ecs_task_definition.dbt.arn_without_revision}:*",
    ]
  }

  statement {
    sid       = "TrackTasks"
    actions   = ["ecs:StopTask", "ecs:DescribeTasks"]
    resources = ["*"]
  }

  statement {
    sid     = "PassRoles"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.execution.arn,
      aws_iam_role.ingestion_task.arn,
      aws_iam_role.dbt_task.arn,
    ]
  }

  # Needed by the ".sync" integration, which waits for the task to finish.
  statement {
    sid       = "SyncIntegration"
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:aws:events:${var.region}:${local.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"]
  }

  statement {
    sid       = "Alerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "sfn" {
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}

# --- Daily schedule ----------------------------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${local.name}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.pipeline.arn
    }]
  })
}

resource "aws_scheduler_schedule" "daily" {
  name                         = "${local.name}-daily"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.pipeline.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}
