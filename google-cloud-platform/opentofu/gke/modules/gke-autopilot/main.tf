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

  # Enables the Secret Manager CSI driver component only (the
  # SecretProviderClass side). This is NOT the same as GKE's separate
  # "Secret Sync" feature (the SecretSync CRD that actually materializes a
  # real k8s Secret, which k8s/shortliner/02-secretsync.yaml depends on) —
  # that's controlled by a distinct `secret_sync_config` block that only
  # exists starting in provider version 7.x (ours is pinned to ~> 6.0, see
  # versions.tf). Until that provider upgrade is done deliberately (a major
  # version bump, not something to rush mid-deployment), Secret Sync is
  # enabled out-of-band via:
  #   gcloud container clusters update shortliner-cluster \
  #     --region europe-central2 --project shortliner-prod --enable-secret-sync
  # This is real IaC drift — the cluster has a setting Terraform doesn't
  # know about — tracked deliberately here until the provider bump happens.
  secret_manager_config {
    enabled = true
  }

  # Workload Identity is enabled automatically on Autopilot clusters and
  # isn't configurable here — not set explicitly to avoid fighting that.
}
