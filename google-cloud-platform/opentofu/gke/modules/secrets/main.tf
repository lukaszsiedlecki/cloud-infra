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
  # TUNNEL_TOKEN is handled by its own resource below — the
  # cloudflare_zero_trust_tunnel_cloudflared_token data source it reads from
  # isn't idempotent (Cloudflare returns a differently-encoded but
  # functionally equivalent token on different calls), which would otherwise
  # make this secret_version want replacement on essentially every plan.
  for_each    = { for k, v in local.secrets : k => v if k != "TUNNEL_TOKEN" }
  secret      = google_secret_manager_secret.main[each.key].id
  secret_data = each.value.value
}

resource "google_secret_manager_secret_version" "tunnel_token" {
  secret      = google_secret_manager_secret.main["TUNNEL_TOKEN"].id
  secret_data = local.secrets["TUNNEL_TOKEN"].value

  lifecycle {
    ignore_changes = [secret_data]
  }
}

moved {
  from = google_secret_manager_secret_version.main["TUNNEL_TOKEN"]
  to   = google_secret_manager_secret_version.tunnel_token
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
