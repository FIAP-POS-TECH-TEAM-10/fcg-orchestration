# Fase 4 — Parte 2: Serviços no EKS (design)

**Data:** 2026-10-06
**Responsável:** Daniel
**Status:** aprovado no brainstorming, aguardando plano de implementação
**Depende de:** parte 1 — `docs/superpowers/specs/2026-10-06-eks-cluster-design.md` (cluster `fcg-eks`)

## Contexto

A parte 1 entregou o cluster `fcg-eks` liga/desliga (2× t3.small, LB Controller, Pod Identity
com ServiceAccounts `users-api`/`catalog-api`/`payments-api`, Secret `fcg-jwt`). Esta parte
coloca os serviços users, catalog e payments rodando nele e aposenta o ECS.

Sequência da Fase 4: parte 1 (cluster) ✅ → **parte 2 (serviços)** → parte 3 (GitHub Actions:
pipeline de deploy dos serviços **e** ligar/desligar o cluster por botão).

### Achados que motivam parte do escopo

1. **ECR vazio** nos 3 repositórios: a lifecycle policy (`ecr.tf` de cada serviço) diz "manter
   as últimas 5 imagens" mas a regra é `sinceImagePushed` 5 dias — sem push há mais de 5 dias,
   tudo expirou.
2. **JWT hardcoded** (`Jwt:Key`) no `appsettings.json` de users, catalog e payments — viola
   "Zero Hardcoded Credentials" do PDF mesmo com `JWT__KEY` sobrescrevendo em runtime.
3. **Workflow `deploy-on-pr-merge.yml`** de cada serviço roda `terraform apply` do ECS a cada
   push na `main` → religa EC2 (desired=1) e volta a cobrar.

## Decisões

| Tema | Decisão | Alternativas descartadas |
|---|---|---|
| Local dos manifests | **Centralizados** em `fcg-orchestration/k8s/eks/` | por serviço (eks-up teria de buscar 3 repos privados) |
| Formato | **YAML + Kustomize** (`kubectl apply -k`) | Helm chart próprio; recursos `kubernetes_*` no Terraform |
| Imagens nos manifests | tag `:latest`; pipeline (parte 3) faz `kubectl set image …:<sha>` | — |
| Worker | **mesmo pod** da API (2 containers) com `emptyDir` em `/data` compartilhando o SQLite | Deployment separado (SQLite não compartilha entre pods) |
| Corrida de migração | sem ordenação: API e Worker chamam `Database.Migrate()`; EF Core 10 tem lock de migração (`__EFMigrationsLock`); no pior caso o k8s reinicia o container | wrapper esperando `/health` |
| Redis | Deployment `redis:alpine` + Service `redis` no cluster, sem persistência | ElastiCache (custo) |
| Exposição | 1 Ingress → 1 ALB, roteamento por path, sem rewrite | ALB por serviço |
| HPA | **não** nesta parte (PDF não exige; com SQLite efêmero cada réplica teria banco próprio e o fluxo de compra quebraria) | HPA só para demo; migrar Pedidos para DynamoDB |
| Swagger/Scalar | desligados (`ASPNETCORE_ENVIRONMENT=Production`); rotas `/scalar` colidiriam no ALB | — |
| ECS | **destruído** (cluster, ASG, launch template, SG, roles, log group, API Gateway); **ECR mantido** | manter até a parte 3 |
| Workflow antigo | `on: push` → só `workflow_dispatch` até a parte 3 | apagar |
| Lifecycle ECR | manter as **últimas 10 imagens** (`imageCountMoreThan`) | — |
| JWT dev | `Jwt:Key` sai do `appsettings.json`; fica só no `appsettings.Development.json` (marcado "só dev local"); docker-compose já usa `JWT__KEY: ${JWT_KEY}` | — |
| Imagens desta parte | build/push **manual, uma vez**, da máquina do Daniel (Docker + `NUGET_AUTH_TOKEN` via `--secret`) | workflow de build antecipado |

## Componentes

### `fcg-orchestration/k8s/eks/`

```
kustomization.yaml     namespace fcgames; lista os recursos; ConfigMap gerado (configMapGenerator)
config.env             variáveis comuns não sensíveis (fonte do ConfigMap fcg-config)
users-api.yaml         Deployment + Service
catalog-api.yaml       Deployment (api + worker) + Service
payments-api.yaml      Deployment (api + worker) + Service
redis.yaml             Deployment + Service
ingress.yaml           Ingress ALB com as rotas
```

**Ingress (`ingressClassName: alb`, `scheme: internet-facing`, `target-type: ip`,
healthcheck `/health`):**

| Path (Prefix) | Service:porta |
|---|---|
| `/usuarios` | `users-api:80` → 5001 |
| `/jogos`, `/compras`, `/biblioteca`, `/desejos` | `catalog-api:80` → 5002 |
| `/pagamentos` | `payments-api:80` → 5003 |

Cada Service tem target group próprio no ALB, então o healthcheck `/health` de cada um bate no
pod certo.

**Configuração dos containers:**

| Variável | Origem | users | catalog api | catalog worker | payments api | payments worker |
|---|---|---|---|---|---|---|
| `ASPNETCORE_ENVIRONMENT=Production` | ConfigMap | ✓ | ✓ | ✓ (a imagem do worker já define `DOTNET_ENVIRONMENT=Production`) | ✓ | ✓ (idem) |
| `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` | ConfigMap | ✓ | ✓ | ✓ | ✓ | ✓ |
| `Messaging__Provider=Sqs`, `AWS__Region=sa-east-1` | ConfigMap | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ASPNETCORE_URLS=http://+:<porta>` | inline | 5001 | 5002 | — | 5003 | — |
| `ConnectionStrings__DefaultConnection` | inline | `Data Source=/data/users.db` | `Data Source=/data/catalog.db` | idem catalog | `Data Source=/data/payments.db` | idem payments |
| `JWT__KEY` | Secret `fcg-jwt` / `jwt-key` | ✓ | ✓ | — | ✓ | — |
| `JWT__ISSUER=AppFiapFcGames` | ConfigMap | ✓ | ✓ | — | ✓ | — |
| `DynamoDb__Region=sa-east-1`, `DynamoDb__ServiceUrl=""` | inline | — | ✓ | ✓ | — | — |
| `ConnectionStrings__Redis=redis:6379` | inline | — | ✓ | — | — | — |

Credenciais AWS: nenhuma variável — vêm da ServiceAccount via Pod Identity.

**Recursos e probes:**

| Container | requests (mem/cpu) | limits (mem) | probes |
|---|---|---|---|
| APIs | 128Mi / 50m | 384Mi | readiness `/health`, liveness `/health/live` (initialDelay 20s) |
| Workers | 96Mi / 25m | 256Mi | nenhuma (sem HTTP) |
| Redis | 32Mi / 10m | 64Mi | tcp 6379 |

Total requisitado ≈ 600Mi para ~1,6 GB livres nos 2 nodes.

**Estratégia:** `replicas: 1`, `RollingUpdate` `maxSurge: 1`, `maxUnavailable: 0` — o pod novo
só recebe tráfego quando a readiness passa; o antigo sai depois. `imagePullPolicy: Always`
(tag `:latest` mutável).

### `fcg-orchestration/scripts/eks-up.sh`

Depois do Terraform: `kubectl apply -k k8s/eks`, `kubectl rollout status` dos 3 deployments
(timeout 5 min cada), imprime `http://<hostname do ALB>` (espera até 5 min o Ingress ganhar
endereço). `eks-down.sh` não muda.

### Repositórios de serviço (`fcg-users-api`, `fcg-catalog-api`, `fcg-payments-api`)

Um PR por repo, branch `feature/eks-migration`:

1. `infra/ecs.tf`, `infra/api_gateway.tf` e `.aws/task-definition.json` removidos; outputs/variáveis
   que só serviam a eles removidos; `terraform plan` deve mostrar **apenas** destruições de
   recursos ECS/API Gateway/IAM/SG/log group — **nenhum** `aws_ecr_*`. Depois `terraform apply`.
2. `infra/ecr.tf`: lifecycle `imageCountMoreThan = 10`, descrição corrigida.
3. `.github/workflows/deploy-on-pr-merge.yml`: gatilho só `workflow_dispatch` + comentário
   "desativado — ECS removido; pipeline EKS chega na parte 3".
4. `appsettings.json` da Api (users/catalog/payments): remove `Jwt:Key`, mantém `Jwt:Issuer`.
   `appsettings.Development.json` mantém a chave com comentário "só dev local".
   `dotnet build` precisa continuar passando.

### Imagens (uma vez)

| Repo ECR | Tags | Dockerfile |
|---|---|---|
| `fcg-users-service` | `<sha>`, `latest` | `fcg-users-api/Dockerfile` |
| `fcg-catalog-service` | `<sha>`, `latest` / `worker-<sha>`, `worker-latest` | `Dockerfile` / `Dockerfile.worker` |
| `fcg-payments-service` | `<sha>`, `latest` / `worker-<sha>`, `worker-latest` | `Dockerfile` / `Dockerfile.worker` |

`<sha>` = commit curto do repo do serviço no momento do build. Build com
`--platform linux/amd64 --secret id=GITHUB_TOKEN,env=NUGET_AUTH_TOKEN` (o token nunca aparece
em log/arquivo). Login via `aws ecr get-login-password`.

## Validação

Sem custo:
- `kubectl kustomize k8s/eks` renderiza sem erro.
- `terraform plan` de cada serviço: só ECS/API Gateway/IAM/SG/log group a destruir, nenhum ECR.
- `dotnet build` dos 3 serviços passa sem `Jwt:Key` no `appsettings.json`.
- ECR: 5 imagens com `:<sha>` e `:latest` (`worker-*` para os workers).

Ciclo real (~45 min, ~US$ 0,20 dos créditos):
1. `eks-up.sh` sobe cluster + serviços e imprime a URL do ALB.
2. `kubectl get pods -n fcgames`: users 1/1, catalog 2/2, payments 2/2, redis 1/1 `Running`,
   sem restart em loop (≤ 1 restart do worker é aceitável — corrida de migração).
3. Fluxo pelo ALB (`fcgames.aws.http` com a URL nova):
   - `POST /usuarios/login` (admin seed) → JWT;
   - `POST /usuarios` → `GET /biblioteca/{id}` mostra biblioteca vazia (evento via SNS/SQS);
   - compra de jogo com preço ≤ 100 → pedido **Aprovado** + jogo na biblioteca;
   - compra de jogo com preço > 100 → pedido **Rejeitado**;
   - `GET /pagamentos/{orderId}` mostra o status.
4. Rolling update: loop de `curl` (1 req/s) em `POST /usuarios/login` com o admin seed durante
   `kubectl rollout restart deploy/users-api -n fcgames` → nenhuma resposta 5xx/erro de conexão
   (o pod novo recria o seed admin no SQLite efêmero antes de ficar ready).
5. `eks-down.sh` → mesmas checagens de limpeza da parte 1.

## Definição de pronto

- Os 5 passos do ciclo real passam.
- PR no `fcg-orchestration` (k8s/eks + eks-up.sh + README) e PR em cada serviço (ECS removido,
  lifecycle, workflow desarmado, JWT fora do appsettings).
- ECS efetivamente destruído na AWS, ECR preservado.
- `CLAUDE.md` atualizado.

## Fora do escopo

HPA; pipeline de build/teste/Trivy/push/rollout e botão liga/desliga no GitHub Actions (parte 3);
OpenSearch/`/search` (outra pessoa do time — a rota entra no Ingress quando existir);
Notifications (já é Lambda); Swagger público.
