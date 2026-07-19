variable "project_id" {
  description = "GCP project ID to create the state bucket and WIF/service account in."
  type        = string
}

variable "region" {
  description = "GCP region for the state bucket (dual/multi-region names also accepted by google_storage_bucket)."
  type        = string
  default     = "us-central1"
}

variable "github_repository" {
  description = "GitHub `owner/repo` allowed to assume the service account via Workload Identity Federation."
  type        = string
  default     = "jasonp2323/keda-gpu-scaler"
}

variable "state_bucket_name" {
  description = "Name of the GCS bucket used for the main stack's remote Terraform state. Bucket names are globally unique across all of GCS."
  type        = string
}

variable "pool_id" {
  description = "ID of the Workload Identity Pool created for GitHub Actions OIDC."
  type        = string
  default     = "keda-gpu-scaler-pool"
}

variable "provider_id" {
  description = "ID of the Workload Identity Pool Provider (the GitHub OIDC provider) within the pool."
  type        = string
  default     = "keda-gpu-scaler-provider"
}

variable "service_account_id" {
  description = "Account ID (local part, before @project.iam.gserviceaccount.com) of the service account CI impersonates for e2e runs."
  type        = string
  default     = "keda-gpu-scaler-e2e"
}
