# AWS bootstrap

**Run this ONCE, by hand, before anything else in `infra/terraform/aws/`.**
It creates the infrastructure the main stack needs just to start:

- an S3 bucket + DynamoDB table for the main stack's remote Terraform state;
- a GitHub Actions OIDC provider + IAM role (`keda-gpu-scaler-e2e`) so CI can
  authenticate without long-lived AWS keys.

This config itself has **no backend block and uses local state**. That's not
an oversight — it's the chicken-and-egg root: the remote-state backend it
creates doesn't exist yet when this runs. Keep `terraform.tfstate` for this
directory somewhere safe (or re-run `apply` — everything here is idempotent
and cheap to recreate, but the S3 bucket name must stay unique/unchanged once
other Terraform configs depend on it).

Apply this with credentials that can create IAM roles/policies, an IAM OIDC
provider, an S3 bucket, and a DynamoDB table (e.g. your own admin AWS creds —
NOT the role this config creates).

## Usage

```bash
cd infra/terraform/aws/bootstrap
cp terraform.tfvars.example terraform.tfvars   # edit state_bucket_name at minimum
terraform init
terraform apply
```

## After `apply`, wire up the rest of the repo

1. **GitHub OIDC secret/variable** (used by `.github/workflows/e2e-cloud.yaml`
   and `infra-validate.yaml` — see `tests/terratest/README.md`):
   - Secret `AWS_E2E_ROLE_ARN` = `terraform output -raw role_arn`
   - Variable `AWS_E2E_REGION` = `terraform output -raw region`

2. **Init the main stack's S3 backend** using this config's outputs:

   ```bash
   terraform output backend_config_hint
   ```

   prints the exact `terraform init -backend-config=...` command to run from
   `infra/terraform/aws/` (fill in `<cluster_name>`). The state key scheme is
   `e2e/aws/<cluster_name>.tfstate`, so multiple clusters/environments can
   share one bucket without clobbering each other's state.

## What this creates

| Resource | Purpose |
|---|---|
| `aws_s3_bucket.state` (+ versioning, SSE-S3, public-access-block) | Remote Terraform state for the main stack |
| `aws_dynamodb_table.lock` | State locking (`PAY_PER_REQUEST`, hash key `LockID`) |
| `aws_iam_openid_connect_provider.github` | Trust for `token.actions.githubusercontent.com` |
| `aws_iam_role.deployer` + inline policy | Role GitHub Actions assumes to plan/apply the main stack |

The deployer role's permissions are the same scoped, service-level policy
documented in `tests/terratest/README.md` (### AWS) — EC2/autoscaling, EKS,
the cluster/node/IRSA IAM roles, the secrets-encryption KMS key, control-plane
CloudWatch logs, plus `sts:GetCallerIdentity` — with added S3/DynamoDB
permissions scoped to just the state bucket and lock table this config
creates, so CI can also run `terraform init`/`plan`/`apply` against the
remote backend.

## Cost

The S3 bucket and DynamoDB table (`PAY_PER_REQUEST`) are effectively free at
this scale. The IAM role/OIDC provider cost nothing. There is no
`terraform destroy` step expected here in normal operation — this is
long-lived, shared infrastructure, not a per-test resource.
