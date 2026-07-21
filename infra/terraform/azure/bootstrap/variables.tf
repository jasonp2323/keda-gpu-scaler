# Azure

variable "subscription_id" {
  description = "Azure subscription ID to bootstrap. Leave null to use the ARM_SUBSCRIPTION_ID environment variable."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for the state storage account (and role AssignableScopes region-agnostic, but kept consistent with the main stack's default)."
  type        = string
  default     = "eastus"
}

# GitHub OIDC

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to federate via OIDC."
  type        = string
  default     = "jasonp2323/keda-gpu-scaler"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner (user/org) ID, embedded in the immutable OIDC `sub` GitHub issues for repos created after 2026-07-15 (repo:OWNER@OWNER_ID/REPO@REPO_ID:...). Fetch: gh api repos/<owner>/<repo> --jq '.owner.id'. Empty = federate the classic sub only."
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID, embedded in the immutable OIDC `sub`. Fetch: gh api repos/<owner>/<repo> --jq '.id'. Empty = federate the classic sub only."
  type        = string
  default     = ""
}

variable "app_display_name" {
  description = "Display name for the app registration / service principal used by CI."
  type        = string
  default     = "keda-gpu-scaler-e2e"
}

variable "create_app_registration" {
  description = "Create the app registration + service principal. Set false to reference an existing app by display_name (var.app_display_name) instead of creating a duplicate."
  type        = bool
  default     = true
}

variable "environments" {
  description = "GitHub Environments to trust via federated credentials (subject repo:<github_repository>:environment:<env>). A pull_request-subject credential is always added in addition to these."
  type        = list(string)
  default     = ["e2e-azure"]
}

# Remote state backend

variable "state_resource_group_name" {
  description = "Resource group created to hold the Terraform remote-state storage account."
  type        = string
  default     = "keda-gpu-scaler-tfstate-rg"
}

variable "state_storage_account_name" {
  description = "Storage account for Terraform remote state. Must be globally unique, 3-24 lowercase letters/digits, no hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "state_storage_account_name must be 3-24 lowercase letters/digits (Azure storage account naming rules)."
  }
}

variable "state_container_name" {
  description = "Blob container within the state storage account used for Terraform state."
  type        = string
  default     = "tfstate"
}
