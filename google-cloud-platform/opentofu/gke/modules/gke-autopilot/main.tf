resource "google_container_cluster" "main" {
  provider = google-beta

  name     = "${var.name_prefix}-cluster"
  location = var.region

  enable_autopilot = true

  network    = var.network_self_link
  subnetwork = var.subnet_self_link

  release_channel {
    channel = "REGULAR"
  }

  # Learning project: avoid an extra confirmation step / API call getting in
  # the way of iterating on the cluster. Revisit if this ever holds anything
  # precious enough to need it.
  deletion_protection = false

  # Lets pods sync Secret Manager values into a real k8s Secret via
  # SecretProviderClass/SecretSync, keeping the existing secretKeyRef-based
  # env var wiring in the apps unchanged.
  secret_manager_config {
    enabled = true
  }

  # Not on by default even on Autopilot — required for the Gateway/HTTPRoute
  # CRDs used in k8s/shortliner/05-gateway.yaml and 05-httproute.yaml.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Workload Identity is enabled automatically on Autopilot clusters and
  # isn't configurable here — not set explicitly to avoid fighting that.
}
