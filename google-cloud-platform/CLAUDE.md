# google-cloud-platform — CLAUDE.md

Read this before touching anything in this directory. It's the complete context for `shortliner-prod`: a personal/learning GCP deployment of the `shortliner` URL-shortener app, provisioned with OpenTofu. It runs **alongside** an already-working homelab (Talos + ArgoCD) dev/UAT deployment of the same app — homelab is untouched and out of scope for anything here.

Full narrative history and design rationale (much more verbose than this file) lives in the Obsidian vault: `~/repo/second-brain/10-projects/shortliner/shortliner-prod-gcp-deployment.md`. This CLAUDE.md is the condensed, current-state version — read the Obsidian note if you need the "why" behind a decision in more depth.

## Current live state (as of 2026-07-09, end of session)

Everything below is **actually deployed and verified working** unless noted otherwise. The entire stack was destroyed and rebuilt from scratch this session (moving off Autopilot — see Architecture below), so private IPs, secret versions, etc. are new since the previous session.

- GKE **Standard** cluster `shortliner-cluster`, **zonal** in `europe-central2-a`, single-node pool `shortliner-primary-pool` (`e2-standard-2`, Spot, 30GB `pd-balanced`).
- Cloud SQL `shortliner-pg` (`db-f1-micro`, `PD_HDD`, private IP `10.158.0.3` — **will change again on any future destroy/recreate**, see gotcha below) running with 2 databases.
- Kafka (Strimzi 1.1.0, single broker) running in `kafka` namespace.
- App pods in `shortliner` namespace — **all Running**, including `shortliner-analytics` (previously stuck at 0 replicas on Autopilot due to node-capacity crunch; the Standard-mode migration fixed this as a side effect):
  - `shortliner`, `shortliner-frontend`, `shortliner-analytics`, `cloudflared` — all **Running**.
- `https://shortliner.lukaszsiedlecki.com` resolves and serves the frontend through the Cloudflare Tunnel — verified with `curl -I`, got `HTTP/2 200`.
- Sleep/wake **verified end-to-end this session**, including the real GKE node pool resize (not just pod-level idling — confirmed `gcloud compute instances list` shows 0 instances while asleep).
- GitHub side fully wired: `production` environment exists on `cloud-infra` with `lukaszsiedlecki` as required reviewer, `GCP_SA_KEY` secret set, and all 3 service repos (`shortliner`, `shortliner-analytics`, `shortliner-frontend`) have `CLOUD_INFRA_DISPATCH_TOKEN` set and dispatch to `cloud-infra` on push to `master`.
- A temporary `tofu-bootstrap` GCP service account (Owner role) and key at `~/tofu-bootstrap-key.json` are **still in use** — needed because normal `gcloud auth application-default login` is broken for this account (see gotchas). **Do not delete this until the user confirms they're done with active infra changes** — it's the only way `tofu`/`gcloud` commands in this project currently authenticate.
- All Terraform providers upgraded to latest this session: `hashicorp/google`/`google-beta` `~> 7.0` (was `~> 6.0`), `cloudflare/cloudflare` `~> 5.0` (patch-latest 5.21.1), `hashicorp/random` `~> 3.6` (patch-latest 3.9.0). The 7.x bump is what unlocked declaring `secret_sync_config` in Terraform (see Architecture).

## Architecture (locked-in decisions — don't re-litigate without new info)

- **GKE Standard**, zonal in `europe-central2-a` (Warsaw region, chosen for latency — user is Poland-based). Switched from Autopilot this session purely for cost: Autopilot forced ~3-4 nodes minimum (mandatory system-only nodes kept separate from workload nodes) with a fixed, non-configurable 100GiB boot disk each, wildly oversized for this workload. Zonal (not regional) specifically to qualify for GKE's free-tier zonal control plane (one free zonal cluster per billing account) vs. ~$73/mo flat for a regional control plane.
  - Single fixed-size node pool (`shortliner-primary-pool`, 1 node, **not** autoscaled — sleep.sh/wake.sh explicitly resize it 0↔1 via `gcloud container clusters resize`, and `lifecycle.ignore_changes = [node_count]` in Terraform keeps `tofu apply` from fighting that).
  - Machine type is `e2-standard-2` (dedicated, non-shared-core, ~1930m allocatable CPU) — **`e2-medium` was tried first and does not work**: its "2 vCPU" is shared-core/burstable, and GKE's allocatable-CPU calculation trims it to ~940m, of which GKE's own mandatory system pods (kube-dns, kube-proxy, csi-secrets-store, gke-metadata-server, fluentbit, konnectivity, netd, node-local-dns) already consume ~930m by themselves — leaving no room for any app workload. Confirmed live (every pod stuck `Pending` on "Insufficient cpu") before switching to `e2-standard-2`.
  - Google Managed Prometheus (the default-on `kube-state-metrics` + `gmp-operator`/`collector` trio, ~110m CPU) is explicitly disabled via `monitoring_config { managed_prometheus { enabled = false } }` — nobody's using it for this project, and every millicore matters on a single small node. `SYSTEM_COMPONENTS` logging/monitoring stays on (cheap, useful).
  - Standard mode is VPC-native and needs explicit secondary IP ranges for pods/services (`modules/network`: `10.20.0.0/21` pods, `10.30.0.0/24` services) and an explicit `workload_identity_config` block on the cluster (automatic under Autopilot, not under Standard) — `modules/secrets`' IAM bindings depend on this actually being present.
  - `http_load_balancing` addon explicitly disabled — Standard enables the GLBC ingress controller by default; this project has zero `Ingress` objects (Cloudflare Tunnel only), so it's dead weight on the one small node.
- **Cloud SQL Postgres**: `db-f1-micro` (cheapest tier confirmed to work for Postgres), `PD_HDD` (not SSD default), private-IP-only, no backups, `edition = "ENTERPRISE"` set explicitly.
- **Kafka**: self-hosted via Strimzi operator, **single combined controller+broker node** (not homelab's 2-node dual-role pool — cost/simplicity call for a project with no real traffic), KRaft mode, internal-only (no external LoadBalancer). Operator installed manually via Helm, out-of-band (matches homelab convention) — only the `Kafka`/`KafkaNodePool` CRs live in git.
- **Ingress: Cloudflare Tunnel**, not GCP Gateway API/Load Balancer. This was a deliberate reversal — the original Gateway API + Certificate Manager design cost a flat ~$18-20/month regardless of traffic (the single biggest recurring cost in the whole stack). `cloudflared` runs as a Deployment, makes an outbound-only connection to Cloudflare's edge. **No GCP load balancer or public IP exists in this project at all.** TLS terminates at Cloudflare.
- **DNS**: Cloudflare, managed via Terraform (`cloudflare` provider), not Google Cloud DNS.
- **Secrets**: Google Secret Manager, synced into real k8s Secrets via GKE's Secret Sync feature. **Now fully Terraform-managed** — `secret_sync_config { enabled = true }` is declared directly on the cluster resource (needed the 7.x provider bump this session; previously this was undeclared out-of-band `gcloud` drift, now closed).
- **Spot VMs**: the node pool runs on Spot pricing (`spot = true` in `modules/gke`), and every app Deployment + the Strimzi `KafkaNodePool` already carries the `cloud.google.com/gke-spot` nodeSelector/toleration — this required zero k8s manifest changes when moving off Autopilot, since GKE applies that label/taint to any Spot node pool automatically, Autopilot or Standard.
- **No ArgoCD**: GitHub Actions promotion (`repository_dispatch` → `cloud-infra`'s `promote.yml`) patches image tags via `yq` and applies directly with `kubectl`, gated behind a `production` GitHub Environment requiring manual approval.
- **GitHub→GCP auth**: long-lived SA JSON key (`GCP_SA_KEY` secret) — Workload Identity Federation is an explicit, deliberately-deferred future step.
- **Sleep/wake cost control**: `k8s/scripts/sleep.sh`/`wake.sh` scale app Deployments + Kafka node pool to 0, stop Cloud SQL, **and now also resize the real GKE node pool to 0** (new this session — Standard mode has real billable VMs, unlike Autopilot). No load-balancer floor cost to worry about (Cloudflare Tunnel has none).
- `shortliner-auth` is fully out of scope (disabled in homelab too, not ready).

## Repo layout

```
opentofu/
  bootstrap/        # one-time, local-state, creates the GCS state bucket. Never touch during normal work.
  gke/              # the main stack — see modules/ for network, gke, cloudsql, iam, secrets, dns, tunnel
k8s/
  shortliner/       # namespace, KSAs, SecretSync, app Deployments/Services, cloudflared
  kafka/            # Strimzi KafkaNodePool + Kafka CRs (operator itself installed manually, see k8s/kafka/README.md)
  scripts/          # sleep.sh / wake.sh
.github/workflows/promote.yml   # repository_dispatch listener, patches image tag, kubectl applies
```

(`modules/gke-autopilot/` was renamed to `modules/gke/` this session — the old name baked a mode choice into the module name that's now wrong; matches the naming convention of every other module.)

## Operational gotchas (real issues hit and fixed — don't rediscover these)

1. **ADC login is broken for this GCP account.** `gcloud auth application-default login` (incl. `--no-browser`) repeatedly drops the `cloud-platform`/`sqlservice.login` scopes during consent. Workaround in active use: the `tofu-bootstrap` SA key described above. Always `export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-bootstrap-key.json` before running `tofu` or `gcloud` commands for this project.

2. **`google_service_networking_connection` has flaky provider polling on create**, not a real auth issue. Fails with a gRPC UNAUTHENTICATED-looking error while *waiting* for the operation (confirmed: the same call via plain `gcloud services vpc-peerings connect` succeeds immediately). Fix when it recurs:
   ```bash
   gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com \
     --ranges=shortliner-psa-range --network=shortliner-vpc --project=shortliner-prod
   tofu import 'module.network.google_service_networking_connection.private_service_access' \
     "projects/shortliner-prod/global/networks/shortliner-vpc:servicenetworking.googleapis.com"
   ```
   **The same resource can also get stuck on *delete*** (`tofu destroy`), with error `FLOW_SN_DC_RESOURCE_PREVENTING_DELETE_CONNECTION` / "Producer services are still using this connection" — this is a [known terraform-provider-google v5+ regression](https://github.com/hashicorp/terraform-provider-google/issues/16275) where the provider's `deleteConnection` API call can hang indefinitely even after Cloud SQL is fully deleted (confirmed: waited over an hour across retries, still stuck). Fix: `gcloud compute networks peerings delete servicenetworking-googleapis-com --network=<vpc> --project=<project>` — the older Compute Engine peering API path deletes it cleanly in seconds where the Service Networking API path hangs. Then re-run `tofu destroy` to clean up the remaining network/address resources (it'll detect the drift and proceed).

3. **Cloud SQL now defaults to ENTERPRISE_PLUS edition**, which rejects `db-custom-*`/shared-core tiers. Already fixed in code (`edition = "ENTERPRISE"` in `modules/cloudsql/main.tf`) — just know why it's there if you see it.

4. **Strimzi API version**: the deployed operator (1.1.0) serves `kafka.strimzi.io/v1`, not `v1beta2`, and `storage.volumes[].storageClass` is renamed to `.class` in v1. Already fixed in `k8s/kafka/01-kafka-cluster.yaml`. Always verify Strimzi manifests with `kubectl apply --dry-run=server` before trusting them, especially after any operator upgrade.

5. **GKE Standard's mandatory system-pod overhead is much larger than it looks, and shared-core machine types make it worse.** `e2-medium` reports only ~940m allocatable CPU out of its nominal "2 vCPU" (shared-core/burstable machines get trimmed hard by GKE's allocatable calculation), and GKE's own mandatory system DaemonSets/Deployments (kube-dns, kube-proxy, csi-secrets-store, gke-metadata-server, fluentbit, konnectivity, netd, node-local-dns) already consume ~930m of that by themselves. On a single-node cluster this leaves **zero room for any app workload**, confirmed live via every pod stuck `Pending` on "Insufficient cpu" before switching to `e2-standard-2` (dedicated cores, ~1930m allocatable). If sizing a single-node Standard cluster again: budget ~930m CPU as a fixed system floor before counting your own workload's requests, and don't use shared-core (`e2-small`/`e2-medium`) machine types for anything tight — dedicated-core `e2-standard-*` reports much closer to nominal capacity.

6. **Google Managed Prometheus is enabled by default on Standard clusters** (`kube-state-metrics` in `gke-managed-cim` namespace + `gmp-operator`/`collector` in `gmp-system`, ~110m CPU combined) — worth disabling explicitly (`monitoring_config { managed_prometheus { enabled = false } }`) on any resource-constrained cluster where nobody's actually looking at the metrics.

7. **`gcloud`'s own client-side operation-wait can time out well before the server-side operation actually finishes** — hit this twice this session: once with `tofu apply` (5-minute Bash tool timeout killed the client mid-`google_container_cluster` update; the GKE API call kept running and completed successfully server-side, confirmed via `gcloud container operations describe <op-id>` showing `DONE`), and once with `gcloud sql instances patch --activation-policy=ALWAYS` inside `wake.sh` (client gave up after its own internal timeout with "taking longer than expected", but the operation itself finished fine, confirmed via `gcloud beta sql operations wait <op-id>`). **Don't assume a timed-out/killed client command means the underlying change failed** — check the operation ID directly before retrying or treating it as an error. A killed `tofu apply` also leaves the GCS state lock stuck (`tofu force-unlock -force <lock-id>` after confirming no `tofu` process is still running).

8. **Cloud SQL's private IP is not stable across recreates.** Confirmed twice this session: `10.80.0.3` → (destroy) → `10.158.0.3`. `k8s/shortliner/03-deployment-shortliner.yaml` and `03-deployment-shortliner-analytics.yaml` currently hardcode `DB_HOST` as a plain env var string — **this will silently break on any future full destroy/recreate** until manually updated to match the new `tofu output cloudsql_private_ip_address`. Worth fixing properly at some point by wiring `DB_HOST` through Secret Sync like the DB credentials already are, instead of a hardcoded literal (see Known outstanding items).

9. **Cloudflare Tunnel's API token permission is mislabeled in the dashboard.** Search "tun" in the token permission UI → only "Argo Tunnel (Legacy)" appears (old product name), and that IS the correct permission (Account-level, needs Edit). "Connectivity Directory" also mentions tunnels but is a different, newer feature — not sufficient on its own.

10. **Historical/no-longer-applicable**: the old Autopilot-specific gotchas (fixed 100GiB non-configurable boot disks, "Autopilot node pools cannot be accessed or modified", 3-of-4-nodes being pure system overhead, `SSD_TOTAL_GB` quota pressure from Autopilot's forced disk size) no longer apply now that this project is on Standard mode with direct node-pool/disk control (`30GB pd-balanced` today). Keeping this note in case Autopilot is ever reconsidered — these were real, confirmed GCP behaviors at the time, not mistakes.

## Known outstanding items

- **`DB_HOST` is hardcoded as a plain string** in `k8s/shortliner/03-deployment-shortliner.yaml` / `03-deployment-shortliner-analytics.yaml` — see gotcha #8. Should eventually be wired through Secret Sync (or a Terraform-templated ConfigMap) instead of a literal that silently goes stale on any Cloud SQL recreate.
- **WIF migration** (replacing `GCP_SA_KEY` with Workload Identity Federation): explicitly deferred, not started.
- **`rebuild.sh` pipeline script**: discussed and designed (see Obsidian note) but not built. Three open questions were left for the user before implementing: image tag handling, Makefile vs plain scripts, whether GitHub secrets setup belongs in the same script.
- **Delete `tofu-bootstrap` SA + key** once the user confirms no more active infra work is planned — don't do this preemptively, it'll break the ability to run `tofu`/`gcloud` for this project.
- **`opentofu/bootstrap/` is on provider `~> 7.0`** (bumped alongside `gke/` this session) but its own state was never re-applied since it's a one-time, already-satisfied config (`tofu plan` there shows no changes) — nothing to do, just noting it's consistent.

## Common commands

```bash
# Always needed first
export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-bootstrap-key.json
export CLOUDFLARE_API_TOKEN=<token>   # only needed for tofu apply/destroy/plan in gke/

# Apply changes
cd opentofu/gke && tofu init && tofu apply

# kubectl context (already added, but if missing) — note --zone, not --region (zonal cluster)
gcloud container clusters get-credentials shortliner-cluster --zone europe-central2-a --project shortliner-prod

# Sleep/wake (now also resizes the real GKE node pool, not just pods/Cloud SQL)
./k8s/scripts/sleep.sh
./k8s/scripts/wake.sh

# Destroy & rebuild from scratch
cd opentofu/gke && tofu destroy   # see gotcha #2 if this hangs on service_networking_connection (create OR delete)
# then follow the full runbook in the Obsidian note, starting from "Apply the main stack"
# Remember: Cloud SQL's private IP will change (gotcha #8) — update DB_HOST in the k8s manifests
# before kubectl apply, and re-run the Strimzi operator Helm install (out-of-band, see k8s/kafka/README.md)
```

## Working conventions for this project

- This is a **learning + cost-conscious personal project** — when in doubt, favor the cheaper/simpler option, but always flag the tradeoff rather than silently picking one.
- **Verify against live GCP/kubectl state before assuming anything from past notes is still true** — this file and the Obsidian note are snapshots, not live status. `tofu state list`, `kubectl get pods -A`, and `gcloud` describe commands are authoritative.
- Mirror homelab's conventions (namespace `shortliner`, numbered manifest files, security context patterns) except where GKE's constraints genuinely require differing — and flag those differences explicitly rather than silently adjusting.
- Don't re-ask questions already answered in this file or the Obsidian note (e.g. Kafka broker count, ingress choice, DB tier, GKE Standard vs Autopilot) unless the user explicitly reopens the decision.
- Never fabricate credential values or ask the user to paste real secrets into chat.
