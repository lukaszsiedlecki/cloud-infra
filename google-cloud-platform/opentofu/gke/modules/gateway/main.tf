resource "google_compute_global_address" "gateway_ip" {
  name    = "${var.name_prefix}-gateway-ip"
  project = var.project_id
}

resource "google_certificate_manager_dns_authorization" "main" {
  name    = "${var.name_prefix}-dns-auth"
  project = var.project_id
  domain  = var.domain
}

resource "google_certificate_manager_certificate" "main" {
  name    = "${var.name_prefix}-cert"
  project = var.project_id

  managed {
    domains            = [var.domain]
    dns_authorizations = [google_certificate_manager_dns_authorization.main.id]
  }
}

resource "google_certificate_manager_certificate_map" "main" {
  name    = "${var.name_prefix}-cert-map"
  project = var.project_id
}

resource "google_certificate_manager_certificate_map_entry" "main" {
  name         = "${var.name_prefix}-cert-map-entry"
  project      = var.project_id
  map          = google_certificate_manager_certificate_map.main.name
  certificates = [google_certificate_manager_certificate.main.id]
  hostname     = var.domain
}
