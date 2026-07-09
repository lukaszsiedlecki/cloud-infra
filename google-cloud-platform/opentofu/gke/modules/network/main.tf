resource "google_compute_network" "main" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.name_prefix}-subnet"
  network       = google_compute_network.main.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr

  private_ip_google_access = true

  # GKE Standard mode (VPC-native) needs explicit secondary ranges for pod
  # and service IPs — Autopilot managed these invisibly. Sized modestly
  # since this cluster will never exceed ~2 nodes, not the typical
  # oversized /14 you'd give a cluster expected to actually scale.
  secondary_ip_range {
    range_name    = "${var.name_prefix}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.name_prefix}-services"
    ip_cidr_range = var.services_cidr
  }
}

# Private Service Access: reserves a peering range and connects it so Cloud
# SQL can get a private IP inside this VPC.
resource "google_compute_global_address" "private_service_access" {
  name          = "${var.name_prefix}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]
}
