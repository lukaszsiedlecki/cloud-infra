variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "domain" {
  description = "Domain the Gateway serves, e.g. shortliner.lukaszsiedlecki.com"
  type        = string
}
