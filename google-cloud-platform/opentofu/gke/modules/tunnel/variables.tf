variable "account_id" {
  description = "Cloudflare account ID that owns the tunnel"
  type        = string
}

variable "tunnel_name" {
  description = "Name shown for this tunnel in the Cloudflare dashboard"
  type        = string
}

variable "app_hostname" {
  description = "Public hostname routed to the tunnel, e.g. shortliner.lukaszsiedlecki.com"
  type        = string
}

variable "origin_service" {
  description = "Internal service the tunnel forwards to, e.g. shortliner-frontend-svc:80"
  type        = string
}
