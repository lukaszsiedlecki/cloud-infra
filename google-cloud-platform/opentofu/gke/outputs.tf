output "cluster_name" {
  value = module.gke_autopilot.cluster_name
}

output "cloudsql_instance_name" {
  value = module.cloudsql.instance_name
}

output "cloudsql_private_ip_address" {
  description = "Set as DB_HOST in the k8s Deployment manifests"
  value       = module.cloudsql.private_ip_address
}

output "dns_app_record_fqdn" {
  description = "The proxied Cloudflare CNAME routing traffic into the tunnel — created automatically, no manual DNS step needed"
  value       = module.dns.app_record_fqdn
}

output "tunnel_id" {
  value = module.tunnel.tunnel_id
}

output "github_deployer_email" {
  value = module.iam.deployer_email
}

output "github_deployer_key_json_base64" {
  description = "Run: tofu output -raw github_deployer_key_json_base64 | base64 -d > key.json — then paste key.json's contents into the GCP_SA_KEY GitHub secret, and delete the local file. Never commit it."
  value       = module.iam.deployer_key_json_base64
  sensitive   = true
}

output "secret_manager_secret_ids" {
  value = module.secrets.secret_ids
}
