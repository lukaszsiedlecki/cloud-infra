# cloud-infra

Multi-cloud infrastructure-as-code. One top-level directory per provider so new ones (AWS, Azure, etc.) can be added as siblings without restructuring anything. Provider-specific tooling, credentials, and CI stay scoped inside their own directory — never add provider-specific config at repo root.

**Exception: GitHub Actions workflow files must live at the real repo-root `.github/workflows/`.** This is a hard GitHub platform constraint, not a style choice — GitHub only ever discovers workflows there, never in a nested subdirectory. A prior version of this repo had `google-cloud-platform/.github/workflows/promote.yml`, which GitHub silently never triggered — confirmed via the API, zero workflow runs in the repo's history until this was fixed (2026-07-09). Provider-scoping for the workflow's *behavior* still applies as normal: path filters (`paths: ['google-cloud-platform/...']`) and `working-directory` keep each workflow's actual effect scoped to its provider directory even though the YAML file itself must sit at the root.

## Providers

- **`google-cloud-platform/`** — GCP infra for `shortliner-prod`. See `google-cloud-platform/CLAUDE.md` for the full context, current state, and every operational gotcha discovered so far. Read that file before doing anything in this directory.

No other provider directories exist yet.
