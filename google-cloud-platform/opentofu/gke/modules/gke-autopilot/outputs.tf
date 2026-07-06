output "cluster_name" {
  value = google_container_cluster.main.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.main.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool string, used to build direct KSA-principal IAM bindings"
  value       = "${var.project_id}.svc.id.goog"
}
