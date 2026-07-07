variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_number" {
  description = "GCP project number (needed for the Workload Identity principal member string)"
  type        = string
}

variable "workload_identity_pool" {
  description = "Workload Identity pool, e.g. <project_id>.svc.id.goog"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the KSAs live in"
  type        = string
  default     = "shortliner"
}

variable "shortliner_db_user" {
  type = string
}

variable "shortliner_db_password" {
  type      = string
  sensitive = true
}

variable "shortliner_analytics_db_user" {
  type = string
}

variable "shortliner_analytics_db_password" {
  type      = string
  sensitive = true
}

variable "tunnel_token" {
  description = "Cloudflare Tunnel token, consumed by the cloudflared Deployment"
  type        = string
  sensitive   = true
}
