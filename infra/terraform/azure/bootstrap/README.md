# Azure bootstrap — RUN ONCE, by a maintainer, before the e2e stack or CI exist

**This is not part of the e2e cluster. It is a one-time, by-hand setup step**
that must complete *before* `infra/terraform/azure` can use a remote backend
or before any CI job federates into Azure. It provisions:

1. the storage account + container the main stack's `azurerm` backend
   (`infra/terraform/azure/backend.tf`) points at, and
2. the GitHub Actions OIDC app registration, federated credentials, and
   scoped custom role documented in `tests/terratest/README.md` ("### Azure").

**This directory uses LOCAL state on purpose** (no `backend.tf` here) — the
storage account it creates doesn't exist yet, so it can't be its own backend.
Keep `terraform.tfstate` for this directory somewhere safe (it is git-ignored;
consider a private location outside the repo checkout, e.g. `~/.tfstate/`)
since it's the only record of these resources short of re-importing them.

## Prerequisites

- Terraform `1.15.6` (see `.terraform-version`).
- `az login`'d (or `ARM_*` / `ARM_SUBSCRIPTION_ID` env vars set) as a principal
  with rights to create app registrations, service principals, role
  definitions/assignments, and storage accounts at subscription scope.
- Decide on a **globally unique** `state_storage_account_name` (3-24 lowercase
  letters/digits — Azure storage account naming rules). There is no default;
  pick one and set it in `terraform.tfvars`.

## Run it

```bash
cd infra/terraform/azure/bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: at minimum set state_storage_account_name

export ARM_SUBSCRIPTION_ID=<your-subscription-id>   # or set subscription_id in tfvars

terraform init
terraform apply
```

## After apply — wire up the rest by hand

### 1. GitHub secrets (for the e2e workflow's OIDC login)

```bash
terraform output -raw client_id
terraform output -raw tenant_id
terraform output -raw subscription_id
```

Store these as GitHub repository (or environment) secrets:

- `AZURE_E2E_CLIENT_ID`
- `AZURE_E2E_TENANT_ID`
- `AZURE_E2E_SUBSCRIPTION_ID`

These match the federated credentials this bootstrap created — one per
`var.environments` entry (subject `repo:<github_repository>:environment:<env>`)
plus one for `pull_request` runs. If you add a new GitHub Environment later,
add it to `var.environments` and re-`apply` this directory; don't hand-edit
credentials outside Terraform or this config will fight them on the next
apply.

### 2. Point the main stack at the new remote backend

```bash
terraform output state_resource_group
terraform output state_storage_account
terraform output state_container
terraform output backend_config_hint   # ready-to-paste -backend-config flags
```

Then, from `infra/terraform/azure` (the main stack, which now has a partial
`backend "azurerm" {}` block in `backend.tf`):

```bash
cd ../  # infra/terraform/azure
terraform init \
  -backend-config="resource_group_name=<state_resource_group>" \
  -backend-config="storage_account_name=<state_storage_account>" \
  -backend-config="container_name=<state_container>" \
  -backend-config="key=e2e/azure/<cluster_name>.tfstate"
```

**If the main stack already has local state**, `terraform init` will offer to
migrate it into the new backend — accept that (`yes`) rather than starting
from an empty remote state, so existing resources aren't orphaned.

`key` is per-cluster (`e2e/azure/<cluster_name>.tfstate`) so multiple stack
instances (e.g. different `cluster_name` values for parallel test runs) don't
collide in the same container.

## Cost

The state storage account is a single Standard LRS account with a couple of
small blobs — negligible cost (well under $1/month). The app
registration/service principal/role are free. Nothing here is a GPU resource
and nothing here needs `terraform destroy` between test runs — only tear this
down if you're decommissioning the whole e2e setup.

## Notes

- The custom role (`keda-gpu-scaler-e2e-deployer`) is scoped to exactly what
  the main stack and the remote backend need: resource-group + AKS
  cluster/locations actions (same as `azure-deployer-role.json` in
  `tests/terratest/README.md`), plus `Microsoft.Storage/storageAccounts/read`,
  `.../listKeys/action`, and `.../blobServices/containers/read` so CI can use
  the azurerm backend (which authenticates to the state storage account with
  an account key, not RBAC data-plane actions).
- Terraform is not installed in this environment — this config has not been
  run through `terraform validate`/`plan`. Review the HCL carefully before
  your first real `apply`.
