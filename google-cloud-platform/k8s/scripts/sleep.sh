#!/usr/bin/env bash
# Scales all shortliner Deployments to 0 (near-zero Autopilot compute cost)
# and stops the Cloud SQL instance (stops compute billing, keeps storage).
# The Gateway/load balancer is deliberately left running — see the plan doc
# for why (fixed forwarding-rule cost either way, tearing it down risks a
# slow/fragile wake with cert re-issuance).
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-shortliner-prod}"
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE:-shortliner-pg}"
NAMESPACE="${NAMESPACE:-shortliner}"

echo "Scaling all Deployments in namespace ${NAMESPACE} to 0 replicas..."
kubectl -n "${NAMESPACE}" scale deployment --all --replicas=0

echo "Stopping Cloud SQL instance ${CLOUDSQL_INSTANCE}..."
gcloud sql instances patch "${CLOUDSQL_INSTANCE}" \
  --project="${PROJECT_ID}" \
  --activation-policy=NEVER \
  --quiet

echo "Asleep. Gateway/load balancer stays up (~\$18-20/month fixed cost, see plan doc)."
