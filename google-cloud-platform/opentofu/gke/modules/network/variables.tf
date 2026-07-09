variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "region" {
  description = "Region for the subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "Primary IP range for the subnet"
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range for pod IPs — /21 (2048 IPs) is ample for a 1-2 node cluster. Chosen clear of the subnet's own 10.10.0.0/20 and the historical PSA auto-picked range (previously ~10.80.0.0/16, not guaranteed identical each time)."
  type        = string
  default     = "10.20.0.0/21"
}

variable "services_cidr" {
  description = "Secondary range for service IPs"
  type        = string
  default     = "10.30.0.0/24"
}
