variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID (used to derive the Workload Identity pool)"
  type        = string
}

variable "region" {
  description = "Region for the Autopilot cluster"
  type        = string
}

variable "network_self_link" {
  description = "Self link of the VPC to attach the cluster to"
  type        = string
}

variable "subnet_self_link" {
  description = "Self link of the subnet to attach the cluster to"
  type        = string
}
