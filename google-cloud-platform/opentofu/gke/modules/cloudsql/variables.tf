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
  description = "Machine tier. db-f1-micro (shared-core) is confirmed to work for PostgreSQL and is the cheapest available option — verified against the real project/region, not just docs."
  type        = string
  default     = "db-f1-micro"
}

variable "network_id" {
  description = "VPC network ID for the private IP connection"
  type        = string
}

variable "private_service_access_connection" {
  description = "The network module's service networking connection, so Cloud SQL waits for the peering to exist first"
  type        = any
}
