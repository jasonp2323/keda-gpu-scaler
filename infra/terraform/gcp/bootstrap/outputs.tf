output "state_bucket" {
  description = "GCS bucket name for the main stack's remote Terraform state. Use it to `terraform init -backend-config=bucket=<value>` in infra/terraform/gcp."
  value       = google_storage_bucket.state.name
}

output "wif_provider" {
  description = "Full Workload Identity Pool Provider resource name. Store as GitHub secret GCP_E2E_WIF_PROVIDER."
  value       = local.wif_provider_name
}

output "service_account_email" {
  description = "Service account CI impersonates via WIF. Store as GitHub secret GCP_E2E_SERVICE_ACCOUNT."
  value       = google_service_account.e2e.email
}

output "project" {
  description = "GCP project ID. Store as GitHub variable GCP_E2E_PROJECT."
  value       = var.project_id
}

output "backend_config_hint" {
  description = "-backend-config flags for `terraform init` in infra/terraform/gcp against the bucket created here. <cluster_name> should match var.cluster_name of the main stack (state is keyed per cluster so multiple e2e runs don't collide)."
  value       = "-backend-config=\"bucket=${google_storage_bucket.state.name}\" -backend-config=\"prefix=e2e/gcp/<cluster_name>\""
}
