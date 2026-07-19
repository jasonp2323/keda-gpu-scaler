# GCP bootstrap — RUN ONCE, LOCAL STATE

> **This is not the e2e test stack.** It provisions the one-time GCP
> plumbing the main stack (`infra/terraform/gcp/`) and its CI need to exist
> *before* anything else can run:
>
> 1. the **GCS bucket** the main stack uses as its remote Terraform state
>    backend, and
> 2. a **Workload Identity Federation (WIF)** pool/provider + **service
>    account** so GitHub Actions can authenticate to GCP with short-lived
>    OIDC-derived credentials — no long-lived service account key stored in
>    GitHub.
>
> Run it **once per GCP project**, by a human/maintainer with sufficient IAM
> privileges (Owner or an equivalent custom role — this config itself
> provisions IAM bindings and a WIF pool). It is **not** invoked by CI.

## Why this config has no remote backend

This is the classic Terraform bootstrap chicken-and-egg problem: the main
stack's state bucket has to exist before the main stack can point at it, so
*this* config (the thing that creates the bucket) can't itself use that
bucket. `bootstrap/` therefore deliberately uses **local state**
(`terraform.tfstate` on your machine) and has **no `backend` block**. Keep
the resulting `terraform.tfstate` somewhere safe (or migrate it to a
different bucket by hand) since it's the only record of these resources.

## Usage

```bash
cd infra/terraform/gcp/bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: project_id and a globally-unique state_bucket_name
# are required.

terraform init
terraform apply
```

## After apply: wire up GitHub

Take the outputs and store them so `.github/workflows/e2e-cloud.yaml` and
`infra-validate.yaml` can authenticate:

| Output | Where it goes |
|---|---|
| `wif_provider` | GitHub **secret** `GCP_E2E_WIF_PROVIDER` |
| `service_account_email` | GitHub **secret** `GCP_E2E_SERVICE_ACCOUNT` |
| `project` | GitHub **variable** `GCP_E2E_PROJECT` |

```bash
terraform output wif_provider
terraform output service_account_email
terraform output project
```

Add these under **Settings -> Secrets and variables -> Actions** in the
`jasonp2323/keda-gpu-scaler` repo, and make sure the `e2e-gcp` GitHub
**Environment** exists with required reviewers (see
`tests/terratest/README.md` "OIDC / Cloud Authentication Setup").

## After apply: wire up the main stack's remote backend

`infra/terraform/gcp/backend.tf` is a **partial** backend config (no
hardcoded bucket), so pass the bucket + a per-cluster prefix at `init` time:

```bash
cd infra/terraform/gcp
terraform init \
  -backend-config="bucket=$(terraform -chdir=../bootstrap output -raw state_bucket)" \
  -backend-config="prefix=e2e/gcp/<cluster_name>"
```

`terraform output backend_config_hint` (run from this directory) prints the
same flags with `<cluster_name>` left as a placeholder for you to fill in —
it should match the main stack's `var.cluster_name` so concurrent/successive
e2e runs against different cluster names don't collide on the same state
object.

## What NOT to do

- Do **not** add a `backend` block to this directory. It must stay
  local-state.
- Do **not** re-run `terraform apply` here as part of routine e2e runs —
  this is one-time account/project setup, not part of the per-run
  provision/destroy cycle.
- Do **not** widen the service account's roles beyond what's granted in
  `oidc.tf` (`container.admin`, `compute.networkAdmin`,
  `iam.serviceAccountUser` at the project level, `storage.objectAdmin`
  scoped to the state bucket only) without updating
  `tests/terratest/README.md` to match.
