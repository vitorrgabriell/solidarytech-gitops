#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/5] Criando namespace argocd..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> [2/5] Instalando ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> [3/5] Aguardando pods do ArgoCD ficarem prontos..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

echo "==> [4/5] Aplicando ArgoCD Applications..."
kubectl apply -f "${SCRIPT_DIR}/applications.yaml"

echo "==> [5/5] Senha inicial do admin (troque depois do primeiro login):"
echo "    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "  URL:      https://localhost:8080"
echo "  Usuário:  admin"
echo ""

echo "==> Iniciando port-forward para argocd-server (Ctrl+C para encerrar)..."
kubectl port-forward svc/argocd-server -n argocd 8080:443
