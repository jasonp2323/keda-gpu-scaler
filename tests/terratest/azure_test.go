//go:build e2e_azure

package terratest

import (
	"os"
	"path/filepath"
	"testing"
)

// TestAzureGPUScalerE2E applies infra/terraform/azure (AKS + GPU node + gpu-operator + KEDA + keda-gpu-scaler + e2e
// fixtures), asserts idle/scale-up/scale-down, then destroys. Real Azure cost — see README.md before running.
// Requires ARM_SUBSCRIPTION_ID (and standard ARM_* auth env vars) — Terraform reads them directly.
func TestAzureGPUScalerE2E(t *testing.T) {
	if os.Getenv("ARM_SUBSCRIPTION_ID") == "" {
		t.Fatal("ARM_SUBSCRIPTION_ID must be set for the Azure e2e suite")
	}

	terraformDir, err := filepath.Abs("../../infra/terraform/azure")
	if err != nil {
		t.Fatalf("resolve terraform dir: %v", err)
	}

	// E2E_CLUSTER_NAME is the full name (CI makes it unique per run); local runs get a suffixed default.
	clusterName := envOrDefault("E2E_CLUSTER_NAME", "keda-gpu-scaler-e2e-"+clusterSuffix())

	// Remote azurerm backend (created by infra/terraform/azure/bootstrap); state key is unique per cluster.
	// Note: the STATE resource group (E2E_AZURE_STATE_*) is distinct from the cluster's own resource group.
	stateSA := envOrDefault("E2E_AZURE_STATE_STORAGE_ACCOUNT", "")
	stateRG := envOrDefault("E2E_AZURE_STATE_RESOURCE_GROUP", "")
	if stateSA == "" || stateRG == "" {
		t.Fatal("E2E_AZURE_STATE_STORAGE_ACCOUNT and E2E_AZURE_STATE_RESOURCE_GROUP must be set — run infra/terraform/azure/bootstrap")
	}
	backendConfig := map[string]interface{}{
		"resource_group_name":  stateRG,
		"storage_account_name": stateSA,
		"container_name":       envOrDefault("E2E_AZURE_STATE_CONTAINER", "tfstate"),
		"key":                  "e2e/azure/" + clusterName + ".tfstate",
	}

	vars := map[string]interface{}{
		"location":                envOrDefault("E2E_AZURE_LOCATION", "eastus"),
		"cluster_name":            clusterName,
		"resource_group_name":     envOrDefault("E2E_AZURE_RESOURCE_GROUP", clusterName+"-rg"),
		"kubernetes_version":      envOrDefault("E2E_K8S_VERSION", "1.33"),
		"gpu_vm_size":             envOrDefault("E2E_GPU_VM_SIZE", "Standard_NC4as_T4_v3"),
		"gpu_node_count":          1,
		"helm_timeout":            envOrDefaultInt("E2E_HELM_TIMEOUT", 900),
		"scaler_image_repository": envOrDefault("E2E_SCALER_IMAGE_REPOSITORY", "ghcr.io/pmady/keda-gpu-scaler"),
		"scaler_image_tag":        envOrDefault("E2E_SCALER_IMAGE_TAG", "v0.5.0"),
		"tags": map[string]interface{}{
			"Project": "keda-gpu-scaler",
		},
	}

	runGPUScalerE2E(gpuScalerE2E{
		t:                 t,
		terraformDir:      terraformDir,
		vars:              vars,
		envVars:           map[string]string{},
		backendConfig:     backendConfig,
		scalerReleaseName: "keda-gpu-scaler",
	})
}
