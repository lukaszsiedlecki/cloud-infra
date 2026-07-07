variable "zone_id" {
  description = "Cloudflare zone ID (looked up once at root level and shared with the tunnel module, to avoid a circular module dependency)"
  type        = string
}

variable "app_hostname" {
  description = "Full hostname the app is served on, e.g. shortliner.lukaszsiedlecki.com"
  type        = string
}

variable "tunnel_id" {
  description = "Cloudflare Tunnel ID (from the tunnel module) — the CNAME target is {tunnel_id}.cfargotunnel.com"
  type        = string
}
