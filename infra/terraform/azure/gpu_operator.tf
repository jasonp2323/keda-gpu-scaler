# NVIDIA GPU operator.
#
# AKS installs the host driver (gpu_driver = "Install" in main.tf), so
# driver.enabled = false — the operator uses the pre-installed host driver,
# same as the EKS sibling uses the AMI's driver.
#
# toolkit.enabled stays true: unlike the EKS NVIDIA AMI, AKS does not register
# a named `nvidia` containerd runtime handler. The operator's toolkit provides
# that runtime handler and the `nvidia` RuntimeClass the scaler's
# `runtimeClassName: nvidia` targets. The operator also provides the device
# plugin (advertises nvidia.com/gpu), NFD/GFD (the `nvidia.com/gpu.present=true`
# node label), and the `nvidia` RuntimeClass.
#
# https://learn.microsoft.com/azure/aks/nvidia-gpu-operator
resource "helm_release" "gpu_operator" {
  name             = "gpu-operator"
  namespace        = "gpu-operator"
  create_namespace = true

  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.gpu_operator_chart_version

  # driver.enabled = false: AKS already installed the host driver. toolkit.enabled
  # stays true so the operator provides the named `nvidia` containerd runtime and
  # RuntimeClass, which AKS does not register itself.
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

  depends_on = [azurerm_kubernetes_cluster.this]
}
