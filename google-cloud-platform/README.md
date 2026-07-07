# google-cloud-platform

Production infrastructure for `shortliner` in GCP, provisioned with OpenTofu.
Runs alongside a homelab (Talos + ArgoCD) dev/UAT deployment of the same app,
which is untouched by anything here. Cost-optimized throughout for a
low-traffic personal project — see the "Cost" section below for what that
means concretely.

## Layout

- `opentofu/bootstrap/` — one-time, local-state config that creates the GCS
  bucket used as the state backend for everything else. Run this exactly
  once, before `opentofu/gke/`. See its own README.
- `opentofu/gke/` — the main stack: VPC + Private Service Access, GKE
  Autopilot cluster, Cloud SQL (private IP, no backups, cheapest tier), Secret
  Manager secrets + Workload Identity bindings, the GitHub Actions deployer
  service account, a Cloudflare Tunnel, and the matching proxied Cloudflare
  DNS record (see `opentofu/gke/modules/tunnel` and `modules/dns`).
- `k8s/shortliner/` — plain Kubernetes manifests (namespace, service
  accounts, SecretSync, Deployments/Services, the `cloudflared` Deployment)
  applied directly by the promotion workflow — no ArgoCD. All Deployments run
  on Spot Pods for cost savings.
- `k8s/kafka/` — self-hosted Kafka via the Strimzi operator (KRaft mode,
  single combined controller+broker node, internal-only, also on Spot Pods).
  Not managed by the promotion workflow — applied the same way as homelab's
  Kafka: manually. See its own README for the one-time operator install.
- `k8s/scripts/sleep.sh` / `wake.sh` — cost control: scale everything down
  (app Deployments + the Kafka node pool) / back up between usage sessions.
- `.github/workflows/promote.yml` — promotion job, triggered by
  `repository_dispatch` from each service's CI, gated behind a `production`
  GitHub Environment requiring manual reviewer approval.

## First-time setup order

1. Create the `shortliner-prod` GCP project and link a billing account
   (manual, via console/gcloud — not managed by OpenTofu).
2. `cd opentofu/bootstrap && tofu init && tofu apply` — creates the state bucket.
3. Create a Cloudflare API token scoped to the `lukaszsiedlecki.com` zone with
   **DNS:Edit**, **Zone:Read**, and **Account > Cloudflare Tunnel:Edit**
   permissions, then `export CLOUDFLARE_API_TOKEN=...`. The tunnel permission
   is easy to miss — it's an Account-level permission, not a Zone-level one,
   listed separately in the token creation UI. Never commit the token or put
   it in a `.tf` file.
4. `cd opentofu/gke && tofu init && tofu apply` — provisions everything,
   including the Cloudflare Tunnel and the proxied DNS record for
   `shortliner.lukaszsiedlecki.com`. No manual DNS step needed.
5. Fill in the `REPLACE_WITH_CLOUDSQL_PRIVATE_IP` placeholders in
   `k8s/shortliner/03-deployment-*.yaml` with `tofu output -raw cloudsql_private_ip_address`.
6. In the GitHub repo settings: create a `production` Environment with
   required reviewers, and add its `GCP_SA_KEY` secret from
   `tofu output -raw github_deployer_key_json_base64 | base64 -d`.
7. Install the Strimzi operator and apply the Kafka cluster (see
   `k8s/kafka/README.md`) — do this before the app Deployments if you want
   them to connect on first boot, though it isn't strictly required since
   the Kafka client usage is fire-and-forget/best-effort.
8. Apply the k8s manifests once manually (`kubectl apply -f k8s/shortliner/`)
   to bootstrap the namespace/cluster objects, then let the promotion
   workflow take over for subsequent image updates. This also brings up
   `cloudflared`, which is what actually makes the site reachable — nothing
   in `opentofu/gke` creates a public IP or load balancer anymore.

## Day-to-day: sleeping the environment

```bash
./k8s/scripts/sleep.sh   # scale workloads + Kafka to 0, stop Cloud SQL
./k8s/scripts/wake.sh    # start Cloud SQL + Kafka, scale workloads back up
```

## Cost

Reviewed end-to-end for a low-traffic personal project, checking live GCP
state rather than assuming from docs:

- **GKE Autopilot cluster management fee**: $0 — Google waives $74.40/month
  per billing account for one Autopilot cluster, and this is the only one.
- **Compute**: Spot Pods everywhere (app Deployments, `cloudflared`, Kafka).
- **Public ingress**: **$0** — Cloudflare Tunnel replaced the GCP Gateway
  API + Certificate Manager setup that used to cost a flat ~$18-20/month
  (a GCLB forwarding rule bills that regardless of traffic or backend
  health). `cloudflared` makes an outbound-only connection to Cloudflare's
  edge instead; no GCP load balancer or public IP exists at all now. TLS
  terminates at Cloudflare, not at a Google-managed cert.
- **Cloud SQL**: `db-f1-micro` (cheapest tier that supports Postgres,
  confirmed against the live project), `PD_HDD` storage (not the pricier SSD
  default), no backups, private IP only.
- **Kafka**: single broker (not homelab's 2-node dual-role pool) — halves
  the compute/disk footprint, at the cost of no redundancy. Internal-only,
  no LoadBalancer Service.
- **Secret Manager / Certificate Manager**: unused now (no more managed
  cert) / well within the always-free tier either way.
- **DNS**: Cloudflare, not Google Cloud DNS — no per-zone or per-query cost.

Net effect: while awake, cost is dominated by whatever Cloud SQL + the single
Kafka broker + app pods actually use (all on Spot pricing); while asleep,
it's close to just the small Persistent Disk storage costs (Cloud SQL +
Kafka, a few $/month combined) — no fixed load-balancer floor cost remains.

## Known gaps / explicit non-goals (for now)

- GitHub → GCP auth uses a long-lived SA JSON key, not Workload Identity
  Federation — migrate later.
- Everything runs on Spot Pods, including the Kafka broker — accepted
  tradeoff for cost; expect occasional brief restarts on preemption (25s
  notice).
- Kafka has no redundancy (single broker) — a restart means brief
  unavailability for the whole thing, not just reduced capacity.
- `shortliner-auth` is out of scope entirely.
