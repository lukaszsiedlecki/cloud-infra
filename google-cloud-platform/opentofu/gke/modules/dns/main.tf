data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

# Certificate Manager's domain-validation record. DNS-only by nature — this
# is read by Google's validation servers, not browsers, so Cloudflare's
# proxy has nothing to do here.
resource "cloudflare_dns_record" "cert_validation" {
  zone_id = data.cloudflare_zone.main.id
  name    = trimsuffix(var.dns_authorization_record_name, ".")
  type    = "CNAME"
  content = trimsuffix(var.dns_authorization_record_data, ".")
  ttl     = 300
  proxied = false
  comment = "Certificate Manager domain validation for the shortliner Gateway — do not proxy"
}

# The app's public hostname. Deliberately DNS-only (not proxied/orange-cloud):
# TLS termination happens at the GCP Gateway with its own managed cert
# (opentofu/gke/modules/gateway) — proxying this through Cloudflare would put
# a second, unrelated TLS/routing layer in front of it.
resource "cloudflare_dns_record" "app" {
  zone_id = data.cloudflare_zone.main.id
  name    = var.app_hostname
  type    = "A"
  content = var.static_ip_address
  ttl     = 300
  proxied = false
  comment = "shortliner-prod Gateway static IP — must stay DNS-only, not proxied"
}
