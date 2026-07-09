#!/usr/bin/env bash
# Reverses sleep.sh: resizes the real GKE Standard node pool back up first
# (nothing can schedule without nodes), then restarts Cloud SQL and the
# Kafka node pool and waits for both to be ready before scaling app
# Deployments back up, so apps don't crash-loop against a not-yet-available
# database or broker.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-shortliner-prod}"
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE:-shortliner-pg}"
NAMESPACE="${NAMESPACE:-shortliner}"
REPLICAS="${REPLICAS:-1}"
KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
KAFKA_NODE_POOL="${KAFKA_NODE_POOL:-dual-role}"
KAFKA_REPLICAS="${KAFKA_REPLICAS:-1}"
GKE_CLUSTER="${GKE_CLUSTER:-shortliner-cluster}"
GKE_ZONE="${GKE_ZONE:-europe-central2-a}"
GKE_NODE_POOL="${GKE_NODE_POOL:-shortliner-primary-pool}"
GKE_NODE_COUNT="${GKE_NODE_COUNT:-1}"

echo "Resizing GKE node pool ${GKE_NODE_POOL} to ${GKE_NODE_COUNT} node(s)..."
gcloud container clusters resize "${GKE_CLUSTER}" \
  --node-pool="${GKE_NODE_POOL}" \
  --num-nodes="${GKE_NODE_COUNT}" \
  --project="${PROJECT_ID}" \
  --zone="${GKE_ZONE}" \
  --quiet

echo "Waiting for node(s) to become Ready..."
kubectl wait --for=condition=Ready node \
  -l cloud.google.com/gke-nodepool="${GKE_NODE_POOL}" --timeout=300s

echo "Starting Cloud SQL instance ${CLOUDSQL_INSTANCE}..."
# --async: gcloud's own synchronous wait for this op has hit its client-side
# threshold live (~10min) while the real op took ~13min — confirmed via
# `gcloud beta sql operations wait` that it had actually succeeded server-side
# (see CLAUDE.md gotcha #7). Returning immediately and letting the RUNNABLE
# poll loop below own the wait avoids that ceiling entirely instead of just
# picking a bigger number.
gcloud sql instances patch "${CLOUDSQL_INSTANCE}" \
  --project="${PROJECT_ID}" \
  --activation-policy=ALWAYS \
  --async \
  --quiet

echo "Scaling Kafka node pool ${KAFKA_NODE_POOL} in namespace ${KAFKA_NAMESPACE} to ${KAFKA_REPLICAS} replica(s)..."
kubectl -n "${KAFKA_NAMESPACE}" patch kafkanodepool "${KAFKA_NODE_POOL}" \
  --type merge -p "{\"spec\":{\"replicas\":${KAFKA_REPLICAS}}}"

echo "Waiting for ${CLOUDSQL_INSTANCE} to become RUNNABLE..."
until [ "$(gcloud sql instances describe "${CLOUDSQL_INSTANCE}" --project="${PROJECT_ID}" --format='value(state)')" = "RUNNABLE" ]; do
  sleep 5
done

echo "Waiting for Kafka pods to become Ready (quorum re-forming can take several minutes)..."
# 600s, not 300s: confirmed live that entity-operator can cycle through
# liveness-probe failures (connection refused / 500s) against the
# not-yet-ready broker for 5+ minutes before settling — 300s cut it off
# mid-retry even though it was already self-healing.
kubectl -n "${KAFKA_NAMESPACE}" wait --for=condition=Ready pod \
  -l strimzi.io/cluster=my-cluster --timeout=600s

echo "Scaling all Deployments in namespace ${NAMESPACE} to ${REPLICAS} replica(s)..."
kubectl -n "${NAMESPACE}" scale deployment --all --replicas="${REPLICAS}"

echo "Awake. Waiting for pods to become Ready..."
kubectl -n "${NAMESPACE}" wait --for=condition=Available deployment --all --timeout=300s
