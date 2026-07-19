# GitHub Actions OIDC -> GCP Workload Identity Federation, so CI never stores
# a long-lived service account key. Mirrors tests/terratest/README.md ("### GCP").

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "keda-gpu-scaler e2e"
  description               = "GitHub Actions OIDC federation for keda-gpu-scaler e2e/terratest runs."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub Actions"
  description                        = "Restricted to ${var.github_repository} via the attribute condition below."

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Scopes the provider to this repo only — without this, any GitHub repo's
  # OIDC token could satisfy the pool.
  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account CI impersonates to run `terraform apply`/`destroy` against
# the main GKE stack.
resource "google_service_account" "e2e" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "keda-gpu-scaler e2e"
  description  = "Impersonated by GitHub Actions (via WIF) to provision/destroy the e2e GKE test cluster."
}

# Scoped to exactly what the main stack provisions (see tests/terratest/README.md
# "### GCP" for the rationale) — no project-wide compute.admin or owner role.
resource "google_project_iam_member" "e2e_container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.e2e.email}"
}

resource "google_project_iam_member" "e2e_network_admin" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_service_account.e2e.email}"
}

resource "google_project_iam_member" "e2e_service_account_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.e2e.email}"
}

# Bucket-scoped (not project-wide) so the SA can read/write the remote
# Terraform state object without a broader storage grant.
resource "google_storage_bucket_iam_member" "e2e_state_bucket" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.e2e.email}"
}

# Lets GitHub Actions workflows running in var.github_repository impersonate
# the service account above via the WIF provider (no service account key).
resource "google_service_account_iam_member" "e2e_wif_binding" {
  service_account_id = google_service_account.e2e.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}
