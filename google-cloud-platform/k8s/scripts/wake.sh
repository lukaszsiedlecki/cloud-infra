#!/usr/bin/env bash
# Reverses sleep.sh: restarts Cloud SQL and the Kafka node pool and waits for
# both to be ready before scaling app Deployments back up, so apps don't
# crash-loop against a not-yet-available database or broker.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-shortliner-prod}"
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE:-shortliner-pg}"
NAMESPACE="${NAMESPACE:-shortliner}"
REPLICAS="${REPLICAS:-1}"
KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
KAFKA_NODE_POOL="${KAFKA_NODE_POOL:-dual-role}"
KAFKA_REPLICAS="${KAFKA_REPLICAS:-1}"

echo "Starting Cloud SQL instance ${CLOUDSQL_INSTANCE}..."
gcloud sql instances patch "${CLOUDSQL_INSTANCE}" \
  --project="${PROJECT_ID}" \
  --activation-policy=ALWAYS \
  --quiet

echo "Scaling Kafka node pool ${KAFKA_NODE_POOL} in namespace ${KAFKA_NAMESPACE} to ${KAFKA_REPLICAS} replica(s)..."
kubectl -n "${KAFKA_NAMESPACE}" patch kafkanodepool "${KAFKA_NODE_POOL}" \
  --type merge -p "{\"spec\":{\"replicas\":${KAFKA_REPLICAS}}}"

echo "Waiting for ${CLOUDSQL_INSTANCE} to become RUNNABLE..."
until [ "$(gcloud sql instances describe "${CLOUDSQL_INSTANCE}" --project="${PROJECT_ID}" --format='value(state)')" = "RUNNABLE" ]; do
  sleep 5
done

echo "Waiting for Kafka pods to become Ready (quorum re-forming can take a minute)..."
kubectl -n "${KAFKA_NAMESPACE}" wait --for=condition=Ready pod \
  -l strimzi.io/cluster=my-cluster --timeout=300s

echo "Scaling all Deployments in namespace ${NAMESPACE} to ${REPLICAS} replica(s)..."
kubectl -n "${NAMESPACE}" scale deployment --all --replicas="${REPLICAS}"

echo "Awake. Waiting for pods to become Ready..."
kubectl -n "${NAMESPACE}" wait --for=condition=Available deployment --all --timeout=300s
