// Package terratest holds Tier-3 apply-level e2e tests: real cloud, real GPU, real terraform apply.
package terratest

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// Fixed by the e2e helm charts (deploy/helm/keda-gpu-scaler + keda-gpu-scaler-e2e) — not configurable per-run.
const (
	demoAppName      = "demo-app"
	demoAppNamespace = "default"
	scaledObjectName = "demo-app-gpu-scaler" // set in deploy/helm/keda-gpu-scaler-e2e/templates/scaledobject.yaml
	demoIdleReplicas = 1

	pollInterval    = 10 * time.Second
	scalerReadyWait = 3 * time.Minute
	idleAssertWait  = 2 * time.Minute
	scaleUpWait     = 6 * time.Minute
	scaleDownWait   = 10 * time.Minute
	kubectlCmdWait  = 60 * time.Second
)

// gpuScalerE2E bundles one cloud's inputs for a single apply -> assert -> load -> assert -> destroy run.
type gpuScalerE2E struct {
	t                 *testing.T
	terraformDir      string // absolute path to infra/terraform/<cloud>
	vars              map[string]interface{}
	envVars           map[string]string
	backendConfig     map[string]interface{} // partial-backend config (bucket/key/etc.); state key is unique per run
	scalerReleaseName string                 // helm release name for the keda-gpu-scaler chart (DaemonSet name == release name)
}

// runGPUScalerE2E drives the full shared flow. Cloud-specific test files just build cfg and call this.
func runGPUScalerE2E(cfg gpuScalerE2E) {
	t := cfg.t
	t.Helper()

	opts := &terraform.Options{
		TerraformDir:  cfg.terraformDir,
		Vars:          cfg.vars,
		EnvVars:       cfg.envVars,
		BackendConfig: cfg.backendConfig, // supplies the partial s3/azurerm/gcs backend at init
		NoColor:       true,
	}

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	scalerNamespace := terraform.Output(t, opts, "scaler_namespace")

	kubeconfig := writeKubeconfig(t, terraform.Output(t, opts, "configure_kubectl"))
	defer os.Remove(kubeconfig)

	scalerOpts := k8s.NewKubectlOptions("", kubeconfig, scalerNamespace)
	demoOpts := k8s.NewKubectlOptions("", kubeconfig, demoAppNamespace)

	// Registered after terraform.Destroy so it runs BEFORE teardown (LIFO) — the cluster still exists.
	defer collectDiagnostics(cfg, scalerOpts, demoOpts)

	assertScalerReady(t, scalerOpts, cfg.scalerReleaseName)
	assertScaledObjectReady(t, demoOpts)
	assertReplicas(t, demoOpts, demoIdleReplicas, idleAssertWait) // idle baseline before load

	loadFile := cfg.terraformDir + "/demo/gpu-load.yaml"
	k8s.KubectlApply(t, demoOpts, loadFile)
	assertReplicasAbove(t, demoOpts, demoIdleReplicas, scaleUpWait)

	k8s.KubectlDelete(t, demoOpts, loadFile)
	assertReplicas(t, demoOpts, demoIdleReplicas, scaleDownWait)
}

// collectDiagnostics dumps cluster state on failure (log + E2E_ARTIFACTS_DIR); deferred before Destroy so the cluster still exists. Best-effort, never fails the test.
func collectDiagnostics(cfg gpuScalerE2E, scalerOpts, demoOpts *k8s.KubectlOptions) {
	t := cfg.t
	if !t.Failed() {
		return
	}
	clusterName, _ := cfg.vars["cluster_name"].(string)
	release := cfg.scalerReleaseName

	var buf bytes.Buffer
	dump := func(title string, opts *k8s.KubectlOptions, args ...string) {
		fmt.Fprintf(&buf, "\n===== %s =====\n", title)
		out, err := k8s.RunKubectlAndGetOutputE(t, opts, args...)
		if err != nil {
			fmt.Fprintf(&buf, "(kubectl error: %v)\n", err)
		}
		buf.WriteString(out)
		buf.WriteString("\n")
	}

	dump("nodes", scalerOpts, "get", "nodes", "-o", "wide")
	dump("scaler pods", scalerOpts, "get", "pods", "-o", "wide")
	dump("scaler daemonset", scalerOpts, "describe", "daemonset", release)
	dump("scaler logs", scalerOpts, "logs", "daemonset/"+release, "--all-containers=true", "--tail=500")
	dump("demo-app deployment", demoOpts, "describe", "deployment", demoAppName)
	dump("scaledobject", demoOpts, "get", "scaledobject", scaledObjectName, "-o", "yaml")
	dump("scaledobject describe", demoOpts, "describe", "scaledobject", scaledObjectName)
	dump("recent events", demoOpts, "get", "events", "-A", "--sort-by=.lastTimestamp")

	t.Logf("---- e2e failure diagnostics (cluster %q) ----\n%s", clusterName, buf.String())

	dir := os.Getenv("E2E_ARTIFACTS_DIR")
	if dir == "" {
		return
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Logf("diagnostics: could not create %s: %v", dir, err)
		return
	}
	name := "diagnostics"
	if clusterName != "" {
		name += "-" + clusterName
	}
	if err := os.WriteFile(filepath.Join(dir, name+".txt"), buf.Bytes(), 0o644); err != nil {
		t.Logf("diagnostics: could not write file: %v", err)
	}
}

// writeKubeconfig runs configure_kubectl against a fresh temp kubeconfig and returns its path (all three clouds' CLIs honor KUBECONFIG).
func writeKubeconfig(t *testing.T, configureCmd string) string {
	t.Helper()

	f, err := os.CreateTemp("", "keda-gpu-scaler-e2e-kubeconfig-*")
	require.NoError(t, err)
	kubeconfigPath := f.Name()
	require.NoError(t, f.Close())

	ctx, cancel := context.WithTimeout(context.Background(), kubectlCmdWait)
	defer cancel()

	cmd := exec.CommandContext(ctx, "bash", "-c", configureCmd)
	cmd.Env = append(os.Environ(), "KUBECONFIG="+kubeconfigPath)
	out, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "configure_kubectl command failed: %s", string(out))

	return kubeconfigPath
}

// assertScalerReady waits for the keda-gpu-scaler DaemonSet (release name == DaemonSet name) to be fully rolled out.
func assertScalerReady(t *testing.T, opts *k8s.KubectlOptions, releaseName string) {
	t.Helper()
	retries := int(scalerReadyWait / pollInterval)
	retry.DoWithRetry(t, fmt.Sprintf("wait for DaemonSet %s available", releaseName), retries, pollInterval, func() (string, error) {
		ds, err := k8s.GetDaemonSetE(t, opts, releaseName)
		if err != nil {
			return "", err
		}
		desired := ds.Status.DesiredNumberScheduled
		if desired == 0 || ds.Status.NumberAvailable != desired {
			return "", fmt.Errorf("daemonset %s: %d/%d available", releaseName, ds.Status.NumberAvailable, desired)
		}
		return "daemonset available", nil
	})
}

// assertScaledObjectReady polls the demo-app ScaledObject until KEDA reports its Ready condition True.
func assertScaledObjectReady(t *testing.T, opts *k8s.KubectlOptions) {
	t.Helper()
	retries := int(scalerReadyWait / pollInterval)
	retry.DoWithRetry(t, "wait for ScaledObject Ready", retries, pollInterval, func() (string, error) {
		out, err := k8s.RunKubectlAndGetOutputE(t, opts, "get", "scaledobject", scaledObjectName,
			"-o", `jsonpath={.status.conditions[?(@.type=="Ready")].status}`)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(out) != "True" {
			return "", fmt.Errorf("scaledobject %s Ready status = %q, want True", scaledObjectName, out)
		}
		return "ScaledObject is Ready", nil
	})
}

// getDemoAppReplicas reads demo-app's current status.replicas via kubectl jsonpath.
func getDemoAppReplicas(t *testing.T, opts *k8s.KubectlOptions) (int, error) {
	t.Helper()
	out, err := k8s.RunKubectlAndGetOutputE(t, opts, "get", "deployment", demoAppName, "-o", "jsonpath={.status.replicas}")
	if err != nil {
		return 0, err
	}
	out = strings.TrimSpace(out)
	if out == "" {
		return 0, nil // status.replicas is unset momentarily right after creation
	}
	return strconv.Atoi(out)
}

// gpuMetricSnapshot returns a short "current/target" string for the GPU-utilization
// metric KEDA is scaling on, read from the managed HPA. Best-effort: returns "" if
// the HPA or metric value isn't readable yet (never fails the test).
func gpuMetricSnapshot(t *testing.T, opts *k8s.KubectlOptions) string {
	t.Helper()
	hpa := "keda-hpa-" + scaledObjectName
	// KEDA external metrics report under either averageValue (AverageValue type,
	// the default) or value (Value type); try both.
	cur := kubectlFirstNonEmpty(t, opts, hpa,
		`jsonpath={.status.currentMetrics[0].external.current.averageValue}`,
		`jsonpath={.status.currentMetrics[0].external.current.value}`)
	if cur == "" {
		return ""
	}
	target := kubectlFirstNonEmpty(t, opts, hpa,
		`jsonpath={.spec.metrics[0].external.target.averageValue}`,
		`jsonpath={.spec.metrics[0].external.target.value}`)
	if target == "" {
		return "gpu=" + cur
	}
	return "gpu=" + cur + "/" + target
}

// kubectlFirstNonEmpty runs `kubectl get hpa <hpa> -o <expr>` for each expr and
// returns the first trimmed non-empty result, or "" if all fail/empty. Best-effort.
func kubectlFirstNonEmpty(t *testing.T, opts *k8s.KubectlOptions, hpa string, exprs ...string) string {
	t.Helper()
	for _, expr := range exprs {
		out, err := k8s.RunKubectlAndGetOutputE(t, opts, "get", "hpa", hpa, "-o", expr)
		if err == nil {
			if v := strings.TrimSpace(out); v != "" {
				return v
			}
		}
	}
	return ""
}

// assertReplicas polls until demo-app's replica count equals want, or fails the test after timeout.
func assertReplicas(t *testing.T, opts *k8s.KubectlOptions, want int, timeout time.Duration) {
	t.Helper()
	retries := int(timeout / pollInterval)
	retry.DoWithRetry(t,
		fmt.Sprintf("wait for %s replicas == %d", demoAppName, want), retries, pollInterval, func() (string, error) {
			got, err := getDemoAppReplicas(t, opts)
			if err != nil {
				return "", err
			}
			gpu := gpuMetricSnapshot(t, opts)
			if got != want {
				return "", fmt.Errorf("%s replicas = %d (%s), want %d", demoAppName, got, gpu, want)
			}
			return fmt.Sprintf("replica count matches: %s replicas = %d (%s)", demoAppName, got, gpu), nil
		})
}

// assertReplicasAbove polls until demo-app's replica count rises above floor (proves scale-up happened).
func assertReplicasAbove(t *testing.T, opts *k8s.KubectlOptions, floor int, timeout time.Duration) {
	t.Helper()
	retries := int(timeout / pollInterval)
	retry.DoWithRetry(t,
		fmt.Sprintf("wait for %s replicas > %d", demoAppName, floor), retries, pollInterval, func() (string, error) {
			got, err := getDemoAppReplicas(t, opts)
			if err != nil {
				return "", err
			}
			gpu := gpuMetricSnapshot(t, opts)
			if got <= floor {
				return "", fmt.Errorf("%s replicas = %d (%s), want > %d", demoAppName, got, gpu, floor)
			}
			return fmt.Sprintf("scaled up: %s replicas = %d (%s)", demoAppName, got, gpu), nil
		})
}

// envOrDefault reads an env var, falling back to def if unset or empty.
func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// envOrDefaultInt reads an int env var, falling back to def if unset, empty, or unparsable.
func envOrDefaultInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

// clusterSuffix derives a short, collision-avoiding suffix for cluster_name from CI env, else a fixed default.
func clusterSuffix() string {
	if id := os.Getenv("GITHUB_RUN_ID"); id != "" {
		return id
	}
	return "local"
}
