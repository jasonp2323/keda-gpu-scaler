# GCP bootstrap — run once, local state

**Not the e2e test stack** — provisions the one-time GCP plumbing the main
stack (`infra/terraform/gcp/`) and its CI need before anything else can run:

1. the **GCS bucket** the main stack uses as its remote Terraform state
   backend, and
2. a **Workload Identity Federation (WIF)** pool/provider + **service
   account** so GitHub Actions can authenticate with short-lived
   OIDC-derived credentials — no long-lived service account key stored in
   GitHub.

Run once per GCP project, by a human/maintainer with sufficient IAM
privileges (Owner or an equivalent custom role — this config itself
provisions IAM bindings and a WIF pool). Not invoked by CI.

This is the classic Terraform bootstrap chicken-and-egg problem: the main
stack's state bucket has to exist before the main stack can point at it, so
this config uses **local state** (`terraform.tfstate` on your machine) and
has **no `backend` block**. Keep the resulting `terraform.tfstate` somewhere
safe (or migrate it to a different bucket by hand) — it's the only record of
these resources.

## Usage

```bash
cd infra/terraform/gcp/bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: project_id and a globally-unique state_bucket_name
# are required.

terraform init
terraform apply
```

## Wire up the rest

| Output | Goes to |
|---|---|
| `wif_provider` | GitHub secret `GCP_E2E_WIF_PROVIDER` |
| `service_account_email` | GitHub secret `GCP_E2E_SERVICE_ACCOUNT` |
| `project` | GitHub variable `GCP_E2E_PROJECT` |

Add these under **Settings -> Secrets and variables -> Actions** in the
`jasonp2323/keda-gpu-scaler` repo, and make sure the `e2e-gcp` GitHub
**Environment** exists with required reviewers (see
`tests/terratest/README.md` "OIDC / Cloud Authentication Setup").

Then point the main stack's partial backend
(`infra/terraform/gcp/backend.tf`) at the bucket:

```bash
cd infra/terraform/gcp
terraform init \
  -backend-config="bucket=$(terraform -chdir=../bootstrap output -raw state_bucket)" \
  -backend-config="prefix=e2e/gcp/<cluster_name>"
```

`terraform output backend_config_hint` (run from this directory) prints the
same flags with `<cluster_name>` left as a placeholder — it should match the
main stack's `var.cluster_name` so concurrent/successive e2e runs don't
collide on the same state object.

## What NOT to do

- Don't add a `backend` block to this directory — it must stay local-state.
- Don't re-run `terraform apply` here as part of routine e2e runs — this is
  one-time account/project setup, not part of the per-run provision/destroy
  cycle.
- Don't widen the service account's roles beyond what's granted in `oidc.tf`
  (`container.admin`, `compute.networkAdmin`, `iam.serviceAccountUser` at the
  project level, `storage.objectAdmin` scoped to the state bucket only)
  without updating `tests/terratest/README.md` to match.
