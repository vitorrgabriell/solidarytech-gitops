# Secrets

Gerenciamento de secrets do cluster para o namespace `solidarytech`.

Os secrets **não são gerenciados pelo ArgoCD** — são aplicados manualmente
(ou via CI/CD), pois os valores reais ficam fora do repositório. O ArgoCD só
sincroniza `base/namespace.yaml` porque a Application `solidarytech-base`
aponta para o path `base/` sem recursão — `base/secrets/` fica de fora do
sync por construção, não por config explícita.

## Secrets disponíveis

| Nome | Namespace | Chaves | Usado por |
|------|-----------|--------|-----------|
| `ngo-service-secret` | `solidarytech` | `DATABASE_URL` | ngo-service |
| `donation-service-secret` | `solidarytech` | `DATABASE_URL`, `AWS_SQS_URL` | donation-service |
| `datadog-api-key` | `monitoring` | `api-key` | otel-collector (exporter Datadog) |

O secret `datadog-api-key` só pode ser aplicado depois que o namespace
`monitoring` existir (via `monitoring/namespace.yaml` — ver
[`../../monitoring/README.md`](../../monitoring/README.md)); diferente do
namespace `solidarytech`, este script não cria o `monitoring` sozinho.

`volunteer-service` **não tem Secret**. Não há senha de banco (usa DynamoDB)
nem credencial AWS estática — no AWS Academy, os pods herdam a `LabRole` do
node via IMDS (ver [k8s/README.md do repo
hackathon-DCLT](https://github.com/vitorrgabriell/hackathon-DCLT/blob/main/k8s/README.md)
para a nota de segurança completa sobre isso). Esse é o motivo pelo qual
este repo, diferente do `togglemaster-gitops`, não guarda
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` em Secret
nenhum.

## Como aplicar

```bash
cd base/secrets

# 1. Crie o .env a partir do template
cp .env.example .env

# 2. Preencha os valores reais no .env (vêm do `terraform output` do
#    repo hackathon-DCLT/infra)

# 3. Aplique no cluster
bash apply-secrets.sh
```

O script é idempotente — pode ser executado múltiplas vezes para atualizar
os secrets (por exemplo, depois de trocar a senha do RDS).

## Arquivos

| Arquivo | Commitado | Descrição |
|---------|-----------|-----------|
| `.env.example` | Sim | Template com todos os placeholders |
| `.env` | **Não** | Valores reais — gitignored |
| `apply-secrets.sh` | Sim | Script que lê o `.env` e aplica os secrets via `kubectl` |
