provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "keda-gpu-scaler"
      ManagedBy = "terraform"
    }
  }
}
