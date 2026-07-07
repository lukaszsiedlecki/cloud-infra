#!/usr/bin/env bash
# Scales all shortliner Deployments and the Kafka node pool to 0 (near-zero
# Autopilot compute cost) and stops the Cloud SQL instance (stops compute
# billing, keeps storage). The Gateway/load balancer is deliberately left
# running: GCP bills its forwarding rule a flat fee regardless of backend
# health, and tearing it down would mean re-issuing the managed TLS cert and
# re-propagating DNS on every wake — not worth the fragility.
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

echo "Asleep. Gateway/load balancer stays up (fixed forwarding-rule cost — see google-cloud-platform/README.md)."
