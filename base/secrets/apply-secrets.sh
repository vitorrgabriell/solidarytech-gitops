#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
NAMESPACE="solidarytech"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Erro: arquivo .env não encontrado em $SCRIPT_DIR"
  echo "Crie-o a partir do template: cp .env.example .env"
  exit 1
fi

set -o allexport
source <(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$')
set +o allexport

echo "Aplicando secrets no namespace '$NAMESPACE'..."

kubectl create secret generic ngo-service-secret \
  --namespace="$NAMESPACE" \
  --from-literal=DATABASE_URL="postgres://app:${NGO_DB_PASSWORD}@${NGO_RDS_ENDPOINT}/ngo_db" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic donation-service-secret \
  --namespace="$NAMESPACE" \
  --from-literal=DATABASE_URL="postgres://app:${DONATION_DB_PASSWORD}@${DONATION_RDS_ENDPOINT}/donation_db" \
  --from-literal=AWS_SQS_URL="${AWS_SQS_URL}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets aplicados com sucesso!"
echo "(volunteer-service não tem Secret — ver .env.example para o motivo)"

echo "Aplicando secret do Datadog no namespace 'monitoring'..."
kubectl create secret generic datadog-api-key \
  --namespace="monitoring" \
  --from-literal=api-key="${DATADOG_API_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret do Datadog aplicado!"
