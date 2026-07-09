output "cluster_name" {
  value = module.gke.cluster_name
}

output "cloudsql_instance_name" {
  value = module.cloudsql.instance_name
}

output "cloudsql_private_ip_address" {
  description = "Also flows automatically into DB_HOST via modules/secrets -> Secret Sync — this output is just for manual inspection"
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
  description = "Set as the GH_DEPLOYER_SA_EMAIL repo variable in each app repo — impersonated via WIF, no key involved"
  value       = module.iam.deployer_email
}

output "secret_manager_secret_ids" {
  value = module.secrets.secret_ids
}

output "infra_ci_email" {
  value = module.iam.infra_ci_email
}

output "workload_identity_pool_provider_name" {
  value = module.iam.workload_identity_pool_provider_name
}
