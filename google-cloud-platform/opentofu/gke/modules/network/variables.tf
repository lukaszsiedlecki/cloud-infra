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
