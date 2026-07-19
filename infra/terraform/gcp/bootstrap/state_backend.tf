# GCS bucket that holds the main stack's remote Terraform state
# (infra/terraform/gcp/backend.tf points at this bucket via -backend-config).
resource "google_storage_bucket" "state" {
  name     = var.state_bucket_name
  location = var.region
  project  = var.project_id

  # Object versioning is how a botched `terraform apply` state write gets
  # recovered — GCS backend does not use state locking + versioning the way
  # S3 does, so this is the safety net.
  versioning {
    enabled = true
  }

  # IAM-only access control (no legacy bucket ACLs) and no public access,
  # ever — this bucket holds Terraform state, which can contain secrets.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}
