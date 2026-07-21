# Azure bootstrap

**Run once, by a maintainer, before `infra/terraform/azure` can use a remote
backend or any CI job federates into Azure.** Creates:

1. the storage account + container the main stack's `azurerm` backend
   (`infra/terraform/azure/backend.tf`) points at, and
2. the GitHub Actions OIDC app registration, federated credentials, and scoped
   custom role documented in `tests/terratest/README.md` ("### Azure").

Uses **local state** on purpose (no `backend.tf`) — the storage account it
creates doesn't exist yet to point at. Keep `terraform.tfstate` for this
directory somewhere safe (it's git-ignored) — it's the only record of these
resources short of re-importing them.

## Prerequisites

- Terraform `1.15.6` (`.terraform-version`).
- `az login`'d (or `ARM_*` / `ARM_SUBSCRIPTION_ID` env vars) as a principal
  able to create app registrations, service principals, role
  definitions/assignments, and storage accounts at subscription scope.
- A globally unique `state_storage_account_name` (3-24 lowercase
  letters/digits) — no default; set it in `terraform.tfvars`.

## Usage

```bash
cd infra/terraform/azure/bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: at minimum set state_storage_account_name

export ARM_SUBSCRIPTION_ID=<your-subscription-id>   # or set subscription_id in tfvars
terraform init
terraform apply
```

## Wire up the rest

**1. GitHub secrets** (for the e2e workflow's OIDC login):

| Output | GitHub secret |
|---|---|
| `client_id` | `AZURE_E2E_CLIENT_ID` |
| `tenant_id` | `AZURE_E2E_TENANT_ID` |
| `subscription_id` | `AZURE_E2E_SUBSCRIPTION_ID` |

These match the federated credentials this bootstrap created — one per
`var.environments` entry plus one for `pull_request` runs. Adding a GitHub
Environment later? Add it to `var.environments` and re-`apply` this directory
rather than hand-editing credentials outside Terraform.

**2. Point the main stack at the new remote backend:**

```bash
terraform output backend_config_hint   # ready-to-paste -backend-config flags

cd ../  # infra/terraform/azure
terraform init \
  -backend-config="resource_group_name=<state_resource_group>" \
  -backend-config="storage_account_name=<state_storage_account>" \
  -backend-config="container_name=<state_container>" \
  -backend-config="key=e2e/azure/<cluster_name>.tfstate"
```

If the main stack already has local state, `terraform init` offers to migrate
it into the new backend — accept (`yes`) so existing resources aren't
orphaned. `key` is per-cluster so parallel test runs don't collide in the
same container.

## Cost

Single Standard LRS storage account with a couple of small blobs —
negligible (well under $1/month). App registration/service principal/role
are free. No `terraform destroy` needed between test runs; only tear this
down when decommissioning the whole e2e setup.

## Notes

The custom role (`keda-gpu-scaler-e2e-deployer`) is scoped to exactly what the
main stack and the remote backend need: resource-group + AKS
cluster/locations actions (same as `azure-deployer-role.json` in
`tests/terratest/README.md`), plus `Microsoft.Storage/storageAccounts/read`,
`.../listKeys/action`, and `.../blobServices/containers/read` so CI can use
the azurerm backend (which authenticates with an account key, not RBAC
data-plane actions).
