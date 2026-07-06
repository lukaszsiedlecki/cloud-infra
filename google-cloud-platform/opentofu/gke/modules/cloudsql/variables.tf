variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for the Cloud SQL instance"
  type        = string
}

variable "tier" {
  description = "Machine tier. Shared-core tiers (e.g. db-f1-micro) have conflicting support signals for Postgres — verify with a real apply before downsizing from this default."
  type        = string
  default     = "db-custom-1-3840"
}

variable "network_id" {
  description = "VPC network ID for the private IP connection"
  type        = string
}

variable "private_service_access_connection" {
  description = "The network module's service networking connection, so Cloud SQL waits for the peering to exist first"
  type        = any
}
