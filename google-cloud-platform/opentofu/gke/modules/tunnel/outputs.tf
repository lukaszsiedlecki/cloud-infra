output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.main.id
}

output "tunnel_token" {
  description = "Fed into the cloudflared Deployment via Secret Manager + SecretSync (see modules/secrets and k8s/shortliner). Never commit this value."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.main.token
  sensitive   = true
}
