resource "google_compute_network" "main" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.name_prefix}-subnet"
  network       = google_compute_network.main.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr

  # Autopilot manages its own pod/service ranges via secondary ranges it
  # creates itself when private_ip_google_access isn't otherwise required
  # for this small a setup; kept simple on purpose.
  private_ip_google_access = true
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
