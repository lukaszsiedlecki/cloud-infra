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

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "shortliner"
}

variable "domain" {
  description = "Domain the Gateway serves"
  type        = string
  default     = "shortliner.lukaszsiedlecki.com"
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-1-3840"
}
