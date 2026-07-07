# Kafka (Strimzi)

Self-hosted Kafka via the Strimzi operator, mirroring the homelab pattern
(KRaft mode, no ZooKeeper, dual-role node pool). Chosen over Google Managed
Service for Apache Kafka because the managed service can't be paused (only
deleted), and self-hosting on GKE Autopilot lets Kafka sleep/wake along with
everything else — see `../scripts/sleep.sh` / `wake.sh`.

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
  cluster needs to reach Kafka, and a LoadBalancer Service would add another
  standing forwarding-rule cost on top of the Gateway's. Consumers/producers
  use `my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092`, same
  hostname shape as homelab.
- **Storage**: `standard-rwo` (balanced Persistent Disk, Autopilot's
  default/cheapest option) — `premium-rwo` (SSD) would cost more with no
  real benefit at this traffic level. 10Gi per broker, matching homelab.
  Note the disks keep costing money even while sleep.sh has scaled the node
  pool to 0 — small (a few $/month for 2x10Gi standard-rwo), but not zero.
- **Spot**: brokers run on Spot Pods like everything else in this cluster —
  accepted tradeoff (brief broker blips on the ~25s preemption notice) for
  the cost savings, per an explicit decision to prioritize cost over HA
  throughout this environment.
- Scaling the node pool to 0 (via sleep.sh) stops the whole cluster,
  including the KRaft controller role — on wake, Strimzi reprovisions pods
  against the same PVCs and re-forms the quorum. Works reliably in practice,
  but is a slower/less battle-tested path than a normal broker restart.
