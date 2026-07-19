terraform {
  # Floor pinned to the current latest Terraform minor (1.15.x). The exact
  # patch contributors/CI should use is pinned in .terraform-version.
  required_version = ">= 1.15.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.79"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}
