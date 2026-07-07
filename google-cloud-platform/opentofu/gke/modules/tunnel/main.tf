# Cloudflare Tunnel replaces the GCP Gateway API + Certificate Manager setup
# entirely: cloudflared (running as a Deployment in-cluster) makes an
# outbound-only connection to Cloudflare's edge, so there's no GCP load
# balancer, forwarding rule, or public IP to pay for. TLS terminates at
# Cloudflare instead of at a Google-managed cert.
resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id = var.account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "main" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id

  config = {
    ingress = [
      {
        hostname = var.app_hostname
        service  = "http://${var.origin_service}"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}
