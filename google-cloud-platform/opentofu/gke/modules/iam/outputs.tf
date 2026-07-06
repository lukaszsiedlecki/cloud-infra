output "deployer_email" {
  value = google_service_account.github_deployer.email
}

output "deployer_key_json_base64" {
  description = "base64-encoded SA key JSON — copy this into the GitHub repo secret GCP_SA_KEY (tofu output -raw). Never commit this value."
  value       = google_service_account_key.github_deployer.private_key
  sensitive   = true
}
