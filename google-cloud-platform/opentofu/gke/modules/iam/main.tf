resource "google_service_account" "github_deployer" {
  account_id   = "${var.name_prefix}-gh-deployer"
  display_name = "GitHub Actions deployer for ${var.name_prefix}"
  project      = var.project_id
}

# Scoped to exactly what the promotion job needs: get cluster credentials
# and apply manifests. Not project editor/owner.
resource "google_project_iam_member" "github_deployer_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

# --- GitHub Actions OIDC federation (separate from the GKE cluster's own
# workload_identity_config pool in modules/gke — do not confuse the two). ---

resource "google_iam_workload_identity_pool" "github_actions" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.name_prefix}-github-actions"
  display_name              = "GitHub Actions"
  description               = "Federates GitHub Actions OIDC tokens for lukaszsiedlecki's repos (app self-deploy + infra CI). No long-lived keys."
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.environment"      = "assertion.environment"
  }

  # Required by Google. Defense-in-depth: even though every SA binding below
  # is further scoped to one exact repo via attribute.repository, this stops
  # tokens from any GitHub account/org other than lukaszsiedlecki's from ever
  # being considered for exchange against this pool at all.
  attribute_condition = "assertion.repository_owner == \"lukaszsiedlecki\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# --- App self-deploy: each of the 3 app repos gets rights to impersonate the
# existing github_deployer SA (container.developer only — unchanged scope). ---

resource "google_service_account_iam_member" "github_deployer_wif" {
  for_each = toset(["shortliner", "shortliner-analytics", "shortliner-frontend"])

  service_account_id = google_service_account.github_deployer.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/lukaszsiedlecki/${each.value}"
}

# --- Infra CI: new identity for tofu plan/apply/destroy, Owner-scoped to
# match what tofu-bootstrap already does locally. Security boundary is WIF
# (keyless, repo-scoped) + required-reviewer approval gates in infra.yml, not
# IAM minimization — deliberate choice for this personal/learning project. ---

resource "google_service_account" "infra_ci" {
  account_id   = "${var.name_prefix}-infra-ci"
  display_name = "GitHub Actions infra CI (tofu plan/apply/destroy) for ${var.name_prefix}"
  project      = var.project_id
}

resource "google_project_iam_member" "infra_ci_owner" {
  project = var.project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.infra_ci.email}"
}

resource "google_service_account_iam_member" "infra_ci_wif" {
  service_account_id = google_service_account.infra_ci.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/lukaszsiedlecki/cloud-infra"
}
