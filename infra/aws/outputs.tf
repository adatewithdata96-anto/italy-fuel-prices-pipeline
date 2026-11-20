output "raw_bucket" {
  description = "Bucket with the raw MIMIT files."
  value       = aws_s3_bucket.this["raw"].bucket
}

output "lake_bucket" {
  description = "Bucket with the Iceberg tables."
  value       = aws_s3_bucket.this["lake"].bucket
}

output "ecr_repositories" {
  description = "Where to push the images."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "state_machine_arn" {
  description = "Start a run by hand: aws stepfunctions start-execution --state-machine-arn <this>"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "athena_workgroup" {
  value = aws_athena_workgroup.this.name
}

output "glue_database" {
  value = aws_glue_catalog_database.lake.name
}

output "github_actions_role_arn" {
  description = "Role for the GitHub Actions workflow that pushes images."
  value       = aws_iam_role.github_actions.arn
}
