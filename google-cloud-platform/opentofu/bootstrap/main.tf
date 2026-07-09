terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  # Deliberately local state: this config manages exactly one bucket that
  # essentially never changes after creation, and it's the thing that would
  # otherwise host its own backend (chicken-and-egg). Never migrate this
  # state into the bucket it creates.
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "tofu_state" {
  name     = var.state_bucket_name
  location = var.region
  project  = var.project_id

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Keep the bucket from growing unbounded with old state versions.
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }
}
