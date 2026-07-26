# NVIDIA GPU operator. The AL2023 NVIDIA AMI already ships the driver and
# container toolkit, so those are disabled here — the operator only adds the
# device plugin, node labelling, DCGM, and the `nvidia` RuntimeClass. Using a
# non-NVIDIA AMI instead? Set driver.enabled=true so it installs the driver.
resource "helm_release" "gpu_operator" {
  name             = "gpu-operator"
  namespace        = "gpu-operator"
  create_namespace = true

  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.gpu_operator_chart_version

  set = [
    {
      name  = "driver.enabled"
      value = "false"
    },
    {
      name  = "toolkit.enabled"
      value = "false"
    },
  ]

  # Device-plugin/GFD rollout and node labelling can take a few minutes after
  # the node joins.
  wait    = true
  timeout = var.helm_timeout

  depends_on = [module.eks]
}
