# S3 bucket for the main stack's remote Terraform state. Locking is native to
# the S3 backend (use_lockfile) — no DynamoDB table.
#
# Each bucket aspect is its own resource: the inline equivalents on
# aws_s3_bucket are deprecated in provider 6.x. Default SSE-S3 encryption (AWS
# default since Jan 2023) is relied upon and not restated; the public-access
# block matches the AWS default too but is declared so the guarantee is
# explicit to Terraform and to security scanners.
resource "aws_s3_bucket" "state" {
  bucket           = var.state_bucket_name
  bucket_namespace = "account-regional"

  # Creation-time only: enables the object-lock configuration below.
  object_lock_enabled = true

  # No force_destroy: losing state shouldn't be a side effect of an unrelated destroy.

  tags = {
    Name = "Terraform state"
  }
}

# Versioning is the undo button for a corrupted or bad state write.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Every state version is immutable for 14 days. GOVERNANCE (not COMPLIANCE) so
# an admin with s3:BypassGovernanceRetention can intervene in an emergency; the
# deployer role has no such permission, so a compromised pipeline can't
# permanently destroy state history.
resource "aws_s3_bucket_object_lock_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 14
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# Expire noncurrent state versions after 90 days — must stay above the 14-day
# object-lock retention (lifecycle can't remove a version until its lock ends).
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
