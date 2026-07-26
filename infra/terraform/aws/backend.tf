terraform {
  # Partial config: bucket/key/region supplied at `terraform init -backend-config=...`.
  # State locking is native to the S3 backend (use_lockfile) — no DynamoDB table.
  backend "s3" {
    use_lockfile = true
  }
}
