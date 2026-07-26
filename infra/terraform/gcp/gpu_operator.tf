# NVIDIA GPU operator: owns the driver + toolkit since GKE installs none
# (gpu_driver_installation_config = INSTALLATION_DISABLED in main.tf), and provides
# the device plugin, NFD/GFD labels, and nvidia RuntimeClass. DCGM is off — the
# scaler reads NVML directly.

# GKE gates system-node-critical/system-cluster-critical pods behind a ResourceQuota;
# without one here the operator + NFD pods get rejected at admission. Create the
# namespace + quota before the operator installs.
resource "kubernetes_namespace_v1" "gpu_operator" {
  metadata {
    name = "gpu-operator"
  }

  depends_on = [
    google_container_node_pool.gpu,
  ]
}

resource "kubernetes_resource_quota_v1" "gpu_operator_critical" {
  metadata {
    name      = "gpu-operator-critical-pods"
    namespace = kubernetes_namespace_v1.gpu_operator.metadata[0].name
  }

  spec {
    hard = {
      pods = "100"
    }

    scope_selector {
      match_expression {
        scope_name = "PriorityClass"
        operator   = "In"
        values     = ["system-node-critical", "system-cluster-critical"]
      }
    }
  }
}

resource "helm_release" "gpu_operator" {
  name             = "gpu-operator"
  namespace        = kubernetes_namespace_v1.gpu_operator.metadata[0].name
  create_namespace = false

  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.gpu_operator_chart_version

  set = [
    # Operator owns the driver + toolkit (GKE installs nothing — INSTALLATION_DISABLED).
    { name = "driver.enabled", value = "true" },
    { name = "toolkit.enabled", value = "true" },

    # CNI fix (NVIDIA/nvidia-container-toolkit#1222): "file" mode edits config.toml
    # in place so the toolkit doesn't reset GKE's CNI bin_dir (/home/kubernetes/bin)
    # to the empty /opt/cni/bin and break pod networking. Must be set on first install.
    { name = "toolkit.env[0].name", value = "CONTAINERD_CONFIG" },
    { name = "toolkit.env[0].value", value = "/etc/containerd/config.toml" },
    { name = "toolkit.env[1].name", value = "CONTAINERD_SOCKET" },
    { name = "toolkit.env[1].value", value = "/run/containerd/containerd.sock" },
    { name = "toolkit.env[2].name", value = "RUNTIME_CONFIG_SOURCE" },
    { name = "toolkit.env[2].value", value = "file" },

    # NVIDIA's recommended injection mode on GKE (does not itself fix the CNI bug).
    { name = "cdi.enabled", value = "true" },
    { name = "cdi.default", value = "true" },

    # Scaler reads NVML directly, not DCGM — skip it to cut image pulls.
    { name = "dcgm.enabled", value = "false" },
    { name = "dcgmExporter.enabled", value = "false" },
  ]

  # wait=true: the driver build converges in ~20 min on this single untainted pool
  # (well under helm_timeout), so apply only returns once the GPU stack is ready.
  # Bump helm_timeout if a driver build needs more time.
  wait = true

  # Bounds the graceful `helm uninstall` on destroy. The operator's teardown is slow
  # and the default 5 min often strands the (billing) GPU node; if it still hangs,
  # see the README destroy note.
  timeout = var.helm_timeout

  depends_on = [
    kubernetes_resource_quota_v1.gpu_operator_critical,
    google_container_node_pool.gpu,
    helm_release.keda,
  ]
}
