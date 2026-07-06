terraform {
  # Bucket created by ../bootstrap — must match its state_bucket_name output.
  backend "gcs" {
    bucket = "shortliner-prod-tofu-state"
    prefix = "gke"
  }
}
