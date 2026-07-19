terraform {
  # Floor pinned to latest Terraform minor; exact patch pinned in .terraform-version.
  required_version = ">= 1.15.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Deliberately NO `backend` block — this config creates the GCS state bucket
  # the main stack backs onto, so it must run with local state itself
  # (chicken-and-egg). Run once per GCP project; do not add a remote backend
  # here.
}
