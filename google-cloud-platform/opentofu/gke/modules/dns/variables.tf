variable "zone_name" {
  description = "Cloudflare zone (registered domain), e.g. lukaszsiedlecki.com"
  type        = string
}

variable "app_hostname" {
  description = "Full hostname the app is served on, e.g. shortliner.lukaszsiedlecki.com"
  type        = string
}

variable "static_ip_address" {
  description = "Gateway's reserved static IP — the A record's target"
  type        = string
}

variable "dns_authorization_record_name" {
  description = "Certificate Manager DNS authorization record name (from the gateway module)"
  type        = string
}

variable "dns_authorization_record_data" {
  description = "Certificate Manager DNS authorization record data/target (from the gateway module)"
  type        = string
}
