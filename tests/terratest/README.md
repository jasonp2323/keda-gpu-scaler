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
| `E2E_K8S_VERSION` | All | — | Kubernetes version for the cluster. |
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
- **Auth:** Uses OIDC/federated cloud auth — no long-lived keys stored.
- **Scope:** Intentionally NOT run on every PR/push, matching the repo's "infra CI is manual only" stance.
- **Approval:** Each cloud has a per-cloud GitHub Environment requiring approval before running.

## Coverage Note

**These tests are the only automated coverage of real-GPU behaviour.** The root module (`cmd/`, `pkg/`) uses a mock GPU collector for unit tests. Real NVIDIA hardware validation happens only here.
