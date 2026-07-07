# Kafka (Strimzi)

Self-hosted Kafka via the Strimzi operator (KRaft mode, no ZooKeeper), based
on the homelab pattern but running a single combined controller+broker node
instead of homelab's 2-node dual-role pool — a pet project with no real
traffic doesn't justify doubling the footprint for quorum resilience, matching
every other cost-over-resilience call made in this environment (no backups,
no HA, spot everywhere). Chosen over Google Managed Service for Apache Kafka
because the managed service can't be paused (only deleted), and self-hosting
on GKE Autopilot lets Kafka sleep/wake along with everything else — see
`../scripts/sleep.sh` / `wake.sh`.

## One-time operator install (not tracked by the promotion workflow)

Same as homelab: the operator itself is installed manually, out-of-band, via
Helm — only the `Kafka`/`KafkaNodePool` custom resources in this directory
are tracked in git and applied like everything else.

```bash
helm repo add strimzi https://strimzi.io/charts/
helm repo update
kubectl create ns kafka
helm install strimzi-operator strimzi/strimzi-kafka-operator -n kafka
```

Then apply the cluster definition:

```bash
kubectl apply -f k8s/kafka/01-kafka-cluster.yaml
```

## Notes

- **Internal only** — no external listener/LoadBalancer. Nothing outside the
  cluster needs to reach Kafka, and a LoadBalancer Service would add its own
  standing forwarding-rule cost. Consumers/producers use
  `my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092`, same hostname
  shape as homelab.
- **Single broker, replication factor 1** — no redundancy; a broker restart
  (spot preemption or a node pool scale-to-0 sleep) means brief unavailability
  for the whole cluster, not just a blip. Acceptable for a low-traffic
  personal project; bump `replicas` back up and the replication factor
  configs in `01-kafka-cluster.yaml` together if that ever changes.
- **Storage**: `standard-rwo` (balanced Persistent Disk, Autopilot's
  default/cheapest option) — `premium-rwo` (SSD) would cost more with no
  real benefit at this traffic level. 10Gi, matching homelab's per-broker
  size. The disk keeps costing money even while sleep.sh has scaled the node
  pool to 0 — small (roughly $1/month for 10Gi standard-rwo), but not zero.
- **Spot**: the broker runs on a Spot Pod like everything else in this
  cluster — accepted tradeoff (brief restarts on the ~25s preemption notice)
  for the cost savings.
- Scaling the node pool to 0 (via sleep.sh) stops the broker/controller
  entirely — on wake, Strimzi reprovisions the pod against the same PVC.
  Works reliably in practice, but is a slower path than a normal restart.
