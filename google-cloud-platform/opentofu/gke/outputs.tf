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

output "gateway_static_ip_address" {
  description = "The Gateway's IP — both DNS records below are managed automatically by the dns module, this is just for reference"
  value       = module.gateway.static_ip_address
}

output "gateway_dns_authorization_record" {
  description = "Reference only — the matching Cloudflare CNAME is created automatically by the dns module"
  value       = module.gateway.dns_authorization_dns_resource_record
}

output "dns_app_record_fqdn" {
  value = module.dns.app_record_fqdn
}

output "gateway_certificate_map_name" {
  description = "Used in the Gateway manifest's networking.gke.io/certmap annotation"
  value       = module.gateway.certificate_map_name
}

output "gateway_static_ip_name" {
  description = "Used in the Gateway manifest's spec.addresses[0].value"
  value       = module.gateway.static_ip_name
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
