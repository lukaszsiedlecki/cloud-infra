# google-cloud-platform — CLAUDE.md

Read this before touching anything in this directory. It's the complete context for `shortliner-prod`: a personal/learning GCP deployment of the `shortliner` URL-shortener app, provisioned with OpenTofu. It runs **alongside** an already-working homelab (Talos + ArgoCD) dev/UAT deployment of the same app — homelab is untouched and out of scope for anything here.

Full narrative history and design rationale (much more verbose than this file) lives in the Obsidian vault: `~/repo/second-brain/10-projects/shortliner/shortliner-prod-gcp-deployment.md`. This CLAUDE.md is the condensed, current-state version — read the Obsidian note if you need the "why" behind a decision in more depth.

## Current live state (as of 2026-07-07, end of session)

Everything below is **actually deployed and verified working** unless noted otherwise:

- GKE Autopilot cluster `shortliner-cluster` running in `europe-central2`.
- Cloud SQL `shortliner-pg` (`db-f1-micro`, `PD_HDD`, private IP) running with 2 databases.
- Kafka (Strimzi, single broker) running in `kafka` namespace.
- App pods in `shortliner` namespace:
  - `shortliner` (core service) — **Running**
  - `shortliner-frontend` — **Running**
  - `cloudflared` — **Running**
  - `shortliner-analytics` — **intentionally scaled to 0 / Pending**, see "Known outstanding items" below. This is not broken — it was a deliberate capacity tradeoff.
- `https://shortliner.lukaszsiedlecki.com` resolves and serves the frontend through the Cloudflare Tunnel — verified with `curl -I`, got `HTTP/2 200`.
- GitHub side fully wired: `production` environment exists on `cloud-infra` with `lukaszsiedlecki` as required reviewer, `GCP_SA_KEY` secret set, and all 3 service repos (`shortliner`, `shortliner-analytics`, `shortliner-frontend`) have `CLOUD_INFRA_DISPATCH_TOKEN` set and dispatch to `cloud-infra` on push to `master`.
- A temporary `tofu-bootstrap` GCP service account (Owner role) and key at `~/tofu-bootstrap-key.json` are **still in use** — needed because normal `gcloud auth application-default login` is broken for this account (see gotchas). **Do not delete this until the user confirms they're done with active infra changes** — it's the only way `tofu`/`gcloud` commands in this project currently authenticate.

## Architecture (locked-in decisions — don't re-litigate without new info)

- **GKE Autopilot**, region `europe-central2` (Warsaw) — chosen for latency (user is Poland-based).
- **Cloud SQL Postgres**: `db-f1-micro` (cheapest tier confirmed to work for Postgres), `PD_HDD` (not SSD default), private-IP-only, no backups, `edition = "ENTERPRISE"` set explicitly.
- **Kafka**: self-hosted via Strimzi operator, **single combined controller+broker node** (not homelab's 2-node dual-role pool — cost/simplicity call for a project with no real traffic), KRaft mode, internal-only (no external LoadBalancer). Operator installed manually via Helm, out-of-band (matches homelab convention) — only the `Kafka`/`KafkaNodePool` CRs live in git.
- **Ingress: Cloudflare Tunnel**, not GCP Gateway API/Load Balancer. This was a deliberate reversal — the original Gateway API + Certificate Manager design cost a flat ~$18-20/month regardless of traffic (the single biggest recurring cost in the whole stack). `cloudflared` runs as a Deployment, makes an outbound-only connection to Cloudflare's edge. **No GCP load balancer or public IP exists in this project at all.** TLS terminates at Cloudflare.
- **DNS**: Cloudflare, managed via Terraform (`cloudflare` provider v5), not Google Cloud DNS.
- **Secrets**: Google Secret Manager, synced into real k8s Secrets via GKE's Secret Sync feature (see gotcha below — this needed a manual `gcloud` step, not fully Terraform-managed yet).
- **Spot Pods everywhere**: all app Deployments, `cloudflared`, and the Kafka node pool run on GKE Autopilot Spot Pods for cost savings. Accepted tradeoff even for Kafka's statefulness.
- **No ArgoCD**: GitHub Actions promotion (`repository_dispatch` → `cloud-infra`'s `promote.yml`) patches image tags via `yq` and applies directly with `kubectl`, gated behind a `production` GitHub Environment requiring manual approval.
- **GitHub→GCP auth**: long-lived SA JSON key (`GCP_SA_KEY` secret) — Workload Identity Federation is an explicit, deliberately-deferred future step.
- **Sleep/wake cost control**: `k8s/scripts/sleep.sh`/`wake.sh` scale app Deployments + Kafka node pool to 0 and stop Cloud SQL. No load-balancer floor cost to worry about anymore (Cloudflare Tunnel has none).
- `shortliner-auth` is fully out of scope (disabled in homelab too, not ready).

## Repo layout

```
opentofu/
  bootstrap/        # one-time, local-state, creates the GCS state bucket. Never touch during normal work.
  gke/              # the main stack — see modules/ for network, gke-autopilot, cloudsql, iam, secrets, dns, tunnel
k8s/
  shortliner/       # namespace, KSAs, SecretSync, app Deployments/Services, cloudflared
  kafka/            # Strimzi KafkaNodePool + Kafka CRs (operator itself installed manually, see k8s/kafka/README.md)
  scripts/          # sleep.sh / wake.sh
.github/workflows/promote.yml   # repository_dispatch listener, patches image tag, kubectl applies
```

## Operational gotchas (real issues hit and fixed — don't rediscover these)

1. **ADC login is broken for this GCP account.** `gcloud auth application-default login` (incl. `--no-browser`) repeatedly drops the `cloud-platform`/`sqlservice.login` scopes during consent. Workaround in active use: the `tofu-bootstrap` SA key described above. Always `export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-bootstrap-key.json` before running `tofu` or `gcloud` commands for this project.

2. **`google_service_networking_connection` has flaky provider polling**, not a real auth issue. Fails with a gRPC UNAUTHENTICATED-looking error while *waiting* for the operation (confirmed: the same call via plain `gcloud services vpc-peerings connect` succeeds immediately). Fix when it recurs:
   ```bash
   gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com \
     --ranges=shortliner-psa-range --network=shortliner-vpc --project=shortliner-prod
   tofu import 'module.network.google_service_networking_connection.private_service_access' \
     "projects/shortliner-prod/global/networks/shortliner-vpc:servicenetworking.googleapis.com"
   ```

3. **Cloud SQL now defaults to ENTERPRISE_PLUS edition**, which rejects `db-custom-*`/shared-core tiers. Already fixed in code (`edition = "ENTERPRISE"` in `modules/cloudsql/main.tf`) — just know why it's there if you see it.

4. **Strimzi API version**: the deployed operator only serves `kafka.strimzi.io/v1`, not `v1beta2`, and `storage.volumes[].storageClass` is renamed to `.class` in v1. Already fixed in `k8s/kafka/01-kafka-cluster.yaml`. Always verify Strimzi manifests with `kubectl apply --dry-run=server` before trusting them, especially after any operator upgrade.

5. **"Secret Manager CSI driver" ≠ "Secret Sync"** — two distinct GKE features. `secret_manager_config` in Terraform only enables the CSI driver side. The `SecretSync` CRD (which `k8s/shortliner/02-secretsync.yaml` needs) requires a separate `secret_sync_config` block that only exists in `hashicorp/google` provider **7.x** — we're pinned to `~> 6.0` deliberately (7.0 has real breaking changes not worth forcing mid-deployment). Secret Sync is enabled out-of-band:
   ```bash
   gcloud container clusters update shortliner-cluster --region europe-central2 \
     --project shortliner-prod --enable-secret-sync
   ```
   This is real, deliberate, documented IaC drift — the cluster has a setting Terraform doesn't manage. Revisit when doing a careful 7.x provider upgrade.

6. **GKE Autopilot node boot disks are a fixed 100GiB, non-configurable.** Confirmed via Google docs and empirically (identical disk size across different machine types on this cluster). This is why `SSD_TOTAL_GB` regional quota (default 500GB) gets tight fast — roughly 5 nodes is the practical ceiling no matter how small the workloads are. `gcloud container node-pools list` errors with "Autopilot node pools cannot be accessed or modified" — Autopilot fully abstracts node config away, don't waste time looking for a Terraform/gcloud knob here.

7. **3 of the cluster's 4 nodes typically run nothing but GKE's own mandatory system components** (DNS, networking, monitoring, CSI drivers) — not our app at all. This is fixed platform overhead that doesn't shrink for a small cluster, and these system pods can't share a node with our Spot-tainted pods. Don't be surprised the node count looks high relative to our actual workload size.

8. **Filestore/GCS Fuse/Parallelstore CSI drivers were enabled by default and unused.** Disabled via Terraform (already applied) since nothing in this project uses those volume types — saved ~240Mi memory per node:
   ```hcl
   addons_config {
     gcp_filestore_csi_driver_config { enabled = false }
     gcs_fuse_csi_driver_config      { enabled = false }
     parallelstore_csi_driver_config { enabled = false }
   }
   ```
   (in `modules/gke-autopilot/main.tf`). Don't re-enable without a reason — Google only warns against disabling if you have PVs backed by them, which we don't.

9. **Cloudflare Tunnel's API token permission is mislabeled in the dashboard.** Search "tun" in the token permission UI → only "Argo Tunnel (Legacy)" appears (old product name), and that IS the correct permission (Account-level, needs Edit). "Connectivity Directory" also mentions tunnels but is a different, newer feature — not sufficient on its own.

10. **`SSD_TOTAL_GB` quota increase requests were auto-denied 3x via CLI** (tried 1000GB, 600GB, 550GB — all denied instantly, likely an anti-abuse cap on new/low-spend billing accounts). If more capacity is needed: try the Console UI (`console.cloud.google.com/iam-admin/quotas`, may route to human review) or open a free Google Cloud Support case referencing quota ID `SSD-TOTAL-GB-per-project-region`. **Do not keep retrying the same CLI request** — it won't succeed without a different approval path.

## Known outstanding items

- **`shortliner-analytics` is intentionally at 0 replicas.** One small Spot node cannot fit all 5 workloads (Kafka + 3 services + `cloudflared`) simultaneously even after the CSI-driver memory cleanup — it's genuinely capacity-constrained, not broken. Scale back with `kubectl scale deployment shortliner-analytics -n shortliner --replicas=1` once either (a) the SSD quota increase lands, or (b) the user decides to accept a different tradeoff (e.g. reduce another service's footprint). It's non-critical — fire-and-forget Kafka consumer for click analytics, not on `shortliner`'s core path.
- **SSD quota increase**: last known state — 3 CLI auto-denials, user needs to pursue Console UI or Support case themselves (see gotcha #10). Check current quota before assuming this is still unresolved: `gcloud compute regions describe europe-central2 --project=shortliner-prod --format=json` and look at the `SSD_TOTAL_GB` quota entry.
- **CI dispatch to `cloud-infra`**: this gap is now closed — all 3 service repos dispatch on push to `master`. Don't re-ask about building this.
- **WIF migration** (replacing `GCP_SA_KEY` with Workload Identity Federation): explicitly deferred, not started.
- **`rebuild.sh` pipeline script**: discussed and designed (see Obsidian note) but not built. Three open questions were left for the user before implementing: image tag handling, Makefile vs plain scripts, whether GitHub secrets setup belongs in the same script.
- **Delete `tofu-bootstrap` SA + key** once the user confirms no more active infra work is planned — don't do this preemptively, it'll break the ability to run `tofu`/`gcloud` for this project.

## Common commands

```bash
# Always needed first
export GOOGLE_APPLICATION_CREDENTIALS=~/tofu-bootstrap-key.json
export CLOUDFLARE_API_TOKEN=<token>   # only needed for tofu apply/destroy/plan in gke/

# Apply changes
cd opentofu/gke && tofu init && tofu apply

# kubectl context (already added, but if missing)
gcloud container clusters get-credentials shortliner-cluster --region europe-central2 --project shortliner-prod

# Sleep/wake
./k8s/scripts/sleep.sh
./k8s/scripts/wake.sh

# Destroy & rebuild from scratch
cd opentofu/gke && tofu destroy   # see gotcha #2 if this hangs on service_networking_connection
# then follow the full runbook in the Obsidian note, starting from "Apply the main stack"
```

## Working conventions for this project

- This is a **learning + cost-conscious personal project** — when in doubt, favor the cheaper/simpler option, but always flag the tradeoff rather than silently picking one.
- **Verify against live GCP/kubectl state before assuming anything from past notes is still true** — this file and the Obsidian note are snapshots, not live status. `tofu state list`, `kubectl get pods -A`, and `gcloud` describe commands are authoritative.
- Mirror homelab's conventions (namespace `shortliner`, numbered manifest files, security context patterns) except where Autopilot's constraints genuinely require differing — and flag those differences explicitly rather than silently adjusting.
- Don't re-ask questions already answered in this file or the Obsidian note (e.g. Kafka broker count, ingress choice, DB tier) unless the user explicitly reopens the decision.
- Never fabricate credential values or ask the user to paste real secrets into chat.
