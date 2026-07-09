resource "google_container_cluster" "main" {
  provider = google-beta

  name     = "${var.name_prefix}-cluster"
  location = var.zone

  network    = var.network_self_link
  subnetwork = var.subnet_self_link

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Standard mode requires an explicit node pool to manage ourselves — the
  # cluster's own default pool is removed immediately in favor of the
  # google_container_node_pool.primary resource below.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Automatic on Autopilot; must be explicit on Standard, and modules/secrets
  # relies on this pool string via the workload_identity_pool output below.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  # Learning project: avoid an extra confirmation step / API call getting in
  # the way of iterating on the cluster. Revisit if this ever holds anything
  # precious enough to need it.
  deletion_protection = false

  # Enables the Secret Manager CSI driver component (the SecretProviderClass
  # side).
  secret_manager_config {
    enabled = true
  }

  # GKE's separate "Secret Sync" feature (the SecretSync CRD that actually
  # materializes a real k8s Secret, which k8s/shortliner/02-secretsync.yaml
  # depends on).
  secret_sync_config {
    enabled = true
  }

  # Standard enables Google Managed Prometheus by default (kube-state-metrics
  # + a collector/operator pair), costing ~110m CPU on a node this small for
  # observability nobody's looking at on a personal project — same "trim
  # unused overhead" call as the CSI drivers below. Left SYSTEM_COMPONENTS
  # logging/monitoring enabled since those are genuinely useful and cheap.
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false
    }
  }

  addons_config {
    # Autopilot enables these three by default even though nothing in this
    # project uses Filestore, GCS Fuse, or Parallelstore volumes — disabled
    # to avoid the DaemonSet overhead. Standard doesn't force them on, but
    # kept explicit for parity/documentation.
    gcp_filestore_csi_driver_config {
      enabled = false
    }

    gcs_fuse_csi_driver_config {
      enabled = false
    }

    parallelstore_csi_driver_config {
      enabled = false
    }

    # Standard enables the GLBC ingress controller by default. This project
    # has zero Ingress objects (Cloudflare Tunnel only) — skip running that
    # pod on our one small node.
    http_load_balancing {
      disabled = true
    }
  }
}

# Dedicated node runtime SA. Without this, Standard node pools default to
# the project's Compute Engine default SA, which carries roles/editor —
# near-full project control. A container breakout or host compromise can
# read that SA's token straight off the node's metadata server, so the
# blast radius of "attacker gets code execution on this node" is normally
# "attacker owns the GCP project." This SA instead gets only the three
# roles GKE's own hardening guidance recommends for node-level logging/
# monitoring — the same telemetry the previous oauth_scopes already limited
# it to, now backed by IAM instead of an Editor-scoped account.
resource "google_service_account" "node" {
  account_id   = "${var.name_prefix}-gke-node"
  display_name = "GKE node runtime SA for ${var.name_prefix}-cluster"
  project      = var.project_id
}

resource "google_project_iam_member" "node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_resource_metadata_writer" {
  project = var.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_container_node_pool" "primary" {
  provider = google-beta

  name     = "${var.name_prefix}-primary-pool"
  cluster  = google_container_cluster.main.name
  location = var.zone

  node_count = var.node_count

  node_config {
    machine_type    = var.machine_type
    spot            = var.spot
    service_account = google_service_account.node.email

    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type

    # Standard-mode equivalent of the automatic GKE Metadata Server config
    # Autopilot gives for free — required for Workload Identity to work.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # sleep.sh/wake.sh resize this out-of-band via `gcloud container clusters
  # resize` for real cost savings (stops the actual VMs, not just pods) —
  # don't let tofu fight that back to var.node_count on the next apply.
  # Same pattern as modules/cloudsql's activation_policy ignore_changes.
  lifecycle {
    ignore_changes = [node_count]
  }
}
