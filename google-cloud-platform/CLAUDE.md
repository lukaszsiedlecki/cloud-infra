# google-cloud-platform — CLAUDE.md

Read this before touching anything in this directory. It's the complete context for `shortliner-prod`: a personal/learning GCP deployment of the `shortliner` URL-shortener app, provisioned with OpenTofu. It runs **alongside** an already-working homelab (Talos + ArgoCD) dev/UAT deployment of the same app — homelab is untouched and out of scope for anything here.

Full narrative history and design rationale (much more verbose than this file) lives in the Obsidian vault: `~/repo/second-brain/10-projects/shortliner/shortliner-prod-gcp-deployment.md`. This CLAUDE.md is the condensed, current-state version — read the Obsidian note if you need the "why" behind a decision in more depth.

## Current live state (as of 2026-07-09, end of session)

Everything below is **actually deployed and verified working** unless noted otherwise.

- GKE **Standard** cluster `shortliner-cluster`, **zonal** in `europe-central2-a`, single-node pool `shortliner-primary-pool` (`e2-standard-2`, Spot, 30GB `pd-balanced`).
- Cloud SQL `shortliner-pg` (`db-f1-micro`, `PD_HDD`) running with 2 databases. `DB_HOST` flows through Terraform → Secret Manager → Secret Sync automatically — no manual manifest edits needed after any future rebuild.
- Kafka (Strimzi 1.1.0, single broker) running in `kafka` namespace.
- App pods in `shortliner` namespace — **all Running**: `shortliner`, `shortliner-analytics`, `shortliner-frontend`, `cloudflared`.
- `https://shortliner.lukaszsiedlecki.com` resolves and serves the frontend through the Cloudflare Tunnel — verified with `curl -I`, got `HTTP/2 200`.
- Sleep/wake verified end-to-end, including the real GKE node pool resize (not just pod-level idling).
- **CI/CD fully rebuilt this session — see "CI/CD architecture" below.** All 3 app repos (`shortliner`, `shortliner-analytics`, `shortliner-frontend`) now build, tag, and deploy themselves directly to `shortliner-prod` via GitHub OIDC → GCP Workload Identity Federation, verified live end-to-end (real image builds, real gated deploys, real rollouts, confirmed via `kubectl` and the live site). `cloud-infra` itself has its own `infra.yml` pipeline for `tofu plan`/`apply`/`destroy`, also WIF-based, also verified live (a real `apply` ran cleanly behind approval; the `destroy` path was verified to reach its approval gate correctly and was deliberately rejected, never executed).
- **No long-lived GCP credentials remain in any GitHub repo.** `GCP_SA_KEY` (env-scoped secret on `cloud-infra`'s `production` environment) and the underlying `google_service_account_key.github_deployer` Terraform resource are both deleted. The `tofu-bootstrap` SA + local key at `~/tofu-bootstrap-key.json` still exists as a **manual human fallback only** (ADC login is still broken for this account, see gotchas) — it's no longer the primary path for anything, CI handles routine work now.
- All Terraform providers on latest as of last check: `hashicorp/google`/`google-beta` `~> 7.0` (7.39.0), `cloudflare/cloudflare` `~> 5.0` (5.21.1), `hashicorp/random` `~> 3.6` (3.9.0).

## CI/CD architecture (new this session — replaces the old promote.yml design entirely)

**App repos own their own deploy.** Each of `shortliner`, `shortliner-analytics`, `shortliner-frontend` has its own `k8s/deployment.yaml` + `k8s/service.yaml` (moved out of this repo — they're app-specific, not infra) and its own `deploy` job in `.github/workflows/deploy.yml`: build+push image to GHCR → patch the image tag into its own `k8s/deployment.yaml` via `yq`, commit the bump back to its own repo (audit trail) → authenticate to GCP via WIF (`google-github-actions/auth@v2`, no key) → `kubectl apply` + rollout-status check. Gated behind that repo's own `production` GitHub Environment (same required reviewer, `lukaszsiedlecki`). The old `repository_dispatch` → `cloud-infra`'s `promote.yml` flow is **completely gone** — `promote.yml` is deleted, has zero remaining callers. Each app repo's separate `notify-homelab` job (dispatches to the unrelated `lukaszsiedlecki/homelab` repo) was **left completely untouched** throughout this whole redesign — different secret (`HOMELAB_DISPATCH_PAT`), different target, not in scope.

**cloud-infra owns its own infra pipeline.** `.github/workflows/infra.yml` (at the real repo root — see gotcha below) has 4 jobs:
- `plan` — runs on every PR touching `opentofu/gke/**`, no approval gate, guarded against fork PRs (repo is public).
- `apply` — runs on push to `main` (same path filter), gated behind the `production` environment.
- `verify-confirmation` — `workflow_dispatch`-only, validates a typed `confirm` input (`destroy-shortliner-prod`) *before* any approval is requested, so a typo fails in seconds with zero reviewer noise.
- `destroy` — `needs: verify-confirmation`, gated behind a **separate** `infra-destroy` environment (deliberately not the same gate as `apply`, so a reviewer can't habit-click through a destroy thinking it's a routine apply).

**Auth**: one shared `google_iam_workload_identity_pool` + `_provider` (`modules/iam`, resource id `shortliner-github-actions`) federates GitHub's OIDC tokens. Two identities hang off it: `shortliner-gh-deployer` (existing SA, `roles/container.developer` only, impersonable by all 3 app repos via `attribute.repository`-scoped bindings) for app deploys, and a new `shortliner-infra-ci` SA (`roles/owner`, scoped to the project, impersonable only by `cloud-infra`) for the infra pipeline — deliberately broad-but-scoped rather than hand-crafted least-privilege, matching what `tofu-bootstrap` already did locally; the real security boundary is WIF (keyless, repo-scoped, no token to leak) plus the required-reviewer gates, not IAM minimization. **This is a completely separate WIF pool from the GKE cluster's own `workload_identity_config`** (used for in-cluster KSA→Secret Manager access, see `modules/gke`/`modules/secrets`) — don't conflate the two.

Repo variables set (not secrets — none of these values are sensitive): `WIF_PROVIDER` and `INFRA_CI_SA_EMAIL` on `cloud-infra`; `WIF_PROVIDER` and `GH_DEPLOYER_SA_EMAIL` on each of the 3 app repos.

## Repo layout

```
opentofu/
  bootstrap/        # one-time, local-state, creates the GCS state bucket. Never touch during normal work.
  gke/              # the main stack — see modules/ for network, gke, cloudsql, iam, secrets, dns, tunnel
k8s/
  shortliner/       # PLATFORM-LEVEL ONLY: namespace, KSAs, SecretSync, cloudflared.
                     # App Deployments/Services live in each app's own repo now (k8s/deployment.yaml,
                     # k8s/service.yaml in shortliner / shortliner-analytics / shortliner-frontend).
  kafka/            # Strimzi KafkaNodePool + Kafka CRs (operator itself installed manually, see k8s/kafka/README.md)
  scripts/          # sleep.sh / wake.sh
```

Root-level (`cloud-infra/`, not `google-cloud-platform/`):
```
.github/workflows/infra.yml   # OpenTofu plan/apply/destroy pipeline for this directory's stack
```
**GitHub Actions workflow files must live at the actual repo root `.github/workflows/`** — this is a hard GitHub platform constraint (GitHub never discovers workflows in a nested subdirectory), overriding the root CLAUDE.md's general "no provider-specific config at root" convention. See that file and gotcha below for the full story.

(`modules/gke-autopilot/` was renamed to `modules/gke/` in an earlier session — matches the naming convention of every other module, no mode baked into the name.)

## Operational gotchas (real issues hit and fixed — don't rediscover these)

1. **ADC login is broken for this GCP account.** `gcloud auth application-default login` (incl. `--no-browser`) repeatedly drops the `cloud-platform`/`sqlservice.login` scopes during consent. Workaround: the `tofu-bootstrap` SA key, now used only as a manual fallback (CI handles routine `tofu`/deploy work via WIF). Always `export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-bootstrap-key.json` before running `tofu` or `gcloud` commands locally for this project.

2. **`google_service_networking_connection` has flaky provider polling on create**, not a real auth issue. Fails with a gRPC UNAUTHENTICATED-looking error while *waiting* for the operation (confirmed: the same call via plain `gcloud services vpc-peerings connect` succeeds immediately). Fix when it recurs:
   ```bash
   gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com \
     --ranges=shortliner-psa-range --network=shortliner-vpc --project=shortliner-prod
   tofu import 'module.network.google_service_networking_connection.private_service_access' \
     "projects/shortliner-prod/global/networks/shortliner-vpc:servicenetworking.googleapis.com"
   ```
   **The same resource can also get stuck on *delete*** (`tofu destroy`), with error `FLOW_SN_DC_RESOURCE_PREVENTING_DELETE_CONNECTION` — a [known terraform-provider-google v5+ regression](https://github.com/hashicorp/terraform-provider-google/issues/16275). Fix: `gcloud compute networks peerings delete servicenetworking-googleapis-com --network=<vpc> --project=<project>` (the older Compute Engine peering API path deletes cleanly where the Service Networking path hangs), then re-run `tofu destroy`.

3. **Cloud SQL now defaults to ENTERPRISE_PLUS edition**, which rejects `db-custom-*`/shared-core tiers. Fixed in code (`edition = "ENTERPRISE"` in `modules/cloudsql/main.tf`).

4. **Strimzi API version**: the deployed operator (1.1.0) serves `kafka.strimzi.io/v1`, not `v1beta2`, and `storage.volumes[].storageClass` is renamed to `.class` in v1. Always verify Strimzi manifests with `kubectl apply --dry-run=server` before trusting them.

5. **GKE Standard's mandatory system-pod overhead is much larger than it looks, and shared-core machine types make it worse.** `e2-medium` reports only ~940m allocatable CPU out of its nominal "2 vCPU"; GKE's own mandatory system pods already consume ~930m of that by themselves — zero room for app workload. Confirmed live (every pod `Pending` on "Insufficient cpu"). Fix: `e2-standard-2` (dedicated cores, ~1930m allocatable). Budget ~930m CPU as a fixed system floor on any single-node Standard cluster; avoid shared-core (`e2-small`/`e2-medium`) machine types.

6. **Google Managed Prometheus is enabled by default on Standard clusters** (~110m CPU) — disable explicitly (`monitoring_config { managed_prometheus { enabled = false } }`) on a resource-constrained cluster nobody's monitoring via Cloud Monitoring dashboards.

7. **`gcloud`/`tofu`'s own client-side operation-wait can time out well before the server-side operation actually finishes.** Hit repeatedly this session (a `tofu apply` killed by a client timeout, a `gcloud sql instances patch` giving up client-side) — in every case the operation had actually succeeded server-side, confirmed via `gcloud container operations describe`/`gcloud beta sql operations wait`. **Don't assume a timed-out client command means the change failed** — check the operation ID directly. A killed `tofu apply` also leaves the GCS state lock stuck (`tofu force-unlock -force <lock-id>` after confirming no `tofu` process is still running).

8. **Cloud SQL's private IP is not stable across recreates**, and `DB_HOST` used to be hardcoded, breaking on every rebuild. **Fixed**: `DB_HOST` now flows through `modules/secrets` → Secret Manager → Secret Sync → `secretKeyRef`, same pattern as the DB credentials, in each app repo's own `k8s/deployment.yaml`.

9. **`SecretSync` doesn't re-poll just because you added a new secret to its `SecretProviderClass`.** `metadata.generation` bumps but `status.observedGeneration` can stay stale for 11+ hours — the new key never appears in the underlying k8s `Secret`. **Fix**: `kubectl delete secretsync <name> -n shortliner` then `kubectl apply` again to force a fresh `Create`. Verify the k8s `Secret`'s actual keys (`kubectl get secret <name> -o jsonpath='{.data}'`) before trusting a `SecretProviderClass` change took effect.

10. **GitHub Actions only discovers workflow files at the literal repo-root `.github/workflows/`, never in a subdirectory.** `promote.yml` lived at `google-cloud-platform/.github/workflows/promote.yml` for a long time — confirmed via the API that this repo had **zero workflow runs in its entire history** until this was fixed. If a workflow ever seems to silently never trigger, check the path first before assuming the trigger config is wrong.

11. **`google-github-actions/setup-gcloud@v2` does not install `gke-gcloud-auth-plugin` by default**, which modern GKE requires for `kubectl` auth. Fails with `exec: executable gke-gcloud-auth-plugin not found` on the first `kubectl apply`/`get` after `gcloud container clusters get-credentials`. Fix: add `with: { install_components: 'gke-gcloud-auth-plugin' }` to the `setup-gcloud` step. Hit this in all 3 app repos' new `deploy` jobs on the first real run — same fix needed anywhere `setup-gcloud` + `kubectl` are combined in a fresh runner.

12. **The `infra_ci` WIF identity's `tofu plan` can show phantom in-place-update diffs** (10 resources — GKE cluster, Cloud SQL instance, an SA key while it still existed, several `google_secret_manager_secret_version`s, `random_password`s — with **zero visible attribute changes**, everything hidden) that the `tofu-bootstrap` key-based identity never sees for the same state. Root cause not fully confirmed — likely a serialization difference between short-lived WIF-issued OAuth tokens and a long-lived key's tokens (e.g. `null` vs `""` on some optional field). **Not dangerous**: confirmed zero adds/destroys/replaces every time, purely in-place. Running `apply` through it once resolves it cleanly and it stays resolved until the next unrelated config change. If `plan` in CI ever shows a bunch of hidden-diff in-place updates with `0 to add, 0 to destroy`, this is almost certainly it — safe to approve.

13. **`gh api ... /pending_deployments` needs `environment_ids` as a JSON integer array**, not `-f environment_ids[]=<id>` (that sends it as a string and 422s). Use `--input -` with a raw JSON body: `{"environment_ids": [123], "state": "approved"}`.

14. **Two separate tool-output prompt-injection attempts were caught this session** while researching via `gh api` and a Bash command against the `shortliner-frontend` repo and general tool output — text formatted to impersonate a Claude Code system reminder, embedded in returned content. Both were correctly identified as non-legitimate and ignored, no action taken on them. Worth periodically auditing `shortliner-frontend` and the general tool chain if this recurs.

15. **Historical/no-longer-applicable**: old Autopilot-specific gotchas (fixed 100GiB boot disks, forced system-node overhead, `SSD_TOTAL_GB` quota pressure) — irrelevant now that this project is on Standard mode. Kept in git history for reference in case Autopilot is ever reconsidered.

## Known outstanding items

- **`opentofu/bootstrap/` is on provider `~> 7.0`** but its own state was never re-applied (one-time config, `tofu plan` there shows no changes — nothing to do).
- **Delete `tofu-bootstrap` SA + key** once confident CI is fully reliable and no more local emergency access is needed — don't do this preemptively, it's still the only fallback if WIF/CI ever breaks.
- ~~WIF migration~~ — **done this session.**
- ~~`rebuild.sh` pipeline script~~ — **superseded by `infra.yml`** (the app-repo self-deploy + infra CI pipeline together cover what `rebuild.sh` was designed to do).

## Common commands

```bash
# Routine infra changes: just open a PR touching opentofu/gke/** against cloud-infra.
# infra.yml handles plan (on PR) and apply (on merge to main, behind approval) automatically.

# Routine app deploys: just push to master in the app's own repo. Its own deploy.yml
# builds, tags, and deploys behind that repo's production environment approval.

# Manual local fallback (ADC is broken for this account, see gotcha #1)
export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-bootstrap-key.json
export CLOUDFLARE_API_TOKEN=<token>   # only needed for tofu apply/destroy/plan in gke/
cd opentofu/gke && tofu init && tofu apply

# kubectl context (note --zone, not --region — zonal cluster)
gcloud container clusters get-credentials shortliner-cluster --zone europe-central2-a --project shortliner-prod

# Sleep/wake (resizes the real GKE node pool, not just pods/Cloud SQL)
./k8s/scripts/sleep.sh
./k8s/scripts/wake.sh

# Destroy the whole stack via CI (requires typed confirmation + separate approval gate)
gh workflow run infra.yml --repo lukaszsiedlecki/cloud-infra -f confirm=destroy-shortliner-prod
# then approve (or reject) the pending deployment on the infra-destroy environment

# Destroy locally (fallback only)
cd opentofu/gke && tofu destroy   # see gotcha #2 if this hangs on service_networking_connection
# Cloud SQL's private IP will change but DB_HOST flows through Secret Sync automatically (gotcha #8).
# Still need to re-run the Strimzi operator Helm install (out-of-band, see k8s/kafka/README.md).
```

## Working conventions for this project

- This is a **learning + cost-conscious personal project** — when in doubt, favor the cheaper/simpler option, but always flag the tradeoff rather than silently picking one.
- **Verify against live GCP/kubectl/GitHub state before assuming anything from past notes is still true** — this file and the Obsidian note are snapshots, not live status. `tofu state list`, `kubectl get pods -A`, `gh run list`, and `gcloud` describe commands are authoritative.
- Mirror homelab's conventions (namespace `shortliner`, numbered manifest files, security context patterns) except where GKE's constraints genuinely require differing — and flag those differences explicitly rather than silently adjusting.
- Don't re-ask questions already answered in this file or the Obsidian note (e.g. Kafka broker count, ingress choice, DB tier, GKE Standard vs Autopilot, manifests-in-app-repos vs cloud-infra, WIF vs SA key) unless the user explicitly reopens the decision.
- Never fabricate credential values or ask the user to paste real secrets into chat.
- **Real production changes** (app repo deploy configs, substantive infra changes) go through a PR the user reviews and merges themselves — don't merge your own PRs or push directly to a repo's default branch for anything beyond a trivial, obviously-correct, already-authorized fix. Human approval gates on GitHub Environments (`production`, `infra-destroy`) are for the user to click through, not to be approved on their behalf even when technically possible via `gh api`.
