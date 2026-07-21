# GitHub Actions OIDC — app registration + federated credentials + custom role. Mirrors the manual `az` steps in tests/terratest/README.md ("### Azure").

data "azurerm_subscription" "current" {}

resource "azuread_application" "e2e" {
  count = var.create_app_registration ? 1 : 0

  display_name = var.app_display_name
}

resource "azuread_service_principal" "e2e" {
  count = var.create_app_registration ? 1 : 0

  client_id = azuread_application.e2e[0].client_id
}

# Reference an existing app/SP instead of creating a duplicate — display_name isn't unique, so re-applying without state (or this toggle) would silently create a second app with a new client_id.
data "azuread_application" "e2e" {
  count        = var.create_app_registration ? 0 : 1
  display_name = var.app_display_name
}

data "azuread_service_principal" "e2e" {
  count     = var.create_app_registration ? 0 : 1
  client_id = data.azuread_application.e2e[0].client_id
}

locals {
  app_object_id = var.create_app_registration ? azuread_application.e2e[0].id : data.azuread_application.e2e[0].id
  app_client_id = var.create_app_registration ? azuread_application.e2e[0].client_id : data.azuread_application.e2e[0].client_id
  sp_object_id  = var.create_app_registration ? azuread_service_principal.e2e[0].object_id : data.azuread_service_principal.e2e[0].object_id

  github_owner = split("/", var.github_repository)[0]
  github_repo  = split("/", var.github_repository)[1]

  # Classic OWNER/REPO slug, plus immutable OWNER@OWNER_ID/REPO@REPO_ID (repos created after 2026-07-15) when IDs are supplied. Federated credentials match `sub` exactly, so each slug needs its own credential set.
  github_repo_slugs = {
    classic   = var.github_repository
    immutable = var.github_owner_id != "" && var.github_repo_id != "" ? "${local.github_owner}@${var.github_owner_id}/${local.github_repo}@${var.github_repo_id}" : ""
  }

  # Slug keys that are actually set (drops immutable when the IDs are empty).
  slug_keys = [for k, v in local.github_repo_slugs : k if v != ""]

  # Subject suffix per GitHub Environment, plus plain `pull_request` for infra-validate's plan job (no Environment).
  oidc_suffixes = merge(
    { for env in var.environments : "env-${env}" => "environment:${env}" },
    { "pull-request" = "pull_request" },
  )

  # One federated credential per (slug x suffix), keyed for a stable, unique display_name.
  federated_credential_subjects = {
    for pair in setproduct(local.slug_keys, keys(local.oidc_suffixes)) :
    "${pair[0]}-${pair[1]}" => "repo:${local.github_repo_slugs[pair[0]]}:${local.oidc_suffixes[pair[1]]}"
  }
}

resource "azuread_application_federated_identity_credential" "e2e" {
  for_each = local.federated_credential_subjects

  application_id = local.app_object_id
  display_name   = "github-actions-${each.key}"
  description    = "GitHub Actions OIDC — ${each.value}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value
}

# Custom role — same scope as azure-deployer-role.json in the terratest README, plus storage actions for the azurerm backend (account created by state_backend.tf).

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

      # Remote state: azurerm backend auths with an account key (not RBAC data actions), so these control-plane actions just need to read the account + fetch the key.
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
  principal_id       = local.sp_object_id

  # Skips the (eventually-consistent) AAD replication check to avoid racing a just-created SP; harmless no-op for an existing SP.
  skip_service_principal_aad_check = true
}
