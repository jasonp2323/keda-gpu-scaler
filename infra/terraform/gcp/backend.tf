terraform {
  # Partial config: bucket/prefix are supplied at `terraform init
  # -backend-config=...` (see infra/terraform/gcp/bootstrap/README.md), so no
  # bucket name is hardcoded here. The bucket itself is created once by
  # infra/terraform/gcp/bootstrap/.
  backend "gcs" {}
}
