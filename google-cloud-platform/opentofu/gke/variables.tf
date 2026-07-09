variable "project_id" {
  description = "GCP project ID (created manually before running this config)"
  type        = string
  default     = "shortliner-prod"
}

variable "region" {
  description = "Region for all resources"
  type        = string
  default     = "europe-central2"
}

variable "zone" {
  description = "Zone for the zonal GKE cluster — chosen for GKE's free-tier zonal control plane (one free zonal cluster per billing account), vs. a flat ~$73/mo for a regional control plane"
  type        = string
  default     = "europe-central2-a"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "shortliner"
}

variable "domain" {
  description = "Domain the app is served on, routed via Cloudflare Tunnel"
  type        = string
  default     = "shortliner.lukaszsiedlecki.com"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. db-f1-micro (shared-core, 614 MiB RAM) is the cheapest option that supports PostgreSQL, chosen for this low-traffic learning project — resize up (e.g. db-g1-small or a db-custom-* tier) if memory pressure becomes a real problem."
  type        = string
  default     = "db-f1-micro"
}

variable "cloudflare_zone" {
  description = "Cloudflare zone (registered domain) that `domain` is a subdomain of"
  type        = string
  default     = "lukaszsiedlecki.com"
}

# no-op: testing infra.yml plan job
