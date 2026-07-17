# Observabilidade — SolidaryTech

Mesma arquitetura usada na Fase 4 (`togglemaster-gitops/monitoring`): OTel
Collector como hub central de telemetria, kube-prometheus-stack para
métricas, loki-stack (Loki + Promtail) para logs. Diferente do togglemaster,
aqui o APM conectado é o **Datadog** (exporter nativo no Collector).

```
┌─────────────┐  ┌──────────────────┐  ┌───────────────────┐
│ ngo-service │  │ donation-service │  │ volunteer-service  │
│  (Python,   │  │  (Go, hot path,  │  │  + consumer.py     │
│   auto-     │  │   spans manuais  │  │  (Python, auto-    │
│   instrum.) │  │   no insert)     │  │   instrum.)        │
└──────┬──────┘  └────────┬─────────┘  └─────────┬──────────┘
       │  OTLP (traces+metrics+logs)              │
       └───────────────┬───────────────────────────┘
                        ▼
              ┌───────────────────┐
              │  OTel Collector   │  processors: memory_limiter, batch, resource
              │  (hub central)    │
              └─────┬──────┬──────┘
                    │      │
        ┌───────────┘      └────────────┐
        ▼                               ▼
┌───────────────┐              ┌─────────────────┐        ┌─────────┐
│ Prometheus     │◄─scrape────  │ (exporter        │        │ Datadog │
│ (kube-         │   ServiceMon │  prometheus)     │        │ (traces,│
│  prometheus-   │              └─────────────────┘        │  metrics│
│  stack)        │                                          │  logs)  │
└───────┬───────┘                                          └─────────┘
        │
        ▼
   Grafana (dashboards + datasource Loki)
        ▲
        │
┌───────┴────────┐        ┌──────────────┐
│ Loki           │◄───────│ Promtail      │ (DaemonSet, lê stdout dos pods
│                │  push  │ (1 por node)  │  direto — não passa pelo Collector)
└────────────────┘        └──────────────┘
```

Logs vão por dois caminhos independentes: Promtail lê o stdout dos
containers direto (não depende de instrumentação nenhuma nos serviços) e
qualquer log OTLP que os apps emitirem via o SDK também passa pelo
Collector. Isso é intencional — é a mesma separação da Fase 4, e significa
que os logs aparecem no Grafana/Loki mesmo que a instrumentação OTel de um
serviço falhe ao iniciar.

## Como o trace atravessa os 3 serviços

`POST /donations` no `donation-service` gera **um trace só** que passa
pelos 3 serviços:

1. `otelhttp.NewHandler` cria o span raiz da requisição HTTP recebida.
2. `donation-service` chama `GET /ngos/{id}` no `ngo-service` (valida o
   `ngo_id` antes de aceitar a doação) usando um `http.Client` com
   `otelhttp.NewTransport` — isso injeta o header `traceparent` na
   chamada, e o `ngo-service` (auto-instrumentado via
   `opentelemetry-instrumentation-flask`) continua o mesmo trace.
3. Um span manual (`db.insert_donation`) marca o tempo gasto no insert no
   Postgres — é o hot path, então vale um span dedicado além do span HTTP
   automático.
4. Ao publicar o evento no SQS, o `donation-service` injeta o trace context
   como *message attributes* (não existe propagação HTTP nesse hop) via
   `otel.GetTextMapPropagator().Inject(...)`.
5. O `volunteer-consumer` (novo processo, mesma imagem do
   `volunteer-service`, `command` diferente — ver
   [`../apps/volunteer-service/deployment-consumer.yaml`](../apps/volunteer-service/deployment-consumer.yaml))
   consome a mensagem, extrai o `traceparent` dos message attributes com
   `opentelemetry.propagate.extract(...)` e abre o span
   `process_donation_event` como filho do mesmo trace.

Resultado: um trace com spans de `donation-service` (HTTP + DB + SQS
publish), `ngo-service` (validação) e `volunteer-service`
(`process_donation_event`) — os 3 microsserviços na mesma requisição de
doação, visível no Datadog APM (produção) ou no Jaeger (local, ver
`hackathon-DCLT/docker-compose.yml`).

## Nota de capacidade — cluster "leaner lab"

O EKS provisionado em `hackathon-DCLT/infra` é 2x `t3.medium` (2 vCPU/4GiB
cada, ~3.2 vCPU / ~6.5GiB alocáveis no total depois do overhead do
`kube-system`). Requests aproximados depois de instalar tudo:

| Componente | CPU (request) | Memória (request) |
|---|---|---|
| 3 microsserviços (min réplicas) | ~600m | ~640Mi |
| otel-collector | 100m | 256Mi |
| kube-prometheus-stack (prometheus+grafana+alertmanager+operator) | ~350m | ~640Mi |
| loki-stack (loki + promtail x2 nodes) | ~200m | ~380Mi |
| kube-state-metrics + node-exporter (DaemonSet) | ~100m | ~150Mi |
| **Total (baseline)** | **~1.35 vCPU** | **~2.1GiB** |

Isso cabe nos ~3.2 vCPU/6.5GiB alocáveis com folga confortável no baseline,
mas o HPA pode escalar os 3 serviços até 4-6 réplicas cada sob carga
(`donation-service` em particular, hot path, vai até 6) — nesse pico,
CPU/memória requisitada sobe mais uns ~600-900m/~1GiB. **Se os pods
começarem a ficar `Pending` sob carga**, o ajuste é aumentar
`eks_node_desired`/`eks_node_instance_type` em
`hackathon-DCLT/infra/variables.tf`, não cortar a stack de observabilidade
— ela já está no osso (retenção de 3d no Prometheus, sem persistência no
Loki/Grafana, 1 réplica de cada).

## Instalando

A stack de monitoring **não** faz parte do `bootstrap.sh` principal (mesma
decisão do `togglemaster-gitops`) — é um passo separado, depois que o
ArgoCD e os 3 serviços já estiverem no ar:

```bash
# 1. Namespace
kubectl apply -f monitoring/namespace.yaml

# 2. Secret do Datadog (precisa do namespace acima já existir)
cd base/secrets
cp .env.example .env   # se ainda não tiver feito
# preencha DATADOG_API_KEY no .env
bash apply-secrets.sh
cd ../..

# 3. Applications do ArgoCD (cada uma sincroniza um Helm chart)
kubectl apply -f monitoring/otel-collector.yaml
kubectl apply -f monitoring/kube-prometheus-stack.yaml
kubectl apply -f monitoring/loki-stack.yaml
kubectl apply -f monitoring/dashboards-app.yaml
```

O ArgoCD assume a partir daí (`syncPolicy.automated`) — qualquer mudança
futura nos values desses `Application` é só commitar e dar push.

## Acessando o Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# usuário: admin / senha: admin (troque depois do primeiro login —
# ver grafana.adminPassword em kube-prometheus-stack.yaml)
```

Datasources Prometheus e Loki já vêm configurados automaticamente (sidecar
do Helm chart + `dashboards/loki-datasource.yaml`).
