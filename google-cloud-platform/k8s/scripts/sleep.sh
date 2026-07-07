#!/usr/bin/env bash
# Scales all shortliner Deployments (including cloudflared) and the Kafka
# node pool to 0 (near-zero Autopilot compute cost) and stops the Cloud SQL
# instance (stops compute billing, keeps storage). Unlike the old GCP
# Gateway setup, there's no load balancer/forwarding-rule floor cost to
# worry about leaving up — Cloudflare Tunnel has no equivalent standing
# charge, so scaling cloudflared to 0 along with everything else is fine.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-shortliner-prod}"
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE:-shortliner-pg}"
NAMESPACE="${NAMESPACE:-shortliner}"
KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
KAFKA_NODE_POOL="${KAFKA_NODE_POOL:-dual-role}"

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

echo "Asleep. cloudflared is also scaled to 0, so the site is unreachable until wake.sh runs — no fixed cost was left running either way."
