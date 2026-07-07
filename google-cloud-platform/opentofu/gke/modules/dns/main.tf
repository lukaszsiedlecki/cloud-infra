# Routes the app hostname through Cloudflare's edge to the tunnel. Unlike a
# normal DNS-only record, this one MUST be proxied (orange cloud) — that's
# what makes Cloudflare intercept the request and forward it into the
# tunnel instead of doing a plain DNS resolution.
resource "cloudflare_dns_record" "app" {
  zone_id = var.zone_id
  name    = var.app_hostname
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
  comment = "shortliner-prod via Cloudflare Tunnel — must stay proxied, unlike a normal DNS-only record"
}
