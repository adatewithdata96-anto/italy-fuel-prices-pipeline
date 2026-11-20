# Three private, encrypted buckets:
#   raw           - files exactly as downloaded from MIMIT (bronze)
#   lake          - Iceberg tables written by dbt-athena (silver / gold)
#   athena-results - query results

locals {
  buckets = {
    raw            = "${local.name}-raw-${local.account_id}"
    lake           = "${local.name}-lake-${local.account_id}"
    athena_results = "${local.name}-athena-results-${local.account_id}"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets
  bucket   = each.value
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.this["raw"].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Raw files are rarely read after the first days: move them to cheaper storage classes.
resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.this["raw"].id

  rule {
    id     = "tier-old-raw-files"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.this["athena_results"].id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}
