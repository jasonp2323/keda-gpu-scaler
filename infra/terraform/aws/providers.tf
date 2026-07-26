provider "aws" {
  region = var.region

  # Tag every resource so a forgotten cluster is easy to find (and bulk-delete).
  default_tags {
    tags = local.tags
  }
}

# Kubernetes/Helm providers authenticate via the AWS CLI's `eks get-token` exec
# plugin — tokens are short-lived and refreshed per operation, so nothing is
# written to ~/.kube/config. Requires awscli v2 on PATH and valid AWS
# credentials for the cluster's account/region.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

# Helm provider v3 takes Kubernetes connection settings as an attribute object
# (`kubernetes = { ... }`, `exec = { ... }`), unlike the Kubernetes provider's
# `exec {}` block above. See the v2 -> v3 upgrade guide.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
