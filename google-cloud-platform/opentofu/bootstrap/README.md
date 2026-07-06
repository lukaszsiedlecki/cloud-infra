# Bootstrap

Creates the single GCS bucket used as the OpenTofu state backend for `../gke`.
This config's own state stays **local** (`terraform.tfstate` in this directory,
gitignored) — it manages one resource that essentially never changes, and it's
the thing that would host the backend for everything else, so it can't
bootstrap itself.

## Prerequisites

- `shortliner-prod` GCP project already exists and is linked to a billing account (created manually).
- You're authenticated: `gcloud auth application-default login`.

## Usage

Run once, before ever touching `../gke`:

```bash
cd opentofu/bootstrap
tofu init
tofu apply
```

Note the `state_bucket_name` output — it must match the `bucket` value in
`../gke/backend.tf`.

## If you ever need to change this bucket

Edit and `tofu apply` again from this directory using the local state file.
Do not attempt to move this config's state into the bucket it manages.
