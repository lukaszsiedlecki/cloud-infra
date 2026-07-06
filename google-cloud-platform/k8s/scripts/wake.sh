#!/usr/bin/env bash
# Reverses sleep.sh: restarts Cloud SQL and waits for it to be RUNNABLE
# before scaling Deployments back up, so apps don't crash-loop against a
# not-yet-available database.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-shortliner-prod}"
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE:-shortliner-pg}"
NAMESPACE="${NAMESPACE:-shortliner}"
REPLICAS="${REPLICAS:-1}"

echo "Starting Cloud SQL instance ${CLOUDSQL_INSTANCE}..."
gcloud sql instances patch "${CLOUDSQL_INSTANCE}" \
  --project="${PROJECT_ID}" \
  --activation-policy=ALWAYS \
  --quiet

echo "Waiting for ${CLOUDSQL_INSTANCE} to become RUNNABLE..."
until [ "$(gcloud sql instances describe "${CLOUDSQL_INSTANCE}" --project="${PROJECT_ID}" --format='value(state)')" = "RUNNABLE" ]; do
  sleep 5
done

echo "Scaling all Deployments in namespace ${NAMESPACE} to ${REPLICAS} replica(s)..."
kubectl -n "${NAMESPACE}" scale deployment --all --replicas="${REPLICAS}"

echo "Awake. Waiting for pods to become Ready..."
kubectl -n "${NAMESPACE}" wait --for=condition=Available deployment --all --timeout=300s
