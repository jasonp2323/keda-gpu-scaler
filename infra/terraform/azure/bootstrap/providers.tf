provider "azurerm" {
  # Required by azurerm v4; falls back to ARM_SUBSCRIPTION_ID, same as the main stack.
  subscription_id = var.subscription_id

  features {}
}

# azuread authenticates against the same tenant as azurerm (ARM_TENANT_ID / az CLI login); no explicit config needed.
provider "azuread" {}
