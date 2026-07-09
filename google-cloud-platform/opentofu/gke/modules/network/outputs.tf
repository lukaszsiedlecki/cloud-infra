output "network_id" {
  value = google_compute_network.main.id
}

output "network_self_link" {
  value = google_compute_network.main.self_link
}

output "subnet_id" {
  value = google_compute_subnetwork.main.id
}

output "subnet_self_link" {
  value = google_compute_subnetwork.main.self_link
}

output "private_service_access_connection" {
  description = "Used as an explicit dependency for resources needing the peering to exist first (e.g. Cloud SQL)"
  value       = google_service_networking_connection.private_service_access
}

output "pods_range_name" {
  value = "${var.name_prefix}-pods"
}

output "services_range_name" {
  value = "${var.name_prefix}-services"
}
