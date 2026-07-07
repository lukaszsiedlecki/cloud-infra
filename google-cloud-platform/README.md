# google-cloud-platform

Production infrastructure for `shortliner` in GCP, provisioned with OpenTofu.
Runs alongside a homelab (Talos + ArgoCD) dev/UAT deployment of the same app,
which is untouched by anything here.

## Layout

- `opentofu/bootstrap/` — one-time, local-state config that creates the GCS
  bucket used as the state backend for everything else. Run this exactly
  once, before `opentofu/gke/`. See its own README.
- `opentofu/gke/` — the main stack: VPC + Private Service Access, GKE
  Autopilot cluster, Cloud SQL (private IP, no backups), Secret Manager
  secrets + Workload Identity bindings, the GitHub Actions deployer service
  account, the Gateway API static IP + Certificate Manager cert, and the
  matching Cloudflare DNS records (both DNS-only/not proxied — see
  `opentofu/gke/modules/dns`).
- `k8s/shortliner/` — plain Kubernetes manifests (namespace, service
  accounts, SecretSync, Deployments/Services, Gateway/HTTPRoute) applied
  directly by the promotion workflow — no ArgoCD. All 3 app Deployments run
  on Spot Pods for cost savings.
- `k8s/kafka/` — self-hosted Kafka via the Strimzi operator (KRaft mode,
  dual-role node pool, internal-only, also on Spot Pods). Not managed by the
  promotion workflow — applied the same way as homelab's Kafka: manually.
  See its own README for the one-time operator install.
- `k8s/scripts/sleep.sh` / `wake.sh` — cost control: scale everything down
  (app Deployments + the Kafka node pool) / back up between usage sessions.
- `.github/workflows/promote.yml` — promotion job, triggered by
  `repository_dispatch` from each service's CI, gated behind a `production`
  GitHub Environment requiring manual reviewer approval.

## First-time setup order

1. Create the `shortliner-prod` GCP project and link a billing account
   (manual, via console/gcloud — not managed by OpenTofu).
2. `cd opentofu/bootstrap && tofu init && tofu apply` — creates the state bucket.
3. Create a Cloudflare API token (DNS edit permission, scoped to the
   `lukaszsiedlecki.com` zone) and `export CLOUDFLARE_API_TOKEN=...` —
   `opentofu/gke` manages the domain's DNS records directly and needs this to
   authenticate. Never commit the token or put it in a `.tf` file.
4. `cd opentofu/gke && tofu init && tofu apply` — provisions everything,
   including the DNS records needed for the managed cert to validate and for
   `shortliner.lukaszsiedlecki.com` to resolve. No manual DNS step needed.
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
   workflow take over for subsequent image updates.

## Day-to-day: sleeping the environment

```bash
./k8s/scripts/sleep.sh   # scale workloads + Kafka to 0, stop Cloud SQL
./k8s/scripts/wake.sh    # start Cloud SQL + Kafka, scale workloads back up
```

The Gateway/load balancer is intentionally left running at all times — GCP
bills its forwarding rule a flat ~$18-20/month regardless of backend health,
and tearing it down would mean re-issuing the managed TLS cert and
re-propagating DNS on every wake, which isn't worth the fragility for the
amount it would save.

## Known gaps / explicit non-goals (for now)

- GitHub → GCP auth uses a long-lived SA JSON key, not Workload Identity
  Federation — migrate later.
- Everything runs on Spot Pods, including Kafka brokers — accepted tradeoff
  for cost; expect occasional brief restarts on preemption (25s notice).
- `shortliner-auth` is out of scope entirely.
