# Serviços no EKS (Fase 4 — Parte 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rodar users, catalog (+worker) e payments (+worker) no cluster `fcg-eks` atrás de um ALB, aposentar o ECS e tirar o JWT do código.

**Architecture:** Manifests YAML + Kustomize centralizados em `fcg-orchestration/k8s/eks/`, aplicados pelo `eks-up.sh` depois do Terraform do cluster. Workers rodam como segundo container no pod da API, compartilhando o SQLite num `emptyDir`. Nos 3 repos de serviço: ECS/API Gateway removidos do Terraform (ECR fica), workflow antigo desarmado, `Jwt:Key` fora do `appsettings.json`.

**Tech Stack:** Kubernetes 1.36 (EKS), Kustomize (embutido no kubectl), AWS Load Balancer Controller 3.6 (Ingress ALB), Terraform ≥ 1.5, Docker (buildx), bash (Git Bash no Windows), .NET 10.

**Spec:** `docs/superpowers/specs/2026-10-06-eks-services-design.md`
**Parte 1 (já pronta):** `docs/superpowers/specs/2026-10-06-eks-cluster-design.md` — cluster, ServiceAccounts `users-api`/`catalog-api`/`payments-api` (Pod Identity) e Secret `fcg-jwt` (key `jwt-key`) no namespace `fcgames`.

---

## Convenções para quem executa

- Workspace: `C:\GIT\FIAP\FIAP-POS-TECH-TEAM-10` com repos irmãos: `fcg-orchestration`, `fcg-users-api`, `fcg-catalog-api`, `fcg-payments-api`.
- `fcg-orchestration`: continuar na branch `feature/eks-cluster` (sem upstream). **Não** commitar `fcgames.aws.http` (alteração pré-existente de outra pessoa).
- Repos de serviço: branch nova `feature/eks-migration` criada a partir de `origin/main` (não da branch local atual). Arquivos `*.db*` não rastreados no payments: ignorar, nunca commitar.
- AWS: `export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1` (conta `915153720516`). No Git Bash o AWS CLI devolve `\r\n` — usar `| tr -d '\r'` ao capturar saída.
- **Nunca dar push** sem o usuário pedir. **Pedir confirmação ao usuário** antes das tasks marcadas com ⚠️ (destroem infra ou geram custo).
- `NUGET_AUTH_TOKEN` (PAT `read:packages`) já está no ambiente — nunca imprimir o valor.
- ECR: `915153720516.dkr.ecr.sa-east-1.amazonaws.com/{fcg-users-service,fcg-catalog-service,fcg-payments-service}`.

## Mapa de arquivos

| Repo | Arquivo | Responsabilidade |
|---|---|---|
| orchestration | `infra/eks/eks.tf` (modificar) | label do namespace para *pod readiness gate* do ALB |
| orchestration | `k8s/eks/kustomization.yaml` | namespace, lista de recursos, ConfigMap gerado |
| orchestration | `k8s/eks/config.env` | variáveis comuns não sensíveis |
| orchestration | `k8s/eks/redis.yaml` | Redis (cache do catalog) |
| orchestration | `k8s/eks/users-api.yaml` | Deployment + Service do users |
| orchestration | `k8s/eks/catalog-api.yaml` | Deployment (api + worker) + Service do catalog |
| orchestration | `k8s/eks/payments-api.yaml` | Deployment (api + worker) + Service do payments |
| orchestration | `k8s/eks/ingress.yaml` | Ingress → ALB com rotas por path |
| orchestration | `k8s/eks/README.md` | o que roda, como aplicar, como depurar |
| orchestration | `scripts/eks-up.sh` (modificar) | aplicar manifests, esperar rollouts, imprimir URL |
| orchestration | `scripts/eks-e2e.sh` | teste ponta a ponta automatizado pelo ALB |
| orchestration | `fcgames.eks.http` | mesmo fluxo para REST Client (vídeo/manual) |
| users/catalog/payments | `infra/ecs.tf`, `infra/api_gateway.tf`, `.aws/task-definition.json` (remover) | ECS aposentado |
| users/catalog/payments | `infra/outputs.tf`, `infra/variables.tf` (modificar) | tirar o que só servia ao ECS |
| users/catalog/payments | `infra/ecr.tf` (modificar) | lifecycle "últimas 10 imagens" |
| users/catalog/payments | `.github/workflows/deploy-on-pr-merge.yml` (modificar) | só `workflow_dispatch` |
| users/catalog/payments | `app/src/*.Api/appsettings.json` (modificar) | sem `Jwt:Key` |

Decisões de implementação além do spec (necessárias para "sem downtime" de verdade com ALB `target-type: ip`):
- Namespace com label `elbv2.k8s.aws/pod-readiness-gate-inject=enabled`: o pod novo só fica *Ready* depois que o ALB o marca *healthy* — sem isso o rolling update remove o pod antigo antes do ALB começar a mandar tráfego pro novo.
- `preStop` com `sleep` de 15 s e `deregistration_delay` de 15 s no target group: o pod antigo continua atendendo enquanto o ALB o retira.
- Teste e2e como script (`scripts/eks-e2e.sh`) em vez de só o `.http`, para o ciclo real ser verificável por comando; o `.http` fica para o vídeo.

---

### Task 0: Preparar branches

- [ ] **Step 1: Orchestration na branch certa**

Run: `git -C fcg-orchestration status -sb`
Expected: primeira linha `## feature/eks-cluster`

- [ ] **Step 2: Criar `feature/eks-migration` nos 3 serviços a partir de `origin/main`**

```bash
for d in fcg-users-api fcg-catalog-api fcg-payments-api; do
  git -C $d fetch -q origin
  git -C $d switch -c feature/eks-migration origin/main
  git -C $d branch --unset-upstream
  git -C $d status -sb | head -1
done
```
Expected: três linhas `## feature/eks-migration`. Se `switch` falhar por arquivos locais modificados e rastreados, parar e reportar (não descartar trabalho de ninguém).

---

### Task 1: Namespace com pod readiness gate

**Files:**
- Modify: `fcg-orchestration/infra/eks/eks.tf` (resource `kubernetes_namespace_v1.app`)

- [ ] **Step 1: Adicionar o label**

Substituir o bloco:
```hcl
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace
  }
```
por:
```hcl
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace

    labels = {
      # O LB Controller injeta um readiness gate nos pods deste namespace: o pod só fica
      # Ready quando o ALB o marca healthy — é o que torna o rolling update sem downtime
      # com target-type ip (sem isso o pod antigo sai antes do novo receber tráfego).
      "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled"
    }
  }
```

- [ ] **Step 2: Validar**

Run: `cd fcg-orchestration/infra/eks && terraform init -backend=false -input=false >/dev/null && terraform validate && terraform fmt -check; echo exit=$?`
Expected: `Success! The configuration is valid.` e `exit=0`

- [ ] **Step 3: Commit**

```bash
cd fcg-orchestration
git add infra/eks/eks.tf
git commit -m "feat(eks): readiness gate do ALB no namespace fcgames"
```

---

### Task 2: Manifests dos serviços (Kustomize)

**Files (todos em `fcg-orchestration/k8s/eks/`):** `config.env`, `kustomization.yaml`, `redis.yaml`, `users-api.yaml`, `catalog-api.yaml`, `payments-api.yaml`, `ingress.yaml`

- [ ] **Step 1: Teste que falha** — Run: `kubectl kustomize fcg-orchestration/k8s/eks`
Expected: erro (`unable to find one of 'kustomization.yaml'...`)

- [ ] **Step 2: `config.env`**

```dotenv
ASPNETCORE_ENVIRONMENT=Production
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
Messaging__Provider=Sqs
AWS__Region=sa-east-1
JWT__ISSUER=AppFiapFcGames
```

- [ ] **Step 3: `kustomization.yaml`**

```yaml
# Serviços do FCGames no EKS (fcg-eks). Aplicado pelo scripts/eks-up.sh:
#   kubectl apply -k k8s/eks
# O namespace, as ServiceAccounts (Pod Identity) e o Secret fcg-jwt vêm do Terraform
# (infra/eks) — não são declarados aqui.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: fcgames

resources:
  - redis.yaml
  - users-api.yaml
  - catalog-api.yaml
  - payments-api.yaml
  - ingress.yaml

# Gera o ConfigMap fcg-config com sufixo de hash: mudar config.env dispara rollout.
configMapGenerator:
  - name: fcg-config
    envs:
      - config.env
```

- [ ] **Step 4: `redis.yaml`**

```yaml
# Cache do catalog (invalidação no CriarJogoCommandHandler). Sem persistência: é cache.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  labels:
    app: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: public.ecr.aws/docker/library/redis:alpine
          ports:
            - name: redis
              containerPort: 6379
          resources:
            requests:
              memory: 32Mi
              cpu: 10m
            limits:
              memory: 64Mi
          readinessProbe:
            tcpSocket:
              port: redis
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  selector:
    app: redis
  ports:
    - name: redis
      port: 6379
      targetPort: redis
```

- [ ] **Step 5: `users-api.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: users-api
  labels:
    app: users-api
spec:
  replicas: 1
  revisionHistoryLimit: 3
  # Sem downtime: sobe o pod novo, espera ficar Ready (inclui o readiness gate do ALB),
  # só então derruba o antigo.
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: users-api
  template:
    metadata:
      labels:
        app: users-api
    spec:
      serviceAccountName: users-api # Pod Identity → role fcg-eks-users-api (SQS/SNS)
      terminationGracePeriodSeconds: 30
      volumes:
        - name: data
          emptyDir: {} # SQLite efêmero (decisão do time)
      containers:
        - name: api
          image: 915153720516.dkr.ecr.sa-east-1.amazonaws.com/fcg-users-service:latest
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 5001
          envFrom:
            - configMapRef:
                name: fcg-config
          env:
            - name: ASPNETCORE_URLS
              value: http://+:5001
            - name: ConnectionStrings__DefaultConnection
              value: Data Source=/data/users.db
            - name: JWT__KEY
              valueFrom:
                secretKeyRef:
                  name: fcg-jwt
                  key: jwt-key
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              memory: 128Mi
              cpu: 50m
            limits:
              memory: 384Mi
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health/live
              port: http
            initialDelaySeconds: 20
            periodSeconds: 10
          lifecycle:
            preStop:
              sleep:
                seconds: 15 # continua atendendo enquanto o ALB retira o target
---
apiVersion: v1
kind: Service
metadata:
  name: users-api
spec:
  selector:
    app: users-api
  ports:
    - name: http
      port: 80
      targetPort: http
```

- [ ] **Step 6: `catalog-api.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-api
  labels:
    app: catalog-api
spec:
  replicas: 1 # sem HPA: cada réplica teria seu próprio SQLite (ver spec)
  revisionHistoryLimit: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: catalog-api
  template:
    metadata:
      labels:
        app: catalog-api
    spec:
      serviceAccountName: catalog-api # Pod Identity → SQS/SNS + DynamoDB (Jogos, Desejos)
      terminationGracePeriodSeconds: 30
      volumes:
        - name: data
          emptyDir: {} # SQLite compartilhado entre api e worker (Pedidos, Bibliotecas)
      containers:
        - name: api
          image: 915153720516.dkr.ecr.sa-east-1.amazonaws.com/fcg-catalog-service:latest
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 5002
          envFrom:
            - configMapRef:
                name: fcg-config
          env:
            - name: ASPNETCORE_URLS
              value: http://+:5002
            - name: ConnectionStrings__DefaultConnection
              value: Data Source=/data/catalog.db
            - name: ConnectionStrings__Redis
              value: redis:6379
            - name: DynamoDb__Region
              value: sa-east-1
            - name: DynamoDb__ServiceUrl
              value: "" # vazio = DynamoDB real da AWS (não o dynamodb-local)
            - name: JWT__KEY
              valueFrom:
                secretKeyRef:
                  name: fcg-jwt
                  key: jwt-key
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              memory: 128Mi
              cpu: 50m
            limits:
              memory: 384Mi
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health/live
              port: http
            initialDelaySeconds: 20
            periodSeconds: 10
          lifecycle:
            preStop:
              sleep:
                seconds: 15
        # Consumers MassTransit (UsuarioCriado, PagamentoProcessado). Mesmo pod da API para
        # enxergar o mesmo SQLite. API e worker rodam Database.Migrate(); o EF Core 10 serializa
        # via __EFMigrationsLock — no pior caso o worker reinicia uma vez.
        - name: worker
          image: 915153720516.dkr.ecr.sa-east-1.amazonaws.com/fcg-catalog-service:worker-latest
          imagePullPolicy: Always
          envFrom:
            - configMapRef:
                name: fcg-config
          env:
            - name: ConnectionStrings__DefaultConnection
              value: Data Source=/data/catalog.db
            - name: DynamoDb__Region
              value: sa-east-1
            - name: DynamoDb__ServiceUrl
              value: ""
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              memory: 96Mi
              cpu: 25m
            limits:
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: catalog-api
spec:
  selector:
    app: catalog-api
  ports:
    - name: http
      port: 80
      targetPort: http
```

- [ ] **Step 7: `payments-api.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments-api
  labels:
    app: payments-api
spec:
  replicas: 1
  revisionHistoryLimit: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: payments-api
  template:
    metadata:
      labels:
        app: payments-api
    spec:
      serviceAccountName: payments-api # Pod Identity → SQS/SNS
      terminationGracePeriodSeconds: 30
      volumes:
        - name: data
          emptyDir: {} # SQLite compartilhado entre api e worker (Pagamentos)
      containers:
        - name: api
          image: 915153720516.dkr.ecr.sa-east-1.amazonaws.com/fcg-payments-service:latest
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 5003
          envFrom:
            - configMapRef:
                name: fcg-config
          env:
            - name: ASPNETCORE_URLS
              value: http://+:5003
            - name: ConnectionStrings__DefaultConnection
              value: Data Source=/data/payments.db
            - name: JWT__KEY
              valueFrom:
                secretKeyRef:
                  name: fcg-jwt
                  key: jwt-key
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              memory: 128Mi
              cpu: 50m
            limits:
              memory: 384Mi
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health/live
              port: http
            initialDelaySeconds: 20
            periodSeconds: 10
          lifecycle:
            preStop:
              sleep:
                seconds: 15
        # Consumer do PedidoRealizadoEvento (simula pagamento, publica PagamentoProcessado).
        - name: worker
          image: 915153720516.dkr.ecr.sa-east-1.amazonaws.com/fcg-payments-service:worker-latest
          imagePullPolicy: Always
          envFrom:
            - configMapRef:
                name: fcg-config
          env:
            - name: ConnectionStrings__DefaultConnection
              value: Data Source=/data/payments.db
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              memory: 96Mi
              cpu: 25m
            limits:
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: payments-api
spec:
  selector:
    app: payments-api
  ports:
    - name: http
      port: 80
      targetPort: http
```

- [ ] **Step 8: `ingress.yaml`**

```yaml
# Um ALB (criado pelo AWS Load Balancer Controller) para os 3 serviços, roteando por path.
# As rotas dos controllers não se repetem entre serviços, então não há rewrite.
# Quando o /search (OpenSearch) existir no catalog, adicionar a rota aqui.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fcgames
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "10"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
    # Casa com o preStop de 15 s dos pods: o ALB para de mandar tráfego antes do pod sair.
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=15
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /usuarios
            pathType: Prefix
            backend:
              service:
                name: users-api
                port:
                  name: http
          - path: /jogos
            pathType: Prefix
            backend:
              service:
                name: catalog-api
                port:
                  name: http
          - path: /compras
            pathType: Prefix
            backend:
              service:
                name: catalog-api
                port:
                  name: http
          - path: /biblioteca
            pathType: Prefix
            backend:
              service:
                name: catalog-api
                port:
                  name: http
          - path: /desejos
            pathType: Prefix
            backend:
              service:
                name: catalog-api
                port:
                  name: http
          - path: /pagamentos
            pathType: Prefix
            backend:
              service:
                name: payments-api
                port:
                  name: http
```

- [ ] **Step 9: Teste passa**

Run:
```bash
kubectl kustomize fcg-orchestration/k8s/eks > /tmp/eks-render.yaml && echo OK
grep -c "^kind:" /tmp/eks-render.yaml
grep -E "^kind:|namespace: fcgames" /tmp/eks-render.yaml | sort | uniq -c
grep -n "name: fcg-config-" /tmp/eks-render.yaml | head -3
```
Expected: `OK`; `10` documentos (1 ConfigMap, 4 Deployments, 4 Services, 1 Ingress); todos com `namespace: fcgames`; o ConfigMap renderizado como `fcg-config-<hash>` e referenciado com o mesmo nome nos `configMapRef`.

- [ ] **Step 10: Commit**

```bash
cd fcg-orchestration
git add k8s/eks/
git commit -m "feat(eks): manifests Kustomize dos serviços (users, catalog+worker, payments+worker, redis, ingress)"
```

---

### Task 3: `eks-up.sh` aplica os serviços

**Files:**
- Modify: `fcg-orchestration/scripts/eks-up.sh`

- [ ] **Step 1: Aviso de cluster ligado em caso de erro** — logo depois da linha `aws() { command aws "$@" | tr -d '\r'; }`, adicionar:

```bash

# Qualquer falha depois do apply deixa o cluster LIGADO (cobrando) — avisa sempre.
trap 'echo; echo "ERRO: o eks-up.sh falhou. Se o cluster chegou a ser criado ele está LIGADO e cobrando —"; echo "corrija e rode de novo, ou desligue com ./scripts/eks-down.sh"' ERR
```

- [ ] **Step 2: Deploy dos serviços** — substituir o trecho final:

```bash
log "Nodes:"
kubectl get nodes -o wide
log "Pods:"
kubectl get pods -A

log "Cluster ligado. Lembre: ./scripts/eks-down.sh ao terminar."
```
por:
```bash
log "Nodes:"
kubectl get nodes -o wide

log "Aplicando os serviços (k8s/eks)..."
(
  cd "$ROOT_DIR"
  kubectl apply -k k8s/eks
)

for deploy in redis users-api catalog-api payments-api; do
  log "Aguardando rollout de $deploy..."
  kubectl rollout status "deploy/$deploy" -n fcgames --timeout=300s
done

log "Pods:"
kubectl get pods -n fcgames -o wide

log "Aguardando o ALB do Ingress (até 5 min)..."
alb_host=""
for _ in $(seq 1 30); do
  alb_host="$(kubectl get ingress fcgames -n fcgames -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  [ -n "$alb_host" ] && break
  sleep 10
done
if [ -z "$alb_host" ]; then
  echo "AVISO: o Ingress ainda não tem endereço. Veja: kubectl describe ingress fcgames -n fcgames"
else
  log "URL pública: http://$alb_host   (o DNS do ALB pode levar 1-2 min para responder)"
fi

log "Cluster ligado. Lembre: ./scripts/eks-down.sh ao terminar."
```

- [ ] **Step 3: Atualizar o cabeçalho** — na linha `# Uso: ./scripts/eks-up.sh        (~15-20 min)`, trocar por:

```bash
# Uso: ./scripts/eks-up.sh        (~20 min: cluster + serviços de k8s/eks)
```

- [ ] **Step 4: Verificar**

Run: `cd fcg-orchestration && bash -n scripts/eks-up.sh && grep -c $'\r' scripts/eks-up.sh; echo exit=$?`
Expected: `0` e `exit=0` (`grep -c` imprime 0 e retorna 1 — aceitar `exit=1` quando a contagem for 0).

- [ ] **Step 5: Commit**

```bash
git add scripts/eks-up.sh
git commit -m "feat(eks): eks-up.sh aplica os serviços, espera rollouts e mostra a URL do ALB"
```

---

### Task 4: Teste ponta a ponta e arquivo `.http`

**Files:**
- Create: `fcg-orchestration/scripts/eks-e2e.sh`
- Create: `fcg-orchestration/fcgames.eks.http`

- [ ] **Step 1: `scripts/eks-e2e.sh`**

```bash
#!/usr/bin/env bash
# ==============================================================================
# FCGames — teste ponta a ponta no EKS, pelo ALB público:
#   cadastro → biblioteca criada (evento via SNS/SQS) → login → compra aprovada
#   (preço <= 100) → compra rejeitada (preço > 100) → pagamento consultado.
#
# Uso: ./scripts/eks-e2e.sh [URL_BASE]
#   Sem argumento, descobre a URL pelo Ingress "fcgames" (precisa do kubectl apontando
#   para o fcg-eks — o eks-up.sh já configura).
# ==============================================================================
set -euo pipefail

PY="$(command -v python3 || command -v python)"
BASE="${1:-}"
if [ -z "$BASE" ]; then
  host="$(kubectl get ingress fcgames -n fcgames -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  [ -n "$host" ] || { echo "Erro: Ingress fcgames sem endereço."; exit 1; }
  BASE="http://$host"
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "FALHOU: $*"; exit 1; }
# Lê JSON do stdin e avalia uma expressão Python sobre ele (variável d).
jq_py() { "$PY" -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# Repete um GET até a expressão Python retornar "ok" (eventos são assíncronos).
wait_for() {
  local url="$1" expr="$2" token="$3" body
  for _ in $(seq 1 30); do
    body="$(curl -s -H "Authorization: Bearer $token" "$url" || true)"
    if [ -n "$body" ] && [ "$(echo "$body" | jq_py "$expr" 2>/dev/null || true)" = "ok" ]; then
      echo "$body"
      return 0
    fi
    sleep 2
  done
  return 1
}

log "Base: $BASE"
email="e2e-$(date +%s)@teste.com"
senha="E2e@12345"

log "1) Cadastro ($email)"
cadastro="$(curl -sf -X POST "$BASE/usuarios" -H 'Content-Type: application/json' \
  -d "{\"nome\":\"e2e\",\"email\":\"$email\",\"senha\":\"$senha\"}")" || fail "POST /usuarios"
uid="$(echo "$cadastro" | jq_py "d['id']")"

log "2) Login"
token="$(curl -sf -X POST "$BASE/usuarios/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$email\",\"senha\":\"$senha\"}" | jq_py "d['token']")" || fail "POST /usuarios/login"

log "3) Biblioteca criada pelo worker do catalog (UsuarioCriadoEvento)"
wait_for "$BASE/biblioteca/$uid" "'ok' if d['usuarioId'] else ''" "$token" >/dev/null \
  || fail "biblioteca de $uid não apareceu em 60 s"

log "4) Escolhendo jogos (preço <= 100 e > 100)"
jogos="$(curl -sf -H "Authorization: Bearer $token" "$BASE/jogos")" || fail "GET /jogos"
barato="$(echo "$jogos" | jq_py "next(j['id'] for j in d if 0 < j['preco'] <= 100)")"
caro="$(echo "$jogos" | jq_py "next(j['id'] for j in d if j['preco'] > 100)")"

log "5) Compra aprovada ($barato)"
pedido_ok="$(curl -sf -X POST "$BASE/compras" -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' -d "{\"jogoId\":\"$barato\"}" | jq_py "d['orderId']")" || fail "POST /compras (barato)"
wait_for "$BASE/compras/$pedido_ok" "'ok' if d['status']=='Aprovado' else ''" "$token" >/dev/null \
  || fail "pedido $pedido_ok não ficou Aprovado"

log "6) Compra rejeitada ($caro)"
pedido_nok="$(curl -sf -X POST "$BASE/compras" -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' -d "{\"jogoId\":\"$caro\"}" | jq_py "d['orderId']")" || fail "POST /compras (caro)"
wait_for "$BASE/compras/$pedido_nok" "'ok' if d['status']=='Rejeitado' else ''" "$token" >/dev/null \
  || fail "pedido $pedido_nok não ficou Rejeitado"

log "7) Pagamento do pedido aprovado"
wait_for "$BASE/pagamentos/$pedido_ok" "'ok' if d['status']=='Aprovado' else ''" "$token" >/dev/null \
  || fail "pagamento de $pedido_ok não está Aprovado"

log "8) Jogo na biblioteca"
wait_for "$BASE/biblioteca/$uid" "'ok' if any(j['jogoId']=='$barato' for j in d['jogos']) else ''" "$token" >/dev/null \
  || fail "jogo $barato não está na biblioteca"

log "OK — fluxo completo passou (aprovado: $pedido_ok, rejeitado: $pedido_nok)"
```

Campos conferidos no código: `POST /usuarios` → `id`; login → `token`; `POST /compras` → `orderId`; `GET /compras/{id}` e `GET /pagamentos/{id}` → `status` como string (`Aprovado`/`Rejeitado`); `GET /biblioteca/{id}` → `usuarioId`, `jogos[].jogoId`; `GET /jogos` → lista com `id`, `preco`.

- [ ] **Step 2: Permissão, LF e sintaxe**

Run:
```bash
cd fcg-orchestration
bash -n scripts/eks-e2e.sh && grep -c $'\r' scripts/eks-e2e.sh
git add --chmod=+x scripts/eks-e2e.sh
```
Expected: `0`

- [ ] **Step 3: `fcgames.eks.http`** (cópia do fluxo do `fcgames.aws.http` com uma URL só — o `fcgames.aws.http` antigo fica como está)

```http
################################################################################
# FCGames no EKS — fluxo completo pelo ALB (REST Client / HTTP Client do Rider)
#
# 1. ./scripts/eks-up.sh imprime a "URL pública" no final — cole em @base abaixo.
# 2. Rode os blocos NA ORDEM. Tudo passa pelo mesmo ALB (rotas por path).
# Para acompanhar a mensageria:
#   kubectl logs -n fcgames deploy/catalog-api -c worker -f
#   kubectl logs -n fcgames deploy/payments-api -c worker -f
################################################################################

@base = http://COLE-AQUI-O-HOST-DO-ALB

### 1) Cadastro -> publica UsuarioCriadoEvento (catalog cria a biblioteca)
# @name cadastro
POST {{base}}/usuarios
Content-Type: application/json

{
  "nome": "rogers",
  "email": "rogers-eks@teste.com",
  "senha": "rogers@123"
}

### 2) Login -> JWT
# @name login
POST {{base}}/usuarios/login
Content-Type: application/json

{
  "email": "rogers-eks@teste.com",
  "senha": "rogers@123"
}

### 3) Jogos (DynamoDB) — escolha um com preço <= 100 e outro > 100
# @name jogos
GET {{base}}/jogos
Authorization: Bearer {{login.response.body.$.token}}

### 4) Compra APROVADA (ajuste o índice para um jogo com preço <= 100)
# @name compraAprovada
POST {{base}}/compras
Authorization: Bearer {{login.response.body.$.token}}
Content-Type: application/json

{
  "jogoId": "{{jogos.response.body.$[0].id}}"
}

### 5) Compra REJEITADA (ajuste o índice para um jogo com preço > 100)
# @name compraRejeitada
POST {{base}}/compras
Authorization: Bearer {{login.response.body.$.token}}
Content-Type: application/json

{
  "jogoId": "{{jogos.response.body.$[1].id}}"
}

### 6) Pedido aprovado (aguarde ~5 s — SNS/SQS é assíncrono)
GET {{base}}/compras/{{compraAprovada.response.body.$.orderId}}
Authorization: Bearer {{login.response.body.$.token}}

### 7) Pagamento do pedido aprovado
GET {{base}}/pagamentos/{{compraAprovada.response.body.$.orderId}}
Authorization: Bearer {{login.response.body.$.token}}

### 8) Biblioteca -> deve conter o jogo aprovado
GET {{base}}/biblioteca/{{cadastro.response.body.$.id}}
Authorization: Bearer {{login.response.body.$.token}}

### Admin (seed: admin@fcgames.com / Admin@123)
# @name loginAdmin
POST {{base}}/usuarios/login
Content-Type: application/json

{
  "email": "admin@fcgames.com",
  "senha": "Admin@123"
}
```

- [ ] **Step 4: Commit**

```bash
git add scripts/eks-e2e.sh fcgames.eks.http
git commit -m "test(eks): teste ponta a ponta pelo ALB (eks-e2e.sh) e fcgames.eks.http"
```

---

### Task 5: README do `k8s/eks`

**Files:**
- Create: `fcg-orchestration/k8s/eks/README.md`

- [ ] **Step 1: Escrever**

````markdown
# Serviços no EKS (`k8s/eks`)

Manifests (YAML + Kustomize) dos serviços do FCGames no cluster `fcg-eks`.
Aplicados automaticamente pelo `scripts/eks-up.sh`. Design:
[`docs/superpowers/specs/2026-10-06-eks-services-design.md`](../../docs/superpowers/specs/2026-10-06-eks-services-design.md).

## O que roda (namespace `fcgames`)

| Deployment | Containers | Porta | Imagem (ECR) |
|---|---|---|---|
| `users-api` | api | 5001 | `fcg-users-service:latest` |
| `catalog-api` | api + worker (mesmo pod, SQLite em `emptyDir`) | 5002 | `fcg-catalog-service:latest` / `:worker-latest` |
| `payments-api` | api + worker (mesmo pod, SQLite em `emptyDir`) | 5003 | `fcg-payments-service:latest` / `:worker-latest` |
| `redis` | redis (cache do catalog) | 6379 | `public.ecr.aws/docker/library/redis:alpine` |

Um Ingress (`fcgames`) cria **um ALB** com rotas por path:
`/usuarios` → users · `/jogos`, `/compras`, `/biblioteca`, `/desejos` → catalog · `/pagamentos` → payments.

Vem do Terraform (`infra/eks`), não daqui: namespace, ServiceAccounts com Pod Identity
(credenciais AWS sem access key) e o Secret `fcg-jwt` (`JWT__KEY`).

**SQLite é efêmero**: cada restart/deploy de pod zera Pedidos/Bibliotecas/Pagamentos/Usuários
(o admin seed é recriado). Jogos e Desejos ficam no DynamoDB e persistem. Por isso `replicas: 1`
e **sem HPA** (cada réplica teria seu próprio banco).

## Comandos

```bash
kubectl apply -k k8s/eks                          # aplicar (o eks-up.sh já faz)
kubectl kustomize k8s/eks                         # ver o YAML final sem aplicar
kubectl get pods -n fcgames
kubectl logs -n fcgames deploy/catalog-api -c worker -f
kubectl rollout restart deploy/users-api -n fcgames  # rolling update sem downtime
./scripts/eks-e2e.sh                              # fluxo completo pelo ALB
```

## Sem downtime — como funciona

`maxSurge: 1` / `maxUnavailable: 0` + readiness `/health` + *pod readiness gate* do ALB
(label no namespace) + `preStop` de 15 s casado com `deregistration_delay` de 15 s no target group.

## Troubleshooting

| Sintoma | Causa provável |
|---|---|
| `ImagePullBackOff` | imagem não existe no ECR (lifecycle mantém só as últimas 10) — rebuild/push |
| `CrashLoopBackOff` no worker | ver `kubectl logs ... -c worker --previous`; 1 restart no 1º start é normal (lock de migração) |
| 502/503 no ALB logo após subir | target group ainda registrando — aguarde 1-2 min |
| Pod `Pending` | memória dos 2× t3.small esgotada — `kubectl describe pod` e `kubectl top pods -n fcgames` |
````

- [ ] **Step 2: Commit**

```bash
git add k8s/eks/README.md
git commit -m "docs(eks): README dos manifests dos serviços"
```

---

### Task 6: Repo `fcg-users-api` — aposentar ECS, lifecycle, workflow, JWT

**Files (em `fcg-users-api/`):**
- Delete: `infra/ecs.tf`, `infra/api_gateway.tf`, `infra/outputs.tf`, `.aws/task-definition.json`
- Modify: `infra/variables.tf`, `infra/ecr.tf`, `.github/workflows/deploy-on-pr-merge.yml`, `app/src/Fiap.FCGames.Users.Api/appsettings.json`

- [ ] **Step 1: Remover arquivos do ECS**

```bash
cd fcg-users-api
git rm -q infra/ecs.tf infra/api_gateway.tf infra/outputs.tf .aws/task-definition.json
```
(`outputs.tf` só tinha outputs do ECS.)

- [ ] **Step 2: `infra/variables.tf`** — remover os blocos `variable "app_port"` e `variable "cluster_name"` inteiros (só o ECS usava). Manter `aws_region` e `service_name`.

- [ ] **Step 3: `infra/ecr.tf`** — substituir o comentário e o resource `aws_ecr_lifecycle_policy.app_repo_policy` por:

```hcl
# Mantém as últimas 10 imagens (API + worker contam juntas). A regra antiga
# (sinceImagePushed 5 dias) apagava TUDO quando ninguém fazia push por 5 dias.
resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```

- [ ] **Step 4: Workflow desarmado** — em `.github/workflows/deploy-on-pr-merge.yml`, substituir o bloco `on:` inteiro (de `on:` até a linha antes de `# Enfileira em vez de rodar em paralelo`) por:

```yaml
# DESATIVADO (Fase 4): o ECS foi removido — o serviço roda no EKS (fcg-orchestration/k8s/eks).
# Rodar este workflow agora recriaria só o ECR e falharia no deploy ECS. O pipeline novo
# (build → ECR → rollout no EKS) chega na parte 3; até lá, só disparo manual.
on:
  workflow_dispatch:

```

- [ ] **Step 5: JWT fora do `appsettings.json`** — em `app/src/Fiap.FCGames.Users.Api/appsettings.json`, trocar:

```json
  "Jwt": {
    "Key": "ChaveSegredo12345671212121321341231231890",
    "Issuer": "AppFiapFcGames"    
  },
```
por:
```json
  "Jwt": {
    "Issuer": "AppFiapFcGames"
  },
```
(`appsettings.Development.json` já tem a chave de desenvolvimento — não mexer. Em produção a chave vem de `JWT__KEY` / Secret `fcg-jwt`; docker-compose usa `JWT__KEY: ${JWT_KEY}`.)

- [ ] **Step 6: Build continua passando**

Run: `cd fcg-users-api && dotnet build app/src/Fiap.FCGames.Users.slnx -nologo -v q 2>&1 | tail -3`
Expected: `0 Error(s)` / `Build succeeded` (warnings ok).

- [ ] **Step 7: Terraform — validar e conferir o plano de destruição (sem aplicar)**

```bash
cd fcg-users-api/infra
export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1
terraform fmt -check && terraform init -input=false -no-color >/dev/null && terraform validate
terraform plan -input=false -no-color > /tmp/plan-users.txt
grep -E "^Plan:|will be destroyed|will be updated|will be created" /tmp/plan-users.txt
grep -c "aws_ecr_repository.app_repo will be destroyed" /tmp/plan-users.txt
```
Expected: `Success!`; a lista só tem `will be destroyed` de recursos ECS/ASG/launch template/SG/IAM/log group/API Gateway, mais **1 update** em `aws_ecr_lifecycle_policy.app_repo_policy`; nenhum `aws_ecr_repository` destruído (último comando imprime `0`). Se aparecer qualquer outra coisa, parar e reportar.

- [ ] **Step 8: Commit**

```bash
cd fcg-users-api
git add -A infra .github app/src/Fiap.FCGames.Users.Api/appsettings.json
git status -s   # conferir: nada de *.db, bin/, obj/
git commit -m "chore: aposenta ECS (serviço roda no EKS), lifecycle ECR 10 imagens, JWT fora do appsettings

- remove ecs.tf, api_gateway.tf, outputs.tf e .aws/task-definition.json
- ECR mantido; lifecycle passa a manter as últimas 10 imagens (antes apagava após 5 dias)
- deploy-on-pr-merge.yml só por workflow_dispatch até o pipeline EKS (Fase 4 parte 3)
- Jwt:Key removido do appsettings.json (produção usa JWT__KEY do Secret fcg-jwt)"
```

---

### Task 7: Repo `fcg-catalog-api` — aposentar ECS, lifecycle, workflow, JWT

**Files (em `fcg-catalog-api/`):**
- Delete: `infra/ecs.tf`, `infra/api_gateway.tf`, `.aws/task-definition.json`
- Modify: `infra/outputs.tf`, `infra/variables.tf`, `infra/ecr.tf`, `.github/workflows/deploy-on-pr-merge.yml`, `app/src/Fiap.FCGames.Catalogo.Api/appsettings.json`

- [ ] **Step 1: Remover arquivos do ECS**

```bash
cd fcg-catalog-api
git rm -q infra/ecs.tf infra/api_gateway.tf .aws/task-definition.json
```

- [ ] **Step 2: `infra/outputs.tf`** — deixar só o output do ECR:

```hcl
output "ecr_repository_url" {
  value       = aws_ecr_repository.app_repo.repository_url
  description = "URI do repositório ECR criado para o microsserviço"
}
```

- [ ] **Step 3: `infra/variables.tf`** — remover os blocos `variable "app_port"` e `variable "cluster_name"` inteiros. Manter `aws_region` e `service_name`.

- [ ] **Step 4: `infra/ecr.tf`** — substituir o comentário acima do lifecycle e o resource `aws_ecr_lifecycle_policy.app_repo_policy` pelo mesmo bloco da Task 6 Step 3:

```hcl
# Mantém as últimas 10 imagens (API + worker contam juntas). A regra antiga
# (sinceImagePushed 5 dias) apagava TUDO quando ninguém fazia push por 5 dias.
resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```
(Se o nome do resource no `ecr.tf` do catalog for diferente de `app_repo_policy`, manter o nome existente para não recriar o recurso.)

- [ ] **Step 5: Workflow desarmado** — em `.github/workflows/deploy-on-pr-merge.yml`, substituir o bloco `on:` inteiro (de `on:` até a linha antes de `permissions:`, incluindo os gatilhos `pull_request` **e** `push`) por:

```yaml
# DESATIVADO (Fase 4): o ECS foi removido — o serviço roda no EKS (fcg-orchestration/k8s/eks).
# Rodar este workflow agora recriaria só o ECR e falharia no deploy ECS. O pipeline novo
# (build → ECR → rollout no EKS) chega na parte 3; até lá, só disparo manual.
on:
  workflow_dispatch:

```
Importante: este mesmo PR não pode disparar o workflow antigo — como o gatilho `pull_request` sai neste commit, o GitHub usa a versão do PR e não roda.

- [ ] **Step 6: JWT fora do `appsettings.json`** — em `app/src/Fiap.FCGames.Catalogo.Api/appsettings.json`, trocar:

```json
  "Jwt": {
    "Key": "ChaveSegredo12345671212121321341231231890",
    "Issuer": "AppFiapFcGames"
  },
```
por:
```json
  "Jwt": {
    "Issuer": "AppFiapFcGames"
  },
```

- [ ] **Step 7: Build**

Run: `cd fcg-catalog-api && dotnet build app/src/Fiap.FCGames.Catalogo.Api.slnx -nologo -v q 2>&1 | tail -3`
Expected: `0 Error(s)`.

- [ ] **Step 8: Terraform — validar e conferir o plano (sem aplicar)**

```bash
cd fcg-catalog-api/infra
export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1
terraform fmt -check && terraform init -input=false -no-color >/dev/null && terraform validate
terraform plan -input=false -no-color > /tmp/plan-catalog.txt
grep -E "^Plan:|will be destroyed|will be updated|will be created" /tmp/plan-catalog.txt
grep -c "aws_ecr_repository.app_repo will be destroyed" /tmp/plan-catalog.txt
```
Expected: só destruições de ECS/ASG/launch template/SG/IAM (incl. policies de DynamoDB/SQS)/log group/API Gateway + 1 update no lifecycle; `0` no último comando.

- [ ] **Step 9: Commit**

```bash
cd fcg-catalog-api
git add -A infra .github app/src/Fiap.FCGames.Catalogo.Api/appsettings.json
git status -s
git commit -m "chore: aposenta ECS (serviço roda no EKS), lifecycle ECR 10 imagens, JWT fora do appsettings

- remove ecs.tf, api_gateway.tf e .aws/task-definition.json; outputs só do ECR
- ECR mantido; lifecycle passa a manter as últimas 10 imagens (antes apagava após 5 dias)
- deploy-on-pr-merge.yml só por workflow_dispatch até o pipeline EKS (Fase 4 parte 3)
- Jwt:Key removido do appsettings.json (produção usa JWT__KEY do Secret fcg-jwt)"
```

---

### Task 8: Repo `fcg-payments-api` — aposentar ECS, lifecycle, workflow, JWT

**Files (em `fcg-payments-api/`):**
- Delete: `infra/ecs.tf`, `infra/api_gateway.tf`, `infra/outputs.tf`, `.aws/task-definition.json`
- Modify: `infra/variables.tf`, `infra/ecr.tf`, `.github/workflows/deploy-on-pr-merge.yml`, `app/src/Fiap.FCGames.Payments.Api/appsettings.json`

- [ ] **Step 1: Remover arquivos do ECS**

```bash
cd fcg-payments-api
git rm -q infra/ecs.tf infra/api_gateway.tf infra/outputs.tf .aws/task-definition.json
```
(`outputs.tf` só tinha outputs do ECS.)

- [ ] **Step 2: `infra/variables.tf`** — remover os blocos `variable "app_port"` e `variable "cluster_name"` inteiros. Manter `aws_region` e `service_name`.

- [ ] **Step 3: `infra/ecr.tf`** — substituir o comentário acima do lifecycle e o resource `aws_ecr_lifecycle_policy.app_repo_policy` por:

```hcl
# Mantém as últimas 10 imagens (API + worker contam juntas). A regra antiga
# (sinceImagePushed 5 dias) apagava TUDO quando ninguém fazia push por 5 dias.
resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```
(Manter o nome de resource existente se for diferente.)

- [ ] **Step 4: Workflow desarmado** — em `.github/workflows/deploy-on-pr-merge.yml`, substituir o bloco `on:` inteiro (de `on:` até a linha antes de `permissions:`, incluindo `pull_request` e `push`) por:

```yaml
# DESATIVADO (Fase 4): o ECS foi removido — o serviço roda no EKS (fcg-orchestration/k8s/eks).
# Rodar este workflow agora recriaria só o ECR e falharia no deploy ECS. O pipeline novo
# (build → ECR → rollout no EKS) chega na parte 3; até lá, só disparo manual.
on:
  workflow_dispatch:

```

- [ ] **Step 5: JWT fora do `appsettings.json`** — em `app/src/Fiap.FCGames.Payments.Api/appsettings.json`, trocar:

```json
  "Jwt": {
    "Key": "ChaveSegredo12345671212121321341231231890",
    "Issuer": "AppFiapFcGames"
  },
```
por:
```json
  "Jwt": {
    "Issuer": "AppFiapFcGames"
  },
```

- [ ] **Step 6: Build**

Run: `cd fcg-payments-api && dotnet build app/src/Fiap.FCGames.Payments.Api.slnx -nologo -v q 2>&1 | tail -3`
Expected: `0 Error(s)`.

- [ ] **Step 7: Terraform — validar e conferir o plano (sem aplicar)**

```bash
cd fcg-payments-api/infra
export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1
terraform fmt -check && terraform init -input=false -no-color >/dev/null && terraform validate
terraform plan -input=false -no-color > /tmp/plan-payments.txt
grep -E "^Plan:|will be destroyed|will be updated|will be created" /tmp/plan-payments.txt
grep -c "aws_ecr_repository.app_repo will be destroyed" /tmp/plan-payments.txt
```
Expected: só destruições de ECS/API Gateway & cia + 1 update no lifecycle; `0` no último comando.

- [ ] **Step 8: Commit**

```bash
cd fcg-payments-api
git add -A infra .github app/src/Fiap.FCGames.Payments.Api/appsettings.json
git status -s   # conferir: os fcgames*.db não rastreados NÃO podem entrar
git commit -m "chore: aposenta ECS (serviço roda no EKS), lifecycle ECR 10 imagens, JWT fora do appsettings

- remove ecs.tf, api_gateway.tf, outputs.tf e .aws/task-definition.json
- ECR mantido; lifecycle passa a manter as últimas 10 imagens (antes apagava após 5 dias)
- deploy-on-pr-merge.yml só por workflow_dispatch até o pipeline EKS (Fase 4 parte 3)
- Jwt:Key removido do appsettings.json (produção usa JWT__KEY do Secret fcg-jwt)"
```

---

### Task 9: ⚠️ Destruir o ECS na AWS (pedir confirmação ao usuário)

- [ ] **Step 1: Mostrar ao usuário** o resumo dos 3 planos (`grep "^Plan:"` de `/tmp/plan-{users,catalog,payments}.txt` + lista de recursos a destruir) e **pedir confirmação**.

- [ ] **Step 2: Aplicar, um serviço por vez**

```bash
export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1
for d in fcg-users-api fcg-catalog-api fcg-payments-api; do
  echo "===== $d"
  (cd $d/infra && terraform apply -input=false -auto-approve -no-color | grep -E "^Apply complete|Error")
done
```
Expected: três `Apply complete! Resources: 0 added, 1 changed, N destroyed.`

- [ ] **Step 3: Conferir na AWS**

```bash
aws ecs list-clusters --output text | tr -d '\r'                                   # vazio
aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(AutoScalingGroupName,'service-asg')].AutoScalingGroupName" --output text | tr -d '\r'   # vazio
aws apigatewayv2 get-apis --query 'Items[].Name' --output text | tr -d '\r'        # sem fcg-*-service-api-gateway
aws ecr describe-repositories --query 'repositories[].repositoryName' --output text | tr -d '\r'  # os 3 fcg-*-service continuam
for r in fcg-users-service fcg-catalog-service fcg-payments-service; do aws ecr get-lifecycle-policy --repository-name $r --query lifecyclePolicyText --output text | tr -d '\r' | grep -o imageCountMoreThan; done   # 3x imageCountMoreThan
```

---

### Task 10: Build e push das imagens (uma vez)

- [ ] **Step 1: Login no ECR**

```bash
export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1
REG=915153720516.dkr.ecr.sa-east-1.amazonaws.com
aws ecr get-login-password | tr -d '\r' | docker login --username AWS --password-stdin $REG
```
Expected: `Login Succeeded`

- [ ] **Step 2: Build e push** (contexto = raiz de cada repo, na branch `feature/eks-migration` — já sem `Jwt:Key`; o token entra só como build secret)

```bash
[ -n "${NUGET_AUTH_TOKEN:-}" ] || { echo "NUGET_AUTH_TOKEN ausente"; exit 1; }
build_push() { # repo dockerfile ecr_repo tag_prefix
  local repo=$1 df=$2 ecr=$3 prefix=$4 sha
  sha=$(git -C $repo rev-parse --short HEAD)
  docker build --platform linux/amd64 --secret id=GITHUB_TOKEN,env=NUGET_AUTH_TOKEN \
    -f $repo/$df -t $REG/$ecr:${prefix}$sha -t $REG/$ecr:${prefix}latest $repo
  docker push $REG/$ecr:${prefix}$sha
  docker push $REG/$ecr:${prefix}latest
}
build_push fcg-users-api    Dockerfile        fcg-users-service    ""
build_push fcg-catalog-api  Dockerfile        fcg-catalog-service  ""
build_push fcg-catalog-api  Dockerfile.worker fcg-catalog-service  "worker-"
build_push fcg-payments-api Dockerfile        fcg-payments-service ""
build_push fcg-payments-api Dockerfile.worker fcg-payments-service "worker-"
```
Os 5 Dockerfiles usam `--mount=type=secret,id=GITHUB_TOKEN` (conferido).

- [ ] **Step 3: Conferir**

```bash
for r in fcg-users-service fcg-catalog-service fcg-payments-service; do
  echo "== $r"; aws ecr describe-images --repository-name $r --query 'imageDetails[].imageTags' --output text | tr -d '\r'
done
```
Expected: users com `<sha> latest`; catalog e payments com `<sha> latest` e `worker-<sha> worker-latest`.

---

### Task 11: ⚠️ Ciclo real (custo ~US$ 0,20 dos créditos — pedir confirmação ao usuário)

Rodar comandos longos com `run_in_background` (o `eks-up.sh` leva ~20 min).

- [ ] **Step 1: Ligar** — Run: `cd fcg-orchestration && ./scripts/eks-up.sh`
Expected: termina com `URL pública: http://k8s-fcgames-fcgames-....elb.amazonaws.com` e `Cluster ligado.`; os 4 `rollout status` com `successfully rolled out`.

- [ ] **Step 2: Pods** — Run: `kubectl get pods -n fcgames`
Expected: `users-api-*` 1/1, `catalog-api-*` 2/2, `payments-api-*` 2/2, `redis-*` 1/1, todos `Running`, RESTARTS ≤ 1.

- [ ] **Step 3: Fluxo completo** — Run: `./scripts/eks-e2e.sh`
Expected: termina com `OK — fluxo completo passou`. Se falhar, ver `kubectl logs -n fcgames deploy/<svc> -c <api|worker>` e corrigir antes de seguir (lembrar: cluster ligado = custo).

- [ ] **Step 4: Rolling update sem downtime**

```bash
URL=$(kubectl get ingress fcgames -n fcgames -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
( for i in $(seq 1 120); do
    curl -s -o /dev/null -w "%{http_code}\n" -X POST "http://$URL/usuarios/login" \
      -H 'Content-Type: application/json' -d '{"email":"admin@fcgames.com","senha":"Admin@123"}'
    sleep 1
  done ) > /tmp/rolling.txt &
sleep 5
kubectl rollout restart deploy/users-api -n fcgames
kubectl rollout status deploy/users-api -n fcgames --timeout=300s
wait
sort /tmp/rolling.txt | uniq -c
```
Expected: só `200` (nenhum `000`, `5xx`).

- [ ] **Step 5: Desligar** — Run: `./scripts/eks-down.sh`
Expected: `Cluster desligado.` sem "sobraram recursos"; depois `aws eks list-clusters` vazio e nenhum load balancer.

- [ ] **Step 6: Se algum passo exigiu correção**, commitar como `fix(eks): ...` no repo certo e registrar.

---

### Task 12: CLAUDE.md, memória e PRs

- [ ] **Step 1: `CLAUDE.md`** (raiz do workspace, fora de git) — na seção 2.6, substituir a linha `- Próximos: parte 2 (...) e parte 3 (CI/CD).` por:

```markdown
**Fase 4 — parte 2: serviços no EKS (`k8s/eks/`)** (feito):
- Manifests YAML + Kustomize centralizados; `eks-up.sh` aplica e imprime a URL do ALB; `scripts/eks-e2e.sh` testa o fluxo completo.
- users / catalog (api+worker) / payments (api+worker) / redis; worker no mesmo pod da API (SQLite em `emptyDir`); `replicas: 1`, sem HPA.
- 1 Ingress → 1 ALB, rotas por path (`/usuarios`, `/jogos`, `/compras`, `/biblioteca`, `/desejos`, `/pagamentos`).
- Sem downtime: readiness gate do ALB (label no namespace) + preStop 15 s + deregistration_delay 15 s.
- ECS e API Gateways **destruídos**; ECR mantido com lifecycle "últimas 10 imagens" (a antiga apagava tudo após 5 dias).
- Workflows `deploy-on-pr-merge.yml` dos serviços só por `workflow_dispatch` até a parte 3.
- `Jwt:Key` fora do `appsettings.json` (só no `appsettings.Development.json`); produção usa o Secret `fcg-jwt`.
- Próximo: parte 3 (GitHub Actions: pipeline build→teste→Trivy→ECR→`kubectl set image` para users e catalog + botão liga/desliga do cluster).
```
E na seção 4.1, marcar `- [x] Externalizar Jwt:Key para env var` (remover o texto "ainda pendente").

- [ ] **Step 2: Mostrar ao usuário** `git log --oneline` das branches (orchestration `feature/eks-cluster`, serviços `feature/eks-migration`) e **perguntar** se pode dar push e abrir os PRs (orchestration + 3 serviços).

- [ ] **Step 3 (após "sim")**: `git push -u origin <branch>` e `gh pr create --base main` em cada repo, com o corpo descrevendo as mudanças e os resultados da Task 11.
