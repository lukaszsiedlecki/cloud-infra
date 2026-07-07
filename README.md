# cloud-infra

Infrastructure-as-code across cloud providers, one top-level directory per
provider so new ones (AWS, Azure, etc.) can be added as siblings without
restructuring anything already here. Provider-specific tooling, credentials,
and CI all stay scoped inside their own directory — nothing provider-specific
lives at repo root.

## Providers

- [`google-cloud-platform/`](google-cloud-platform/) — GCP infra for
  `shortliner-prod`, provisioned with OpenTofu (GKE Autopilot, Cloud SQL,
  Secret Manager, Cloudflare Tunnel) plus the Kubernetes manifests and
  promotion workflow that deploy to it. See its README for setup and
  day-to-day usage.
