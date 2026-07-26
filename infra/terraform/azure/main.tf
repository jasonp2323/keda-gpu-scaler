locals {
  tags = merge(
    {
      Project   = "keda-gpu-scaler"
      Component = "gpu-integration-test"
      ManagedBy = "terraform"
      Stack     = "infra/terraform/azure"
    },
    var.tags,
  )
}

###############################################################################
# Resource group
###############################################################################

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

###############################################################################
# AKS control plane + single GPU node pool
#
# Hand-rolled on azurerm_kubernetes_cluster instead of the Azure/aks/azurerm
# module (v11.7.0): AKS manages its own VNet so there's no networking module to
# lean on, and the module only exposes gpu_driver on extra node_pools, not the
# default pool, forcing a 2-pool design. Making the default pool the GPU pool
# (gpu_driver = "Install") keeps a single untainted node running the whole
# stack, mirroring the EKS sibling's single GPU node group.
###############################################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name       = "gpu"
    vm_size    = var.gpu_vm_size
    node_count = var.gpu_node_count

    # Fixed-size pool: predictable for tests, no autoscaling, no spot.
    auto_scaling_enabled = false

    os_disk_size_gb = var.gpu_node_disk_size

    # AKS installs a prebuilt driver (no runtime kernel build), mirroring the
    # EKS AL2023 NVIDIA AMI. The GPU operator only adds k8s-facing pieces
    # (gpu_operator.tf).
    gpu_driver = "Install"

    # Lets vm_size / os_disk overrides roll a fresh pool instead of failing.
    temporary_name_for_rotation = "tmpgpu"

    node_labels = {
      "keda-gpu-scaler.io/pool" = "gpu"
    }

    tags = local.tags

    # NOTE: intentionally the untainted default/system pool, so KEDA, the GPU
    # operator and CoreDNS schedule alongside the scaler on the one GPU node.
    # Tainting it later is safe for the scaler but strands system pods unless
    # you add a separate CPU pool.
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}
