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
  description = "Workload Identity pool string, used to build direct KSA-principal IAM bindings in modules/secrets"
  # Reads the actual resource attribute rather than hand-building the string
  # from project_id — on Autopilot this was automatic and unconfigurable, so
  # the hardcoded string was harmless; now that Standard requires an
  # explicit workload_identity_config block, this ties the output to what
  # the cluster actually has configured.
  value = google_container_cluster.main.workload_identity_config[0].workload_pool
}
