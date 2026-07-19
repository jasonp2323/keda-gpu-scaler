provider "azurerm" {
  # subscription_id is required by the azurerm v4 provider. Falls back to the
  # ARM_SUBSCRIPTION_ID environment variable — same convention as the main stack.
  subscription_id = var.subscription_id

  features {}
}

# azuread authenticates against the same tenant as azurerm (ARM_TENANT_ID /
# az CLI login). No explicit config needed beyond the ambient Azure CLI /
# environment credentials used to run this run-once bootstrap.
provider "azuread" {}
