variable "region" {
  description = "AWS region to create the state backend and OIDC role in."
  type        = string
  default     = "us-east-2"
}

variable "github_repository" {
  description = "GitHub \"owner/repo\" allowed to assume the deployer role via OIDC."
  type        = string
  default     = "jasonp2323/keda-gpu-scaler"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner (user/org) ID, embedded in the immutable OIDC `sub` GitHub issues for repos created after 2026-07-15 (repo:OWNER@OWNER_ID/REPO@REPO_ID:...). Fetch: gh api repos/<owner>/<repo> --jq '.owner.id'. Empty = trust the classic sub only."
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID, embedded in the immutable OIDC `sub`. Fetch: gh api repos/<owner>/<repo> --jq '.id'. Empty = trust the classic sub only."
  type        = string
  default     = ""
}

variable "state_bucket_name" {
  description = "S3 bucket for the main stack's Terraform state. Required: bucket names are globally unique, so there's no safe default."
  type        = string
}

variable "state_lock_table_name" {
  description = "DynamoDB table used for Terraform state locking."
  type        = string
  default     = "keda-gpu-scaler-tf-lock"
}

variable "role_name" {
  description = "Name of the IAM role GitHub Actions assumes via OIDC to run the main stack."
  type        = string
  default     = "keda-gpu-scaler-e2e"
}

variable "environments" {
  description = "GitHub Environments allowed to assume the deployer role (each becomes a repo:<repo>:environment:<env> OIDC subject, in addition to the pull_request plan-job subject)."
  type        = list(string)
  default     = ["e2e-aws"]
}
