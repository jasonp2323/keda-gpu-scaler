terraform {
  # Floor pinned to current latest minor (1.15.x); exact patch pinned in .terraform-version.
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
  }

  # No backend block: this config creates the remote-state backend itself (chicken-and-egg), so it stays on local state. Run once, by hand, before the main stack's first init.
}
