terraform {
  # Floor pinned to latest Terraform minor; exact patch pinned in .terraform-version.
  required_version = ">= 1.15.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Deliberately no backend block: creates the GCS bucket the main stack backs onto, so it stays on local state (chicken-and-egg). Run once per GCP project.
}
