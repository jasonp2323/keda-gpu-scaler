//go:build e2e_gcp

package terratest

import (
	"os"
	"path/filepath"
	"testing"
)

// TestGCPGPUScalerE2E applies infra/terraform/gcp (GKE + GPU + KEDA + keda-gpu-scaler + e2e fixtures), asserts idle/scale-up/scale-down, then destroys. Real GCP cost — see README.md.
func TestGCPGPUScalerE2E(t *testing.T) {
	projectID := envOrDefault("E2E_GCP_PROJECT", os.Getenv("GOOGLE_PROJECT"))
	if projectID == "" {
		t.Fatal("set E2E_GCP_PROJECT or GOOGLE_PROJECT for the GCP e2e suite")
	}

	terraformDir, err := filepath.Abs("../../infra/terraform/gcp")
	if err != nil {
		t.Fatalf("resolve terraform dir: %v", err)
	}

	// E2E_CLUSTER_NAME is the full name (CI makes it unique per run); local runs get a suffixed default.
	clusterName := envOrDefault("E2E_CLUSTER_NAME", "keda-gpu-scaler-e2e-"+clusterSuffix())

	// Remote GCS backend (created by infra/terraform/gcp/bootstrap); state prefix is unique per cluster.
	stateBucket := envOrDefault("E2E_GCP_STATE_BUCKET", "")
	if stateBucket == "" {
		t.Fatal("E2E_GCP_STATE_BUCKET must be set — run infra/terraform/gcp/bootstrap and use its state_bucket output")
	}
	backendConfig := map[string]interface{}{
		"bucket": stateBucket,
		"prefix": "e2e/gcp/" + clusterName,
	}

	vars := map[string]interface{}{
		"project_id":              projectID,
		"region":                  envOrDefault("E2E_GCP_REGION", "us-central1"),
		"zone":                    envOrDefault("E2E_GCP_ZONE", "us-central1-a"),
		"cluster_name":            clusterName,
		"kubernetes_version":      envOrDefault("E2E_K8S_VERSION", "1.34"),
		"gpu_machine_type":        envOrDefault("E2E_GPU_MACHINE_TYPE", "n1-standard-4"),
		"gpu_type":                envOrDefault("E2E_GPU_TYPE", "nvidia-tesla-t4"),
		"gpu_per_node":            1,
		"gpu_node_count":          1,
		"helm_timeout":            envOrDefaultInt("E2E_HELM_TIMEOUT", 1800),
		"scaler_image_repository": envOrDefault("E2E_SCALER_IMAGE_REPOSITORY", "ghcr.io/pmady/keda-gpu-scaler"),
		"scaler_image_tag":        envOrDefault("E2E_SCALER_IMAGE_TAG", "v0.5.0"),
		"labels": map[string]interface{}{
			"project": "keda-gpu-scaler",
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
