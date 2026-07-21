# GCS bucket that holds the main stack's remote Terraform state (infra/terraform/gcp/backend.tf points here via -backend-config).
resource "google_storage_bucket" "state" {
  name     = var.state_bucket_name
  location = var.region
  project  = var.project_id

  # Versioning is the recovery path for a botched state write — GCS backend doesn't lock+version like S3 does.
  versioning {
    enabled = true
  }

  # IAM-only access, no public access ever — this bucket can hold secrets in state.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}
