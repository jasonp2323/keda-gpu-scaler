###############################################################################
# GitHub Actions OIDC — app registration + federated credentials + custom role
#
# Mirrors, in Terraform, the manual `az` steps documented in
# tests/terratest/README.md ("### Azure"): an app registration + service
# principal that GitHub Actions federates into (no client secret), scoped by a
# custom role to just the resources the e2e stack (and its remote-state
# storage account) touches.
###############################################################################

data "azurerm_subscription" "current" {}

resource "azuread_application" "e2e" {
  display_name = var.app_display_name
}

resource "azuread_service_principal" "e2e" {
  client_id = azuread_application.e2e.client_id
}

locals {
  # One federated credential per GitHub Environment (`environment:<env>`),
  # plus one for plain `pull_request` runs (e.g. infra-validate's plan job,
  # which doesn't run under an Environment). Keyed so each gets a stable,
  # unique display_name.
  federated_credential_subjects = merge(
    { for env in var.environments : "environment-${env}" => "repo:${var.github_repository}:environment:${env}" },
    { "pull_request" = "repo:${var.github_repository}:pull_request" },
  )
}

resource "azuread_application_federated_identity_credential" "e2e" {
  for_each = local.federated_credential_subjects

  application_id = azuread_application.e2e.id
  display_name   = "github-actions-${each.key}"
  description    = "GitHub Actions OIDC — ${each.value}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value
}

###############################################################################
# Custom role — same scope as azure-deployer-role.json in the terratest
# README, plus the storage actions CI needs to use the azurerm backend
# (read the account, list its keys, read containers) since the main stack's
# state now lives in the account created by state_backend.tf.
###############################################################################

resource "azurerm_role_definition" "deployer" {
  name  = "keda-gpu-scaler-e2e-deployer"
  scope = data.azurerm_subscription.current.id

  description = "Deploy the keda-gpu-scaler AKS e2e stack (resource group + AKS cluster with a system-assigned identity) and use the Terraform remote-state storage account."

  permissions {
    actions = [
      # Stack: resource group + AKS cluster (system-assigned identity).
      "Microsoft.Resources/subscriptions/read",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/resourceGroups/write",
      "Microsoft.Resources/subscriptions/resourceGroups/delete",
      "Microsoft.ContainerService/managedClusters/*",
      "Microsoft.ContainerService/locations/*/read",

      # Remote state: the azurerm backend authenticates to the state storage
      # account with an account key (data plane is key/AD, not RBAC data
      # actions), so the control-plane actions below are what's needed to
      # read the account and fetch that key.
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/listKeys/action",
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
    ]
    not_actions = []
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

resource "azurerm_role_assignment" "deployer" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.deployer.role_definition_resource_id
  principal_id       = azuread_service_principal.e2e.object_id

  # The service principal was just created in this same apply; skip the
  # (eventually-consistent) AAD replication check so the assignment doesn't
  # race it.
  skip_service_principal_aad_check = true
}
