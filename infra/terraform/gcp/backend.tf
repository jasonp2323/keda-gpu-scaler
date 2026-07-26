terraform {
  # Partial config — bucket/prefix supplied at `terraform init -backend-config=...`; bucket created once by infra/terraform/gcp/bootstrap.
  backend "gcs" {}
}
