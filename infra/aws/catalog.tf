# Glue Data Catalog database for the Iceberg tables, and an Athena workgroup with cost limits.

resource "aws_glue_catalog_database" "lake" {
  name        = replace(local.name, "-", "_")
  description = "Italy fuel prices: tables built by dbt"
}

resource "aws_athena_workgroup" "this" {
  name          = local.name
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_cutoff

    result_configuration {
      output_location = "s3://${aws_s3_bucket.this["athena_results"].bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
