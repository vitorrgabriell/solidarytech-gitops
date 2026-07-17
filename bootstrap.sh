#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="solidarytech"
ARGOCD_NS="argocd"

echo "==> [1/6] Verificando conexão com o cluster..."
kubectl get nodes >/dev/null
echo "    OK"

echo "==> [2/6] Instalando ArgoCD..."
kubectl create namespace ${ARGOCD_NS} --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n ${ARGOCD_NS} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> [3/6] Aguardando ArgoCD ficar pronto..."
kubectl rollout status deployment/argocd-server -n ${ARGOCD_NS} --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n ${ARGOCD_NS} --timeout=300s

echo "==> [4/6] Criando namespace ${NAMESPACE} e aplicando secrets..."
kubectl apply -f "${SCRIPT_DIR}/base/namespace.yaml"

if [[ ! -f "${SCRIPT_DIR}/base/secrets/.env" ]]; then
  echo "ERRO: ${SCRIPT_DIR}/base/secrets/.env não encontrado."
  echo "Copie de .env.example e preencha com os valores reais (terraform output) antes de continuar."
  exit 1
fi

bash "${SCRIPT_DIR}/base/secrets/apply-secrets.sh"

echo "==> [5/6] Aplicando ArgoCD Applications..."
kubectl apply -f "${SCRIPT_DIR}/argocd/applications.yaml"

echo "==> [6/6] Bootstrap completo!"
echo ""
echo "Pra ver a senha inicial do admin ArgoCD:"
echo "  kubectl -n ${ARGOCD_NS} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Pra acessar a UI:"
echo "  kubectl port-forward svc/argocd-server -n ${ARGOCD_NS} 8080:443"
echo "  URL: https://localhost:8080 (usuário: admin)"
echo ""
echo "Acompanhe os pods subindo com: kubectl get pods -n ${NAMESPACE} -w"
