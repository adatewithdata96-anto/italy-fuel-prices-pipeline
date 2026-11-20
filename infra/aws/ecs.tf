# ECS Fargate: one task definition per job, each with its own least-privilege IAM role.

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "disabled" # enable in production if you need per-task metrics (extra cost)
  }
}

resource "aws_cloudwatch_log_group" "tasks" {
  for_each          = local.images
  name              = "/ecs/${local.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

# --- Roles -------------------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Used by ECS itself to pull images and write logs.
resource "aws_iam_role" "execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Ingestion: can only write to the raw bucket.
resource "aws_iam_role" "ingestion_task" {
  name               = "${local.name}-ingestion-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "ingestion_task" {
  statement {
    sid       = "WriteRawFiles"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this["raw"].arn}/*"]
  }
}

resource "aws_iam_role_policy" "ingestion_task" {
  role   = aws_iam_role.ingestion_task.id
  policy = data.aws_iam_policy_document.ingestion_task.json
}

# dbt: reads raw files, reads/writes the lake, runs Athena queries, manages Glue tables.
resource "aws_iam_role" "dbt_task" {
  name               = "${local.name}-dbt-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "dbt_task" {
  statement {
    sid     = "ReadRaw"
    actions = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.this["raw"].arn,
      "${aws_s3_bucket.this["raw"].arn}/*",
    ]
  }

  statement {
    sid = "ReadWriteLakeAndResults"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:ListBucket", "s3:GetBucketLocation", "s3:AbortMultipartUpload",
    ]
    resources = [
      aws_s3_bucket.this["lake"].arn,
      "${aws_s3_bucket.this["lake"].arn}/*",
      aws_s3_bucket.this["athena_results"].arn,
      "${aws_s3_bucket.this["athena_results"].arn}/*",
    ]
  }

  statement {
    sid = "Athena"
    actions = [
      "athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults",
      "athena:StopQueryExecution", "athena:GetWorkGroup",
    ]
    resources = [aws_athena_workgroup.this.arn]
  }

  statement {
    sid = "GlueCatalog"
    actions = [
      "glue:GetDatabase", "glue:GetDatabases",
      "glue:GetTable", "glue:GetTables", "glue:CreateTable", "glue:UpdateTable", "glue:DeleteTable",
      "glue:GetPartition", "glue:GetPartitions", "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${local.account_id}:catalog",
      aws_glue_catalog_database.lake.arn,
      "arn:aws:glue:${var.region}:${local.account_id}:table/${aws_glue_catalog_database.lake.name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "dbt_task" {
  role   = aws_iam_role.dbt_task.id
  policy = data.aws_iam_policy_document.dbt_task.json
}

# --- Task definitions --------------------------------------------------------------------------

resource "aws_ecs_task_definition" "ingestion" {
  family                   = "${local.name}-ingestion"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.ingestion_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "ingestion"
    image     = "${aws_ecr_repository.this["ingestion"].repository_url}:${var.image_tag}"
    essential = true
    environment = [
      { name = "S3_BUCKET", value = aws_s3_bucket.this["raw"].bucket },
      { name = "MIMIT_PRICES_URL", value = var.mimit_prices_url },
      { name = "MIMIT_STATIONS_URL", value = var.mimit_stations_url },
      { name = "CREATE_BUCKET", value = "false" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.tasks["ingestion"].name
        awslogs-region        = var.region
        awslogs-stream-prefix = "ingestion"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "dbt" {
  family                   = "${local.name}-dbt"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.dbt_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "dbt"
    image     = "${aws_ecr_repository.this["dbt"].repository_url}:${var.image_tag}"
    essential = true
    command   = ["build", "--target", "prod"]
    environment = [
      { name = "ATHENA_WORKGROUP", value = aws_athena_workgroup.this.name },
      { name = "ATHENA_DATABASE", value = aws_glue_catalog_database.lake.name },
      { name = "ATHENA_S3_DATA_DIR", value = "s3://${aws_s3_bucket.this["lake"].bucket}/tables/" },
      { name = "ATHENA_S3_STAGING_DIR", value = "s3://${aws_s3_bucket.this["athena_results"].bucket}/dbt/" },
      { name = "RAW_BUCKET", value = aws_s3_bucket.this["raw"].bucket },
      { name = "AWS_REGION", value = var.region },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.tasks["dbt"].name
        awslogs-region        = var.region
        awslogs-stream-prefix = "dbt"
      }
    }
  }])
}
