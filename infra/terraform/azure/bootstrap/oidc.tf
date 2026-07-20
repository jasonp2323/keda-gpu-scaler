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
  count = var.create_app_registration ? 1 : 0

  display_name = var.app_display_name
}

resource "azuread_service_principal" "e2e" {
  count = var.create_app_registration ? 1 : 0

  client_id = azuread_application.e2e[0].client_id
}

# Reference an existing app/service principal instead of creating a duplicate.
# Azure AD app display_name is NOT unique, so re-applying without state (and
# without this toggle) would silently create a second app with a new client_id.
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

  # Classic OWNER/REPO slug, plus — when the numeric IDs are supplied — the
  # immutable OWNER@OWNER_ID/REPO@REPO_ID slug GitHub embeds in `sub` for repos
  # created after 2026-07-15. Federated credentials match `sub` exactly (no
  # wildcard), so each accepted slug needs its own set of credentials.
  github_repo_slugs = {
    classic   = var.github_repository
    immutable = var.github_owner_id != "" && var.github_repo_id != "" ? "${local.github_owner}@${var.github_owner_id}/${local.github_repo}@${var.github_repo_id}" : ""
  }

  # Slug keys that are actually set (drops immutable when the IDs are empty).
  slug_keys = [for k, v in local.github_repo_slugs : k if v != ""]

  # Subject suffix per GitHub Environment (`environment:<env>`) plus plain
  # `pull_request` (infra-validate's plan job, which has no Environment).
  oidc_suffixes = merge(
    { for env in var.environments : "env-${env}" => "environment:${env}" },
    { "pull-request" = "pull_request" },
  )

  # One federated credential per (non-empty slug) x (suffix), keyed for a
  # stable, unique display_name.
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
  principal_id       = local.sp_object_id

  # When create_app_registration=true the service principal was just created
  # in this same apply, so skip the (eventually-consistent) AAD replication
  # check to avoid racing it. Harmless no-op when referencing an existing SP.
  skip_service_principal_aad_check = true
}
