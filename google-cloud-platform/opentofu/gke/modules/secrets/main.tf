locals {
  # Maps each secret's k8s-facing key name to its value and which app's KSA
  # needs to read it. Kept as a single map so the secret + version + IAM
  # binding triple is generated consistently for all four credentials.
  db_secrets = {
    SHORTLINER_DB_USER     = { value = var.shortliner_db_user, ksa = "shortliner" }
    SHORTLINER_DB_PASSWORD = { value = var.shortliner_db_password, ksa = "shortliner" }
    ANALYTICS_DB_USER      = { value = var.shortliner_analytics_db_user, ksa = "shortliner-analytics" }
    ANALYTICS_DB_PASSWORD  = { value = var.shortliner_analytics_db_password, ksa = "shortliner-analytics" }
  }
}

resource "google_secret_manager_secret" "db" {
  for_each  = local.db_secrets
  project   = var.project_id
  secret_id = lower(replace(each.key, "_", "-"))

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db" {
  for_each    = local.db_secrets
  secret      = google_secret_manager_secret.db[each.key].id
  secret_data = each.value.value
}

# Direct Workload Identity Federation principal binding — no separate Google
# service account needed for this, per GKE's SecretSync auth model.
resource "google_secret_manager_secret_iam_member" "db_accessor" {
  for_each  = local.db_secrets
  project   = var.project_id
  secret_id = google_secret_manager_secret.db[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${var.workload_identity_pool}/subject/ns/${var.namespace}/sa/${each.value.ksa}"
}
