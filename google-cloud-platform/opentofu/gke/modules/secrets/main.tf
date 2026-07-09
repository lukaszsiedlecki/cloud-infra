locals {
  # Maps each secret's k8s-facing key name to its value and which app's KSA
  # needs to read it. Kept as a single map so the secret + version + IAM
  # binding triple is generated consistently for every credential, DB or not.
  secrets = {
    SHORTLINER_DB_USER     = { value = var.shortliner_db_user, ksa = "shortliner" }
    SHORTLINER_DB_PASSWORD = { value = var.shortliner_db_password, ksa = "shortliner" }
    SHORTLINER_DB_HOST     = { value = var.db_host, ksa = "shortliner" }
    ANALYTICS_DB_USER      = { value = var.shortliner_analytics_db_user, ksa = "shortliner-analytics" }
    ANALYTICS_DB_PASSWORD  = { value = var.shortliner_analytics_db_password, ksa = "shortliner-analytics" }
    ANALYTICS_DB_HOST      = { value = var.db_host, ksa = "shortliner-analytics" }
    TUNNEL_TOKEN           = { value = var.tunnel_token, ksa = "cloudflared" }
  }
}

resource "google_secret_manager_secret" "main" {
  for_each  = local.secrets
  project   = var.project_id
  secret_id = lower(replace(each.key, "_", "-"))

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "main" {
  for_each    = local.secrets
  secret      = google_secret_manager_secret.main[each.key].id
  secret_data = each.value.value
}

# Direct Workload Identity Federation principal binding — no separate Google
# service account needed for this, per GKE's SecretSync auth model.
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each  = local.secrets
  project   = var.project_id
  secret_id = google_secret_manager_secret.main[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${var.workload_identity_pool}/subject/ns/${var.namespace}/sa/${each.value.ksa}"
}
