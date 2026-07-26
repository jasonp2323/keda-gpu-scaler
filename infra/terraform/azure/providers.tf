provider "azurerm" {
  # subscription_id is required by the azurerm v4 provider. Leave var.subscription_id
  # null to fall back to the ARM_SUBSCRIPTION_ID environment variable.
  subscription_id = var.subscription_id

  features {}
}

# Kubernetes and Helm authenticate to the new AKS cluster using the admin
# kubeconfig azurerm exports from the cluster resource, read straight from
# state — nothing needs writing to ~/.kube/config. Relies on the cluster's
# local admin account (local_account_disabled = false, the default); the `az`
# CLI is only needed afterwards to fetch a kubeconfig (see configure_kubectl).
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}

# Helm provider v3 takes its Kubernetes connection settings as an attribute
# object (`kubernetes = { ... }`) rather than a nested block — see the v2 -> v3
# upgrade guide.
provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}
