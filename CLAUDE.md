# cloud-infra

Multi-cloud infrastructure-as-code. One top-level directory per provider so new ones (AWS, Azure, etc.) can be added as siblings without restructuring anything. Provider-specific tooling, credentials, and CI stay scoped inside their own directory — never add provider-specific config at repo root.

## Providers

- **`google-cloud-platform/`** — GCP infra for `shortliner-prod`. See `google-cloud-platform/CLAUDE.md` for the full context, current state, and every operational gotcha discovered so far. Read that file before doing anything in this directory.

No other provider directories exist yet.
