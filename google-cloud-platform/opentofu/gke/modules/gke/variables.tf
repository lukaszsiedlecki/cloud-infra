variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID (used to derive the Workload Identity pool)"
  type        = string
}

variable "zone" {
  description = "Zone for the zonal cluster and its node pool — qualifies for GKE's free zonal control-plane tier (one free zonal cluster per billing account), unlike a regional cluster"
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

variable "pods_range_name" {
  description = "Name of the subnet's secondary IP range for pod IPs"
  type        = string
}

variable "services_range_name" {
  description = "Name of the subnet's secondary IP range for service IPs"
  type        = string
}

variable "machine_type" {
  description = "Node machine type. e2-medium (2 vCPU shared-core, 4GB) was tried first but proved insufficient in practice: GKE's own mandatory system pods (kube-dns, kube-proxy, csi-secrets-store, gke-metadata-server, fluentbit, konnectivity, netd, node-local-dns, managed Prometheus) consume ~930m of e2-medium's ~940m allocatable CPU by themselves, leaving no room for the ~800m the app workload needs. e2-standard-2 is dedicated (non-shared-core) 2 vCPU with ~1930m allocatable — comfortably fits both."
  type        = string
  default     = "e2-standard-2"
}

variable "spot" {
  description = "Run the node pool on Spot VMs for cost savings"
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Boot disk size per node — Autopilot forced a fixed 100GiB; right-sized down now that Standard gives direct control"
  type        = number
  default     = 30
}

variable "disk_type" {
  description = "Boot disk type per node"
  type        = string
  default     = "pd-balanced"
}

variable "node_count" {
  description = "Fixed node count — manually resized to 0 by sleep.sh and back to this value by wake.sh, not managed by a cluster autoscaler"
  type        = number
  default     = 1
}
