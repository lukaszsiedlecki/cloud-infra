resource "google_sql_database_instance" "main" {
  name             = "${var.name_prefix}-pg"
  database_version = "POSTGRES_16"
  region           = var.region
  project          = var.project_id

  # Sleep/wake scripts flip activation_policy directly via gcloud; OpenTofu
  # must never fight that by resetting it back to ALWAYS on the next apply.
  lifecycle {
    ignore_changes = [settings[0].activation_policy]
  }

  settings {
    tier              = var.tier
    availability_type = "ZONAL"
    disk_autoresize   = true

    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }
  }

  deletion_protection = false

  depends_on = [var.private_service_access_connection]
}

resource "google_sql_database" "shortliner" {
  name     = "shortliner"
  instance = google_sql_database_instance.main.name
  project  = var.project_id
}

resource "google_sql_database" "shortliner_analytics" {
  name     = "shortliner_analytics"
  instance = google_sql_database_instance.main.name
  project  = var.project_id
}

resource "random_password" "shortliner_db" {
  length  = 32
  special = false
}

resource "random_password" "shortliner_analytics_db" {
  length  = 32
  special = false
}

resource "google_sql_user" "shortliner" {
  name     = "shortliner"
  instance = google_sql_database_instance.main.name
  password = random_password.shortliner_db.result
  project  = var.project_id
}

resource "google_sql_user" "shortliner_analytics" {
  name     = "shortliner_analytics"
  instance = google_sql_database_instance.main.name
  password = random_password.shortliner_analytics_db.result
  project  = var.project_id
}
