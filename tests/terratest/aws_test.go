//go:build e2e_aws

package terratest

import (
	"path/filepath"
	"testing"
)

// TestAWSGPUScalerE2E applies infra/terraform/aws (EKS + GPU node + gpu-operator + KEDA + keda-gpu-scaler + e2e
// fixtures), asserts idle/scale-up/scale-down, then destroys. Real AWS cost — see README.md before running.
func TestAWSGPUScalerE2E(t *testing.T) {
	terraformDir, err := filepath.Abs("../../infra/terraform/aws")
	if err != nil {
		t.Fatalf("resolve terraform dir: %v", err)
	}

	// E2E_CLUSTER_NAME is the full name (CI makes it unique per run); local runs get a suffixed default.
	clusterName := envOrDefault("E2E_CLUSTER_NAME", "keda-gpu-scaler-e2e-"+clusterSuffix())

	vars := map[string]interface{}{
		"region":                  envOrDefault("AWS_REGION", "us-east-2"),
		"cluster_name":            clusterName,
		"kubernetes_version":      envOrDefault("E2E_K8S_VERSION", "1.33"),
		"gpu_instance_type":       envOrDefault("E2E_GPU_INSTANCE_TYPE", "g5.xlarge"),
		"gpu_node_count":          1,
		"helm_timeout":            envOrDefaultInt("E2E_HELM_TIMEOUT", 600),
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
		scalerReleaseName: "keda-gpu-scaler",
	})
}
