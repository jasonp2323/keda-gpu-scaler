terraform {
  # Floor pinned to the current latest Terraform minor (1.15.x). The exact
  # patch contributors/CI should use is pinned in .terraform-version.
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
  }

  # No backend block: this config creates the remote-state backend (S3 +
  # DynamoDB) itself, so it's the chicken-and-egg root and stays on local
  # state. Run once, by hand, before the main stack ever runs `init`.
}
