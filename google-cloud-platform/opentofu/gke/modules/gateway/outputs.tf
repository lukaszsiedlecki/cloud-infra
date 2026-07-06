output "static_ip_name" {
  description = "Reserved static IP resource name, referenced by the Gateway manifest's addresses field"
  value       = google_compute_global_address.gateway_ip.name
}

output "static_ip_address" {
  description = "The actual IP address — point your DNS A record at this"
  value       = google_compute_global_address.gateway_ip.address
}

output "dns_authorization_dns_resource_record" {
  description = "Add this CNAME record at your DNS provider before the managed certificate can be issued — {name} -> {data}"
  value       = google_certificate_manager_dns_authorization.main.dns_resource_record
}

output "certificate_map_name" {
  description = "Short name referenced by the Gateway manifest's networking.gke.io/certmap annotation"
  value       = google_certificate_manager_certificate_map.main.name
}
