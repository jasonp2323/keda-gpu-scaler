output "state_resource_group" {
  description = "Resource group holding the Terraform remote-state storage account."
  value       = azurerm_resource_group.state.name
}

output "state_storage_account" {
  description = "Storage account holding Terraform remote state."
  value       = azurerm_storage_account.state.name
}

output "state_container" {
  description = "Blob container within state_storage_account used for Terraform state."
  value       = azurerm_storage_container.state.name
}

output "client_id" {
  description = "Application (client) ID of the GitHub Actions OIDC app/service principal. Store as the AZURE_E2E_CLIENT_ID secret."
  value       = azuread_application.e2e.client_id
}

output "tenant_id" {
  description = "Azure AD tenant ID. Store as the AZURE_E2E_TENANT_ID secret."
  value       = data.azurerm_subscription.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID the e2e stack deploys into. Store as the AZURE_E2E_SUBSCRIPTION_ID secret."
  value       = data.azurerm_subscription.current.subscription_id
}

output "backend_config_hint" {
  description = "-backend-config flags for `terraform init` on the main stack (infra/terraform/azure), given a cluster_name. Replace <cluster_name> with the value of that stack's var.cluster_name."
  value       = "-backend-config=resource_group_name=${azurerm_resource_group.state.name} -backend-config=storage_account_name=${azurerm_storage_account.state.name} -backend-config=container_name=${azurerm_storage_container.state.name} -backend-config=key=e2e/azure/<cluster_name>.tfstate"
}
