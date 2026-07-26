# NVIDIA GPU operator. driver.enabled = false since AKS already installs the
# host driver (gpu_driver = "Install" in main.tf), mirroring the EKS AMI's
# driver. toolkit.enabled stays true because, unlike the EKS AMI, AKS doesn't
# register a named `nvidia` containerd runtime — the toolkit supplies that
# runtime and the `nvidia` RuntimeClass, plus the device plugin and NFD/GFD's
# `nvidia.com/gpu.present` node label.
#
# https://learn.microsoft.com/azure/aks/nvidia-gpu-operator

# Some managed clusters gate system-node-critical/system-cluster-critical pods
# behind a ResourceQuota; create the namespace + quota before the operator so its
# controllers and NFD are admitted (mirrors the GCP stack).
resource "kubernetes_namespace_v1" "gpu_operator" {
  metadata {
    name = "gpu-operator"
  }

  depends_on = [azurerm_kubernetes_cluster.this]
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

  # Host driver already installed; toolkit.enabled adds the `nvidia` containerd
  # runtime + RuntimeClass that AKS doesn't register itself.
  set = [
    {
      name  = "driver.enabled"
      value = "false"
    },
    {
      name  = "toolkit.enabled"
      value = "true"
    },
  ]

  # No driver build now — just the toolkit + device-plugin/GFD rollout and node
  # labelling, a couple of minutes after the node joins.
  wait    = true
  timeout = var.helm_timeout

  depends_on = [
    azurerm_kubernetes_cluster.this,
    kubernetes_resource_quota_v1.gpu_operator_critical,
  ]
}
