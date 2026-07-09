#!/usr/bin/env bash
# Scales all shortliner Deployments (including cloudflared) and the Kafka
# node pool to 0, stops the Cloud SQL instance (stops compute billing, keeps
# storage), and resizes the real GKE Standard node pool to 0 nodes — unlike
# Autopilot, Standard mode has real, billable VMs sitting under the cluster,
# so scaling pods to 0 alone doesn't stop that cost. Unlike the old GCP
# Gateway setup, there's no load balancer/forwarding-rule floor cost to
# worry about leaving up — Cloudflare Tunnel has no equivalent standing
# charge, so scaling cloudflared to 0 along with everything else is fine.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-shortliner-prod}"
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE:-shortliner-pg}"
NAMESPACE="${NAMESPACE:-shortliner}"
KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
KAFKA_NODE_POOL="${KAFKA_NODE_POOL:-dual-role}"
GKE_CLUSTER="${GKE_CLUSTER:-shortliner-cluster}"
GKE_ZONE="${GKE_ZONE:-europe-central2-a}"
GKE_NODE_POOL="${GKE_NODE_POOL:-shortliner-primary-pool}"

echo "Scaling all Deployments in namespace ${NAMESPACE} to 0 replicas..."
kubectl -n "${NAMESPACE}" scale deployment --all --replicas=0

echo "Scaling Kafka node pool ${KAFKA_NODE_POOL} in namespace ${KAFKA_NAMESPACE} to 0 replicas..."
kubectl -n "${KAFKA_NAMESPACE}" patch kafkanodepool "${KAFKA_NODE_POOL}" \
  --type merge -p '{"spec":{"replicas":0}}'

echo "Stopping Cloud SQL instance ${CLOUDSQL_INSTANCE}..."
gcloud sql instances patch "${CLOUDSQL_INSTANCE}" \
  --project="${PROJECT_ID}" \
  --activation-policy=NEVER \
  --quiet

echo "Resizing GKE node pool ${GKE_NODE_POOL} to 0 nodes..."
gcloud container clusters resize "${GKE_CLUSTER}" \
  --node-pool="${GKE_NODE_POOL}" \
  --num-nodes=0 \
  --project="${PROJECT_ID}" \
  --zone="${GKE_ZONE}" \
  --quiet

echo "Asleep. Node pool at 0 nodes, cloudflared scaled to 0, Cloud SQL stopped — no fixed cost left running."
