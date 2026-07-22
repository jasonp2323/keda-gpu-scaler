# Terratest E2E Suite: Real GPU Scaling Validation

The **Tier-3 end-to-end test suite** for KEDA GPU Scaler: runs real `terraform apply` against live cloud infrastructure and asserts autoscaling behaviour on actual NVIDIA hardware.

## Quickstart

End-to-end setup, once per cloud you want to test. Each step links to its full details below.

1. **Prerequisites** — install Go 1.25+, Terraform 1.15.6, and the cloud CLI; request GPU quota for your region/family (0 by default on fresh accounts). See [Prerequisites](#prerequisites).
2. **Bootstrap (run once)** — `cd infra/terraform/<cloud>/bootstrap`, copy `terraform.tfvars.example` to `terraform.tfvars` and set at least the globally-unique state bucket/account name (and, for repos created after 2026-07-15, the `github_owner_id`/`github_repo_id`), then `terraform apply`. Creates the remote-state backend **and** the GitHub OIDC role/app/service account. See [Bootstrap](#bootstrap-run-once-per-cloud).
3. **Copy the outputs into GitHub** — run `terraform output` in the bootstrap dir; put the role ARN / client IDs / WIF provider / state bucket names into repo **Settings → Secrets and variables** using the exact names in the [GitHub Actions configuration](#github-actions-configuration-secrets--variables) tables.
4. **Create Environments** — `e2e-aws` / `e2e-azure` / `e2e-gcp` under **Settings → Environments**, each with required reviewers (the approval gate for paid apply runs).
5. **Enable Actions** — forks have Actions disabled by default: open the **Actions** tab and enable them. Optionally add the `INFRACOST_API_KEY` secret for cost estimates.
6. **Run it:**
   - Open a PR touching `infra/terraform/**` → the credential-less gates (fmt/validate/tflint/checkov/docs) run automatically — **no cloud connection needed**. Run a `terraform plan` on demand from **Actions → E2E Plan (Manual)** (pick the cloud).
   - Trigger the real GPU apply from **Actions → E2E Cloud Tests (Apply and Destroy) → Run workflow** → pick the cloud(s) and type `apply` in the confirm box. To tear down a leftover cluster, use **Actions → E2E Destroy (Manual)** (pick the cloud, enter the cluster name, type `destroy`). For local runs see [Building & Running Tests](#building--running-tests).

## What the Suite Is

**Location:** `tests/terratest/` — a separate Go module (`github.com/pmady/keda-gpu-scaler/tests/terratest`), isolated from the root module so Terratest's large dependency tree stays out of the lean CGO/NVML scaler build.

**Scope:** Provisions a real GPU Kubernetes cluster (EKS/AKS/GKE) with the NVIDIA GPU operator, KEDA, and keda-gpu-scaler, asserts autoscaling on actual NVIDIA hardware, then destroys all infrastructure. This is the automated version of the manual validation checklist in `infra/AGENTS.md`.

## E2E Test Flow

Each cloud's test follows this sequence:

1. `terraform apply` the stack (cluster + 1 GPU node + gpu-operator + KEDA + keda-gpu-scaler chart + e2e fixtures).
2. The `keda-gpu-scaler` DaemonSet (namespace `keda`) becomes fully available.
3. The `demo-app-gpu-scaler` ScaledObject (namespace `default`) reports Ready.
4. At idle, the `demo-app` Deployment sits at 1 replica.
5. Applying `infra/terraform/<cloud>/demo/gpu-load.yaml` (a `gpu-burn` Job) drives the GPU busy → `demo-app` scales above 1.
6. Deleting the load → `demo-app` returns to 1 replica.
7. `terraform destroy` runs via a deferred call (always, even on failure).

## Building & Running Tests

Each cloud is independent. Run via Go build tags or Makefile:

### Go (`go test` direct)
```bash
# AWS
go test -tags e2e_aws -timeout 60m -v ./tests/terratest/

# Azure
go test -tags e2e_azure -timeout 60m -v ./tests/terratest/

# GCP
go test -tags e2e_gcp -timeout 60m -v ./tests/terratest/
```

Test function names: `TestAWSGPUScalerE2E`, `TestAzureGPUScalerE2E`, `TestGCPGPUScalerE2E`.

### Makefile
```bash
make test-terratest-aws
make test-terratest-azure
make test-terratest-gcp
```

## Prerequisites

- **Go 1.25+**
- **Terraform 1.15.6** (pinned by each stack's `.terraform-version` file)
- **Cloud CLI** on `PATH`: AWS `aws`, Azure `az`, GCP `gcloud` + `gke-gcloud-auth-plugin`
- **Cloud credentials** with permissions to create clusters, networking, and node pools.
- **GPU service quota** — typically zero on fresh accounts, per-region and per-GPU-family. **Request an increase before running**, or provisioning fails at node creation:
  - **AWS:** "Running On-Demand G and VT instances" quota `L-DB2E81BA` (measured in vCPUs) in the target region.
  - **Azure:** NC/ND/NV VM-family vCPU quota in the target location.
  - **GCP:** Global GPU quota + per-region, per-type GPU quota.

## Bootstrap (run once per cloud)

Each cloud has an `infra/terraform/<cloud>/bootstrap/` config that you apply **once** (it uses local state) to create the prerequisites the pipeline depends on:

1. the **remote Terraform state backend** — an S3 bucket with native state locking (AWS), a storage account + container (Azure), or a GCS bucket (GCP); and
2. the **GitHub OIDC** identity provider, deployer role/app/service account, and least-privilege permissions — see [OIDC / Cloud Authentication Setup](#oidc--cloud-authentication-setup) for the manual steps bootstrap automates.

After `terraform apply` in a bootstrap dir:

- Put its OIDC outputs into the GitHub secrets/variables (`*_ROLE_ARN` / `*_CLIENT_ID` / `*_WIF_PROVIDER`, etc.).
- Put its state-backend outputs into the `E2E_*_STATE_*` variables (see the table below) so CI — and the tests — can reach the backend.

The main stacks carry a **partial** backend block (`backend "s3"/"azurerm"/"gcs" {}`); the tests supply the bucket/key at init via these variables, keyed per run. This means the bootstrap must be applied before the suite can run (locally or in CI).

## GitHub Actions configuration (secrets & variables)

Everything the workflows read, in one place. Add these under **Settings → Secrets and variables → Actions**. **Most values are outputs of the per-cloud `bootstrap/`** — apply the bootstrap, run `terraform output`, and copy them in. (Note the naming: the GitHub *variable* `AWS_E2E_STATE_BUCKET` is mapped by the workflow to the test env var `E2E_AWS_STATE_BUCKET` — set the GitHub name shown here.)

### Secrets

| Secret | Used by | Where it comes from |
|--------|---------|---------------------|
| `AWS_E2E_ROLE_ARN` | e2e-apply, plan-aws | `aws/bootstrap` output `role_arn` |
| `AZURE_E2E_CLIENT_ID` | e2e-apply, plan-azure | `azure/bootstrap` output `client_id` |
| `AZURE_E2E_TENANT_ID` | e2e-apply, plan-azure | `azure/bootstrap` output `tenant_id` |
| `AZURE_E2E_SUBSCRIPTION_ID` | e2e-apply, plan-azure | `azure/bootstrap` output `subscription_id` |
| `GCP_E2E_WIF_PROVIDER` | e2e-apply, plan-gcp | `gcp/bootstrap` output `wif_provider` |
| `GCP_E2E_SERVICE_ACCOUNT` | e2e-apply, plan-gcp | `gcp/bootstrap` output `service_account_email` |
| `INFRACOST_API_KEY` | infra-validate (cost) | free key from infracost.io — **optional**; cost steps skip without it |
| `GITHUB_TOKEN` | PR comments, docs push | **auto-provided by GitHub — do not set** |

### Variables

| Variable | Used by | Where it comes from |
|----------|---------|---------------------|
| `AWS_E2E_REGION` | e2e-apply, plan-aws | your target AWS region (match `aws/bootstrap` `region`) |
| `AWS_E2E_STATE_BUCKET` | e2e-apply, plan-aws | `aws/bootstrap` output `state_bucket` |
| `AZURE_E2E_STATE_RESOURCE_GROUP` | e2e-apply, plan-azure | `azure/bootstrap` output `state_resource_group` |
| `AZURE_E2E_STATE_STORAGE_ACCOUNT` | e2e-apply, plan-azure | `azure/bootstrap` output `state_storage_account` |
| `AZURE_E2E_STATE_CONTAINER` | e2e-apply, plan-azure | `azure/bootstrap` output `state_container` (default `tfstate`) |
| `GCP_E2E_PROJECT` | e2e-apply, plan-gcp | your GCP project id |
| `GCP_E2E_STATE_BUCKET` | e2e-apply, plan-gcp | `gcp/bootstrap` output `state_bucket` |

### Environments

Create `e2e-aws`, `e2e-azure`, `e2e-gcp` under **Settings → Environments**, each with required reviewers — the approval gate for the paid apply jobs in `e2e-apply.yaml`. Only the `plan-*` and e2e apply/destroy jobs consume any of the above; the credential-less jobs (`fmt`/`validate`/`tflint`/`checkov`/`docs`) need none of it.

## Configuration (Environment Variables)

All variables are optional unless marked **required**.

| Variable | Cloud | Default | Notes |
|----------|-------|---------|-------|
| `E2E_CLUSTER_NAME` | All | `keda-gpu-scaler-e2e-<suffix>` | Full cluster name; CI sets it unique per run. `GITHUB_RUN_ID` used as suffix when set. |
| `E2E_K8S_VERSION` | All | `1.33` | Kubernetes version for the cluster. |
| `E2E_SCALER_IMAGE_REPOSITORY` | All | `ghcr.io/pmady/keda-gpu-scaler` | Container image repository for keda-gpu-scaler. |
| `E2E_SCALER_IMAGE_TAG` | All | `v0.5.0` | Container image tag for keda-gpu-scaler. |
| `E2E_HELM_TIMEOUT` | All | Cloud-specific (see below) | Helm chart deployment timeout. |
| `GITHUB_RUN_ID` | All | — | GitHub Actions run ID; used as cluster-name suffix when set. |
| `AWS_REGION` | AWS | `us-east-2` | AWS region. |
| `E2E_GPU_INSTANCE_TYPE` | AWS | `g5.xlarge` | EC2 instance type for GPU node. |
| `E2E_HELM_TIMEOUT` | AWS | `600` | Helm timeout in seconds (10 min). |
| `ARM_SUBSCRIPTION_ID` | Azure | — | **REQUIRED.** Azure subscription ID; test fails fast without it. |
| `E2E_AZURE_LOCATION` | Azure | `eastus` | Azure region/location. |
| `E2E_AZURE_RESOURCE_GROUP` | Azure | `<cluster_name>-rg` | Azure resource group name. |
| `E2E_GPU_VM_SIZE` | Azure | `Standard_NC4as_T4_v3` | Azure VM size for GPU node. |
| `E2E_HELM_TIMEOUT` | Azure | `900` | Helm timeout in seconds (15 min). |
| `E2E_GCP_PROJECT` or `GOOGLE_PROJECT` | GCP | — | **REQUIRED.** GCP project ID; test fails fast without it. |
| `E2E_GCP_REGION` | GCP | `us-central1` | GCP region. |
| `E2E_GCP_ZONE` | GCP | `us-central1-a` | GCP zone. |
| `E2E_GPU_MACHINE_TYPE` | GCP | `n1-standard-4` | GCP machine type for GPU node. |
| `E2E_GPU_TYPE` | GCP | `nvidia-tesla-t4` | GCP GPU type. |
| `E2E_HELM_TIMEOUT` | GCP | `1800` | Helm timeout in seconds (30 min). |
| `E2E_AWS_STATE_BUCKET` | AWS | — | **REQUIRED (remote backend).** S3 bucket — `aws/bootstrap` `state_bucket` output. |
| `E2E_AZURE_STATE_RESOURCE_GROUP` | Azure | — | **REQUIRED (remote backend).** State resource group — `azure/bootstrap` output. |
| `E2E_AZURE_STATE_STORAGE_ACCOUNT` | Azure | — | **REQUIRED (remote backend).** State storage account — `azure/bootstrap` output. |
| `E2E_AZURE_STATE_CONTAINER` | Azure | `tfstate` | Blob container — `azure/bootstrap` output. |
| `E2E_GCP_STATE_BUCKET` | GCP | — | **REQUIRED (remote backend).** GCS bucket — `gcp/bootstrap` `state_bucket` output. |
| `E2E_ARTIFACTS_DIR` | All | — | Directory the test writes failure diagnostics to. CI sets it and uploads the contents as an artifact; unset (local) means console-only. |

The state key is derived per run as `e2e/<cloud>/<cluster_name>.tfstate` (GCS uses prefix `e2e/gcp/<cluster_name>`), so concurrent runs with unique cluster names never collide on state.

## Cost & Teardown ⚠️

**These tests provision REAL clusters and bill real money by the hour.** Estimated cost: ~$0.55–$1.20/hr per cloud stack, depending on region and GPU type. Always watch the logs for `terraform destroy` completion.

**Automatic teardown:** the test defers `terraform destroy`, which runs on exit (success or failure). CI adds a safety-net `terraform destroy` job if the test process is killed.

**Finding leftovers:** all resources are tagged `Project=keda-gpu-scaler` (GCP uses label `project=keda-gpu-scaler`). If a run is interrupted, find and destroy manually:
```bash
cd infra/terraform/<cloud>
terraform destroy
```

## CI Workflow

**`e2e-apply.yaml`** — the apply-level suite:
- **Trigger:** manual `workflow_dispatch` — pick cloud(s), type `apply` to confirm. A run self-destroys when it finishes; use **E2E Destroy (Manual)** for a cluster that leaked past that.
- **Auth:** OIDC/federated cloud auth — no long-lived keys stored. See [OIDC / Cloud Authentication Setup](#oidc--cloud-authentication-setup).
- **Approval:** gated per-cloud by a GitHub Environment — see [Who can deploy](#who-can-deploy--how-its-gated) for what that does and doesn't guarantee.
- **Diagnostics:** on failure the test dumps scaler pod logs, node status, `demo-app`/ScaledObject describe, and recent events (to `E2E_ARTIFACTS_DIR`); the job uploads those plus the full `go test` log as a build artifact (`if: always()`), so a failed run is debuggable after the fact.
- **Scope:** not run on every PR/push, matching the repo's "infra CI is manual only" stance.

**Related workflows:**
- **`infra-validate.yaml`** — per-PR gates on `infra/terraform/**`, fully credential-less: `terraform fmt`, `validate`, `tflint`, `checkov` (blocking); a `terraform-docs` job that keeps each stack README's inputs/outputs table current.
- **`e2e-plan.yml`** — manual `workflow_dispatch` (pick a cloud) that runs `terraform plan` with OIDC and saves the plan as an artifact + tf-summarize digest + job summary. Moved out of the PR pipeline so PRs never require cloud connectivity; runs in the `e2e-<cloud>` Environment (same OIDC subject as apply/destroy).

## Who can deploy / how it's gated

The apply and destroy workflows are **manual (`workflow_dispatch`)**, so two guards apply on **every** GitHub plan and repo visibility:

1. **Write access** — only users with write/maintain/admin can trigger a run; a read-only collaborator or outsider cannot.
2. **A typed confirmation** — `apply` for the E2E run, `destroy` for teardown — guards against an accidental click.

A mandatory **second-person approval** (GitHub environment *required reviewers*) is an optional layer whose availability depends on the repo:

| Repo | Free / Pro / Team | Enterprise |
|------|:--:|:--:|
| **Public** | ✅ required reviewers | ✅ |
| **Private / Internal** | ❌ not available | ✅ |

The workflows always declare `environment: e2e-<cloud>` (needed for the OIDC subject), so where required reviewers *are* available they take effect automatically; where they aren't (a private repo below Enterprise) the run proceeds under guards 1–2. **To add a hard second-person gate without Enterprise:** make the repo public, or add an issue-comment approval step (e.g. a pinned `manual-approval` action) to the deploy/destroy workflows.

## OIDC / Cloud Authentication Setup

CI never stores long-lived cloud keys. Instead, GitHub Actions mints a short-lived OIDC token per job and exchanges it for temporary cloud credentials (AWS `AssumeRoleWithWebIdentity`, Azure federated credential, GCP Workload Identity Federation). This section is the one-time setup a maintainer runs per cloud account.

Three workflows consume these credentials, and **all run in a GitHub Environment** (`e2e-aws` / `e2e-azure` / `e2e-gcp`): `.github/workflows/e2e-apply.yaml` (the e2e apply job), `.github/workflows/e2e-plan.yml` (the manual `plan-*` jobs), and `.github/workflows/e2e-destroy.yaml` (the manual destroy jobs). Because all three run in the Environment, they present the **same** OIDC subject: `repo:<repo>:environment:e2e-<cloud>`. (The bootstrap also emits a `pull_request` subject — a leftover from when plan ran on PRs; it's now unused by any workflow. Harmless to leave; drop it for tighter least-privilege.)

### AWS

1. **Create the GitHub OIDC provider** in the target AWS account (once per account):
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create an IAM role** federated to that provider, trusting:
   - `repo:jasonp2323/keda-gpu-scaler:environment:e2e-aws`
   - `repo:jasonp2323/keda-gpu-scaler:pull_request` (unused leftover — see above; safe to omit)

   **Immutable `sub` (repos created after 2026-07-15):** GitHub issues the `sub` claim as `repo:OWNER@OWNER_ID/REPO@REPO_ID:...` for newer repos. A trust policy matching only the classic `repo:OWNER/REPO:...` form fails with *"Not authorized to perform sts:AssumeRoleWithWebIdentity."* — so match **both**. Fetch the numeric IDs:
   ```bash
   gh api repos/jasonp2323/keda-gpu-scaler --jq '{owner_id: .owner.id, repo_id: .id}'
   ```

   Trust policy allowing both formats:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
           },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": [
               "repo:jasonp2323/keda-gpu-scaler:environment:e2e-aws",
               "repo:jasonp2323/keda-gpu-scaler:pull_request",
               "repo:jasonp2323@<OWNER_ID>/keda-gpu-scaler@<REPO_ID>:environment:e2e-aws",
               "repo:jasonp2323@<OWNER_ID>/keda-gpu-scaler@<REPO_ID>:pull_request"
             ]
           }
         }
       }
     ]
   }
   ```
   The `aws/bootstrap` config builds this list for you — set its `github_owner_id` / `github_repo_id` variables (leave empty to trust the classic form only). Looser alternative: replace the four subjects with `"repo:jasonp2323/keda-gpu-scaler:*"` and its immutable twin `"repo:jasonp2323@<OWNER_ID>/keda-gpu-scaler@<REPO_ID>:*"`.

3. **Attach a permissions policy.** Rather than `AdministratorAccess`, attach a policy scoped to the services this stack actually provisions: EC2/VPC networking, EKS + the managed node group, the cluster/node IAM roles and IRSA OIDC provider, the EKS secrets-encryption KMS key, and control-plane CloudWatch logs. Save this as `deployer-policy.json`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "NetworkingAndCompute",
         "Effect": "Allow",
         "Action": [
           "ec2:*",
           "autoscaling:Describe*",
           "autoscaling:CreateOrUpdateTags",
           "autoscaling:DeleteTags"
         ],
         "Resource": "*"
       },
       {
         "Sid": "EKS",
         "Effect": "Allow",
         "Action": "eks:*",
         "Resource": "*"
       },
       {
         "Sid": "IAMClusterNodeAndIRSARoles",
         "Effect": "Allow",
         "Action": [
           "iam:CreateRole",
           "iam:DeleteRole",
           "iam:GetRole",
           "iam:ListRolePolicies",
           "iam:ListAttachedRolePolicies",
           "iam:ListInstanceProfilesForRole",
           "iam:AttachRolePolicy",
           "iam:DetachRolePolicy",
           "iam:PutRolePolicy",
           "iam:DeleteRolePolicy",
           "iam:GetRolePolicy",
           "iam:PassRole",
           "iam:TagRole",
           "iam:UntagRole",
           "iam:CreatePolicy",
           "iam:DeletePolicy",
           "iam:GetPolicy",
           "iam:GetPolicyVersion",
           "iam:ListPolicyVersions",
           "iam:CreatePolicyVersion",
           "iam:DeletePolicyVersion",
           "iam:CreateInstanceProfile",
           "iam:DeleteInstanceProfile",
           "iam:GetInstanceProfile",
           "iam:AddRoleToInstanceProfile",
           "iam:RemoveRoleFromInstanceProfile",
           "iam:TagInstanceProfile",
           "iam:CreateOpenIDConnectProvider",
           "iam:DeleteOpenIDConnectProvider",
           "iam:GetOpenIDConnectProvider",
           "iam:TagOpenIDConnectProvider",
           "iam:CreateServiceLinkedRole"
         ],
         "Resource": "*"
       },
       {
         "Sid": "SecretsEncryptionKMS",
         "Effect": "Allow",
         "Action": [
           "kms:CreateKey",
           "kms:CreateAlias",
           "kms:DeleteAlias",
           "kms:DescribeKey",
           "kms:GetKeyPolicy",
           "kms:GetKeyRotationStatus",
           "kms:ListAliases",
           "kms:ListResourceTags",
           "kms:PutKeyPolicy",
           "kms:EnableKeyRotation",
           "kms:ScheduleKeyDeletion",
           "kms:CreateGrant",
           "kms:TagResource",
           "kms:UntagResource"
         ],
         "Resource": "*"
       },
       {
         "Sid": "ControlPlaneLogging",
         "Effect": "Allow",
         "Action": [
           "logs:CreateLogGroup",
           "logs:DeleteLogGroup",
           "logs:DescribeLogGroups",
           "logs:PutRetentionPolicy",
           "logs:ListTagsForResource",
           "logs:TagResource",
           "logs:UntagResource"
         ],
         "Resource": "*"
       },
       {
         "Sid": "Identity",
         "Effect": "Allow",
         "Action": "sts:GetCallerIdentity",
         "Resource": "*"
       }
     ]
   }
   ```
   Then create the role and attach the policy inline:
   ```bash
   aws iam create-role \
     --role-name keda-gpu-scaler-e2e \
     --assume-role-policy-document file://trust-policy.json

   aws iam put-role-policy \
     --role-name keda-gpu-scaler-e2e \
     --policy-name keda-gpu-scaler-e2e-deployer \
     --policy-document file://deployer-policy.json
   ```
   This is scoped by **service + action** — it drops everything `AdministratorAccess` would grant outside these services (no S3, RDS, billing, Organizations, etc.). It is **not** scoped per-resource-ARN: the cluster, roles, and KMS key names are generated during `apply`, so ARN-level conditions aren't practical for a from-scratch build. To tighten further, replace `ec2:*`/`eks:*` with explicit action lists; if a first `apply` returns an `AccessDenied`, add the named action and re-run.

4. **Store the role ARN and region** in the repo:
   - Secret `AWS_E2E_ROLE_ARN` = the role's ARN.
   - Variable `AWS_E2E_REGION` = target region (e.g. `us-east-2`).

### Azure

1. **Create an app registration** (or user-assigned managed identity) and note its client ID and tenant ID:
   ```bash
   az ad app create --display-name keda-gpu-scaler-e2e
   az ad sp create --id <APP_CLIENT_ID>
   ```

2. **Add federated credentials** on the app — one per subject that needs to authenticate:
   ```bash
   az ad app federated-credential create \
     --id <APP_OBJECT_ID> \
     --parameters '{
       "name": "e2e-azure-environment",
       "issuer": "https://token.actions.githubusercontent.com",
       "subject": "repo:jasonp2323/keda-gpu-scaler:environment:e2e-azure",
       "audiences": ["api://AzureADTokenExchange"]
     }'

   # Optional: also let infra-validate's plan-azure job (no Environment) authenticate
   az ad app federated-credential create \
     --id <APP_OBJECT_ID> \
     --parameters '{
       "name": "e2e-azure-pull-request",
       "issuer": "https://token.actions.githubusercontent.com",
       "subject": "repo:jasonp2323/keda-gpu-scaler:pull_request",
       "audiences": ["api://AzureADTokenExchange"]
     }'
   ```

   **Immutable `sub`:** unlike AWS's wildcard-friendly trust policy, federated credentials match the `sub` claim **exactly** — a repo issuing the immutable `repo:OWNER@OWNER_ID/REPO@REPO_ID:...` form (repos created after 2026-07-15) needs a **second credential per subject** in that form (e.g. `repo:jasonp2323@<OWNER_ID>/keda-gpu-scaler@<REPO_ID>:environment:e2e-azure`). `azure/bootstrap` adds these automatically when you set its `github_owner_id` / `github_repo_id` variables (fetch the IDs with the `gh api` command shown in the AWS section).

3. **Grant the app access via a custom role.** This stack creates only a resource group and an AKS cluster with a **system-assigned** identity (no custom VNet, no `azurerm_role_assignment`), so it needs neither broad `Contributor` nor `User Access Administrator`. Define a role scoped to just those providers — save as `azure-deployer-role.json`:
   ```json
   {
     "Name": "keda-gpu-scaler-e2e-deployer",
     "IsCustom": true,
     "Description": "Deploy the keda-gpu-scaler AKS e2e stack: a resource group and an AKS cluster with a system-assigned identity.",
     "Actions": [
       "Microsoft.Resources/subscriptions/read",
       "Microsoft.Resources/subscriptions/resourceGroups/read",
       "Microsoft.Resources/subscriptions/resourceGroups/write",
       "Microsoft.Resources/subscriptions/resourceGroups/delete",
       "Microsoft.ContainerService/managedClusters/*",
       "Microsoft.ContainerService/locations/*/read"
     ],
     "NotActions": [],
     "DataActions": [],
     "NotDataActions": [],
     "AssignableScopes": ["/subscriptions/<SUBSCRIPTION_ID>"]
   }
   ```
   Create the role and assign it to the app:
   ```bash
   az role definition create --role-definition azure-deployer-role.json

   az role assignment create \
     --assignee <APP_CLIENT_ID> \
     --role "keda-gpu-scaler-e2e-deployer" \
     --scope /subscriptions/<SUBSCRIPTION_ID>
   ```
   Add `Microsoft.Authorization/roleAssignments/write` (or the built-in `User Access Administrator`) only if you later introduce a custom VNet or explicit `azurerm_role_assignment` resources — the current stack needs neither.

4. **Store as secrets:** `AZURE_E2E_CLIENT_ID`, `AZURE_E2E_TENANT_ID`, `AZURE_E2E_SUBSCRIPTION_ID`.

### GCP

1. **Create a Workload Identity Pool and OIDC provider**, restricted to this repo via an attribute condition:
   ```bash
   gcloud iam workload-identity-pools create keda-gpu-scaler-pool \
     --project=<PROJECT_ID> \
     --location=global \
     --display-name="keda-gpu-scaler e2e"

   gcloud iam workload-identity-pools providers create-oidc keda-gpu-scaler-provider \
     --project=<PROJECT_ID> \
     --location=global \
     --workload-identity-pool=keda-gpu-scaler-pool \
     --issuer-uri="https://token.actions.githubusercontent.com" \
     --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
     --attribute-condition="assertion.repository == 'jasonp2323/keda-gpu-scaler'"
   ```

2. **Create a service account** with roles scoped to what the stack provisions — GKE (`container.admin`), the custom VPC + subnet (`compute.networkAdmin`, far narrower than `compute.admin`), and permission to attach the default node service account (`iam.serviceAccountUser`):
   ```bash
   gcloud iam service-accounts create keda-gpu-scaler-e2e \
     --project=<PROJECT_ID> \
     --display-name="keda-gpu-scaler e2e"

   for role in roles/container.admin roles/compute.networkAdmin roles/iam.serviceAccountUser; do
     gcloud projects add-iam-policy-binding <PROJECT_ID> \
       --member="serviceAccount:keda-gpu-scaler-e2e@<PROJECT_ID>.iam.gserviceaccount.com" \
       --role="$role"
   done
   ```
   `container.admin` is already GKE-scoped and `compute.networkAdmin` covers only the VPC network/subnetwork the stack creates — GKE provisions the node VMs via its own service agent, so `compute.admin` isn't needed. Add `roles/iam.serviceAccountAdmin` only if you change the stack to create its own node service account.

3. **Bind the pool to impersonate the service account**, scoped to this repo:
   ```bash
   gcloud iam service-accounts add-iam-policy-binding \
     keda-gpu-scaler-e2e@<PROJECT_ID>.iam.gserviceaccount.com \
     --project=<PROJECT_ID> \
     --role=roles/iam.workloadIdentityUser \
     --member="principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/keda-gpu-scaler-pool/attribute.repository/jasonp2323/keda-gpu-scaler"
   ```

4. **Store:**
   - Secret `GCP_E2E_WIF_PROVIDER` = full provider resource name (`projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/keda-gpu-scaler-pool/providers/keda-gpu-scaler-provider`).
   - Secret `GCP_E2E_SERVICE_ACCOUNT` = `keda-gpu-scaler-e2e@<PROJECT_ID>.iam.gserviceaccount.com`.
   - Variable `GCP_E2E_PROJECT` = `<PROJECT_ID>`.

### GitHub side

- Add all secrets/variables above under **Settings → Secrets and variables → Actions** (secrets for credentials, variables for the non-secret region/project values).
- Create the `e2e-aws` / `e2e-azure` / `e2e-gcp` [Environments](#environments) — they supply the OIDC subject the trust policy expects, and, on a **public repo or GitHub Enterprise**, enforce required-reviewer approval before a run proceeds. See [Who can deploy](#who-can-deploy--how-its-gated) for what applies on a private repo below Enterprise.
- The credential-less gates (`fmt`, `validate`, `tflint`, `checkov`) need none of this setup — only the `plan-*` jobs and the e2e apply/destroy jobs authenticate to a cloud.
- **Infracost (optional):** the plan and apply jobs' Infracost step needs the `INFRACOST_API_KEY` secret (free key from infracost.io). Without it the cost step skips and the rest of the pipeline is unaffected.

### Reusing existing OIDC resources

Some of these resources are account/tenant-global and may already exist (an org that already wired GitHub OIDC for other repos). Each bootstrap can **reference** an existing one instead of failing on a duplicate — flip the toggle to `false`:

| Cloud | Toggle (`false` = reuse) | Referenced resource |
|-------|--------------------------|---------------------|
| AWS   | `create_github_oidc_provider`   | the account's `token.actions.githubusercontent.com` OIDC provider |
| GCP   | `create_workload_identity_pool` | the Workload Identity Pool + provider (`var.pool_id` / `var.provider_id`) |
| Azure | `create_app_registration`       | the app registration + service principal (by `var.app_display_name`; must be unique in the tenant) |

With the toggle `false` the bootstrap looks the resource up and wires the rest (role, federated credentials, bindings) onto it — no duplicate created.

Alternatively, adopt an already-created resource into this config's state with `terraform import`, then apply normally. The `[0]` index is required because these resources are now `count`-based:

```bash
# AWS — existing OIDC provider
terraform import 'aws_iam_openid_connect_provider.github[0]' \
  arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com

# GCP — existing pool + provider
terraform import 'google_iam_workload_identity_pool.github[0]' \
  projects/<PROJECT_ID>/locations/global/workloadIdentityPools/<POOL_ID>
terraform import 'google_iam_workload_identity_pool_provider.github[0]' \
  projects/<PROJECT_ID>/locations/global/workloadIdentityPools/<POOL_ID>/providers/<PROVIDER_ID>

# Azure — existing app registration + service principal
terraform import 'azuread_application.e2e[0]' /applications/<APP_OBJECT_ID>
terraform import 'azuread_service_principal.e2e[0]' <SP_OBJECT_ID>
```

## Coverage Note

**These tests are the only automated coverage of real-GPU behaviour.** The root module (`cmd/`, `pkg/`) uses a mock GPU collector for unit tests. Real NVIDIA hardware validation happens only here.
