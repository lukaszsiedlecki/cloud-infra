variable "project_id" {
  description = "GCP project ID (created manually before running this config)"
  type        = string
  default     = "shortliner-prod"
}

variable "region" {
  description = "Region for the state bucket"
  type        = string
  default     = "europe-central2"
}

variable "state_bucket_name" {
  description = "Globally-unique name for the OpenTofu state bucket"
  type        = string
  default     = "shortliner-prod-tofu-state"
}
