output "state_bucket_name" {
  description = "Name of the GCS bucket to use as the backend for opentofu/gke"
  value       = google_storage_bucket.tofu_state.name
}
