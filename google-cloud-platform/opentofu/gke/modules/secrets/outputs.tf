output "secret_ids" {
  description = "Map of k8s-facing key name -> Secret Manager secret_id, for wiring into SecretProviderClass"
  value       = { for k, v in google_secret_manager_secret.main : k => v.secret_id }
}
