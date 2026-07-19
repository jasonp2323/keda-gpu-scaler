# Terratest E2E Suite: Real GPU Scaling Validation

This is the **Tier-3 end-to-end test suite** for KEDA GPU Scaler. It runs REAL `terraform apply` against live cloud infrastructure and asserts autoscaling behaviour on actual NVIDIA hardware.

## What the Suite Is

**Location:** `tests/terratest/` — a separate Go module (`github.com/pmady/keda-gpu-scaler/tests/terratest`), isolated from the repo's root module so Terratest's large dependency tree stays out of the lean CGO/NVML scaler build.

**Scope:** Provisions a real GPU Kubernetes cluster (EKS/AKS/GKE) with the NVIDIA GPU operator, KEDA, and keda-gpu-scaler, then asserts autoscaling on actual NVIDIA hardware, then destroys all infrastructure.

This is the automated version of the manual validation checklist in `infra/AGENTS.md`.

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
- **Cloud CLI** on `PATH`:
  - AWS: `aws`
  - Azure: `az`
  - GCP: `gcloud` + `gke-gcloud-auth-plugin`
- **Cloud credentials** with permissions to create clusters, networking, and node pools.
- **GPU service quota** — typically zero on fresh accounts, per-region and per-GPU-family. **Request an increase BEFORE running or provisioning fails at node creation:**
  - **AWS:** "Running On-Demand G and VT instances" quota `L-DB2E81BA` (measured in vCPUs) in the target region.
  - **Azure:** NC/ND/NV VM-family vCPU quota in the target location.
  - **GCP:** Global GPU quota + per-region, per-type GPU quota.

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

## Cost & Teardown ⚠️

**These tests provision REAL clusters and bill real money by the hour.**

- Estimated cost: ~$0.55–$1.20/hr per cloud stack, depending on region and GPU type.
- **Always confirm teardown.** Watch the logs for `terraform destroy` completion.

**Automatic teardown:** The test defers `terraform destroy`, which runs on exit (success or failure). The CI workflow adds a safety-net `terraform destroy` job if the test process is killed.

**Finding leftovers:** All resources are tagged `Project=keda-gpu-scaler` (GCP uses label `project=keda-gpu-scaler`). If a run is interrupted, find and destroy manually:
```bash
cd infra/terraform/<cloud>
terraform destroy
```

## CI Workflow

- **Trigger:** `.github/workflows/e2e-cloud.yaml` via `workflow_dispatch` (manual, gated).
- **Inputs:** Select cloud(s); type `RUN` in the cost-confirm input.
- **Auth:** Uses OIDC/federated cloud auth — no long-lived keys stored. See [OIDC / Cloud Authentication Setup](#oidc--cloud-authentication-setup).
- **Scope:** Intentionally NOT run on every PR/push, matching the repo's "infra CI is manual only" stance.
- **Approval:** Each cloud has a per-cloud GitHub Environment requiring approval before running.

## OIDC / Cloud Authentication Setup

CI never stores long-lived cloud keys. Instead, GitHub Actions mints a short-lived OIDC token per job and exchanges it for temporary cloud credentials (AWS `AssumeRoleWithWebIdentity`, Azure federated credential, GCP Workload Identity Federation). This section is the one-time setup a maintainer runs per cloud account.

Two workflows consume these credentials:
- `.github/workflows/e2e-cloud.yaml` — the e2e apply/destroy jobs, gated by a GitHub **Environment** (`e2e-aws` / `e2e-azure` / `e2e-gcp`).
- `.github/workflows/infra-validate.yaml` — the advisory `plan-*` jobs, triggered on `pull_request` with **no Environment**.

These two trigger types present **different OIDC subjects** to the cloud provider, so trust policies/federated credentials must allow both if the plan jobs are also meant to authenticate.

### AWS

1. **Create the GitHub OIDC provider** in the target AWS account (once per account):
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create an IAM role** federated to that provider. The subject differs by workflow:
   - `e2e-cloud.yaml` (Environment `e2e-aws`): `repo:jasonp2323/keda-gpu-scaler:environment:e2e-aws`
   - `infra-validate.yaml` (`plan-aws`, no Environment): `repo:jasonp2323/keda-gpu-scaler:pull_request`

   Trust policy allowing both:
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
               "repo:jasonp2323/keda-gpu-scaler:pull_request"
             ]
           }
         }
       }
     ]
   }
   ```
   (Broader alternative if preferred: `"repo:jasonp2323/keda-gpu-scaler:*"` in place of the two explicit subjects.)

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
- Create the three GitHub **Environments** — `e2e-aws`, `e2e-azure`, `e2e-gcp` — under **Settings → Environments**, and add required reviewers to each. This is what the manual `RUN` confirmation in `e2e-cloud.yaml` actually gates.
- The credential-less gates (`fmt`, `validate`, `tflint`, `checkov`) need none of this setup — only the `plan-*` jobs and the e2e apply/destroy jobs authenticate to a cloud.

## Coverage Note

**These tests are the only automated coverage of real-GPU behaviour.** The root module (`cmd/`, `pkg/`) uses a mock GPU collector for unit tests. Real NVIDIA hardware validation happens only here.
