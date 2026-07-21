# AWS bootstrap

**Run once, by hand, before anything else in `infra/terraform/aws/`.** Creates:

| Resource | Purpose |
|---|---|
| `aws_s3_bucket.state` (versioned, SSE-S3, public-access-block) | Remote Terraform state for the main stack |
| `aws_dynamodb_table.lock` | State locking (`PAY_PER_REQUEST`, hash key `LockID`) |
| `aws_iam_openid_connect_provider.github` | Trust for `token.actions.githubusercontent.com` |
| `aws_iam_role.deployer` + inline policy | Role GitHub Actions assumes to plan/apply the main stack |

Uses **local state** (no backend block) — the S3 bucket it creates doesn't exist
yet to point at. Keep `terraform.tfstate` for this directory safe, or re-run
`apply` (idempotent) — but the bucket name must stay unchanged once other
configs depend on it.

Apply with credentials that can create IAM roles/policies, an OIDC provider, an
S3 bucket, and a DynamoDB table (e.g. your own admin AWS creds — not the role
this config creates).

## Usage

```bash
cd infra/terraform/aws/bootstrap
cp terraform.tfvars.example terraform.tfvars   # edit state_bucket_name at minimum
terraform init
terraform apply
```

## Wire up the rest

| Output | Goes to |
|---|---|
| `role_arn` | GitHub secret `AWS_E2E_ROLE_ARN` |
| `region` | GitHub variable `AWS_E2E_REGION` |
| `backend_config_hint` | prints the `terraform init -backend-config=...` command to run from `infra/terraform/aws/` (fill in `<cluster_name>`) |

State key scheme is `e2e/aws/<cluster_name>.tfstate`, so multiple clusters
share one bucket without clobbering each other's state.

The deployer role's permissions are the same scoped policy documented in
`tests/terratest/README.md` (### AWS) — EC2/autoscaling, EKS, the
cluster/node/IRSA IAM roles, the secrets-encryption KMS key, control-plane
CloudWatch logs, `sts:GetCallerIdentity` — plus S3/DynamoDB permissions scoped
to just the state bucket and lock table this config creates.

## Cost

S3 + DynamoDB (`PAY_PER_REQUEST`) and the IAM role/OIDC provider are
effectively free. No `terraform destroy` expected in normal operation — this
is long-lived, shared infrastructure, not a per-test resource.
