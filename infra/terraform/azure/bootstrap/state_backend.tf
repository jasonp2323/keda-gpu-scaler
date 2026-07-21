# Remote state storage — resource group + storage account + container. What the main stack's backend.tf points at; created with local state (chicken-and-egg).

resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group_name
  location = var.location

  tags = {
    Project   = "keda-gpu-scaler"
    Component = "tfstate"
    ManagedBy = "terraform"
    Stack     = "infra/terraform/azure/bootstrap"
  }
}

resource "azurerm_storage_account" "state" {
  name                = var.state_storage_account_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # No anonymous/public blob access — state only readable via authenticated ARM/OIDC identity.
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
  }

  tags = {
    Project   = "keda-gpu-scaler"
    Component = "tfstate"
    ManagedBy = "terraform"
    Stack     = "infra/terraform/azure/bootstrap"
  }
}

resource "azurerm_storage_container" "state" {
  name                  = var.state_container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}
