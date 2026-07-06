resource "google_service_account" "github_deployer" {
  account_id   = "${var.name_prefix}-gh-deployer"
  display_name = "GitHub Actions deployer for ${var.name_prefix}"
  project      = var.project_id
}

# NOTE: if shortliner-prod sits under a GCP Organization, an org policy
# (iam.disableServiceAccountKeyCreation) may block this by default — check
# for an org first; if present, this needs an explicit policy exception.
resource "google_service_account_key" "github_deployer" {
  service_account_id = google_service_account.github_deployer.name
}

# Scoped to exactly what the promotion job needs: get cluster credentials
# and apply manifests. Not project editor/owner.
resource "google_project_iam_member" "github_deployer_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}
