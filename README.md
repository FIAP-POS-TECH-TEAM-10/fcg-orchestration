# fcg-orchestration

Repositório de infraestrutura do FCGames: `docker-compose`, manifests k8s,
contratos de referência e documentação. É daqui que você sobe a stack completa.

> 📐 Arquitetura geral: [`../CLAUDE.md`](../CLAUDE.md)
> 📑 Endpoints, contratos e dados: [`docs/API-REFERENCE.md`](docs/API-REFERENCE.md)
> 📋 Convenção de nomenclatura: [`docs/ADR-001-convencao-nomenclatura.md`](docs/ADR-001-convencao-nomenclatura.md)

---

## 1. Pré-requisitos

- **Docker Desktop** (com Docker Compose v2)
- **.NET 10 SDK** — só se for rodar algum serviço fora do container
- **PAT do GitHub** com scope `read:packages` — para restaurar o pacote
  `FCGames.IntegrationEvents` durante o build das imagens
- Os **5 repositórios clonados como pastas irmãs**:
  ```
  C:\GIT\FIAP\FIAP-POS-TECH-TEAM-10\
    ├── fcg-users-api
    ├── fcg-catalog-api
    ├── fcg-payments-api
    ├── fcg-notifications-api
    └── fcg-orchestration   ← você roda os comandos daqui
  ```

---

## 2. Setup (uma vez)

```bash
# a partir de fcg-orchestration/
cp .env.example .env
```

Edite o `.env` e preencha:

| Variável | O que é |
|----------|---------|
| `NUGET_AUTH_TOKEN` | PAT com `read:packages` (restaura o pacote de eventos no build) |
| `JWT_KEY` | Chave de assinatura JWT, **idêntica** nos 3 serviços (mín. 32 chars) |
| `RABBITMQ_USER` / `RABBITMQ_PASS` | Credenciais do broker (default `guest`/`guest`) |

> O `.env` **não é commitado** (está no `.gitignore`).

---

## 3. Subir a stack completa

```bash
# build + sobe tudo em background
docker compose up -d --build

# acompanhar os logs de todos os serviços
docker compose logs -f
```

A ordem de inicialização é controlada por healthcheck:
`rabbitmq` (healthy) → APIs (criam/migram o banco) → workers.

### O que sobe

| Serviço | Container | Porta | Acesso |
|---------|-----------|-------|--------|
| RabbitMQ | `fcg-rabbitmq` | 5672 / 15672 | Management UI: http://localhost:15672 |
| UsersAPI | `fcg-users-api` | 5001 | Swagger: http://localhost:5001/swagger |
| CatalogAPI | `fcg-catalog-api` | 5002 | Swagger: http://localhost:5002/swagger |
| Catalog Worker | `fcg-catalog-worker` | — | consumer (sem porta) |
| PaymentsAPI | `fcg-payments-api` | 5003 | Swagger: http://localhost:5003/swagger |
| Payments Worker | `fcg-payments-worker` | — | consumer (sem porta) |
| Notifications | `fcg-notifications-worker` | 5004 | só `/health` |

> Catalog e Payments rodam **2 containers cada** (API publisher + Worker consumer),
> compartilhando o mesmo arquivo SQLite via volume. O worker espera a API ficar
> healthy para evitar corrida de migration.

---

## 4. Verificar se está tudo no ar

```bash
docker compose ps                              # status de cada container
curl http://localhost:5001/health              # UsersAPI
curl http://localhost:5002/health              # CatalogAPI
curl http://localhost:5003/health              # PaymentsAPI
curl http://localhost:5004/health              # Notifications
```

**RabbitMQ Management UI:** http://localhost:15672 (login `guest`/`guest`)
— veja as filas sendo criadas e as mensagens passando em tempo real.

---

## 5. Testar o fluxo end-to-end

O arquivo [`fcgames.http`](fcgames.http) tem o roteiro completo (use a extensão
REST Client no VS Code ou o cliente `.http` do Rider/Visual Studio):

```
1. POST /usuarios            cria usuário  → biblioteca criada + log boas-vindas
2. POST /usuarios/login      pega o JWT
3. POST /jogos               (como Admin) cadastra um jogo
4. GET  /jogos               lista o catálogo
5. POST /compras             compra → fluxo assíncrono
6. GET  /compras/{id}        status do pedido (Aprovado/Rejeitado)
7. GET  /biblioteca/{uid}    jogo aparece na biblioteca (se Aprovado)
```

Acompanhe os logs do Notifications para ver os "e-mails":
```bash
docker compose logs -f notifications-worker
```

---

## 6. Rodar UM serviço isolado (sem Docker, para desenvolver)

Suba só o RabbitMQ no Docker e rode o serviço pelo SDK:

```bash
# só o broker
docker compose up -d rabbitmq

# em outro terminal, no repo do serviço (ex: fcg-catalog-api)
export NUGET_AUTH_TOKEN=ghp_...        # (Windows PowerShell: $env:NUGET_AUTH_TOKEN="ghp_...")
dotnet restore
dotnet run --project app/src/Fiap.FCGames.Catalogo.Api
```

> O serviço conecta no `localhost:5672`. As env vars (JWT, connection string,
> RabbitMQ) podem ir no `appsettings.Development.json` ou no ambiente.

---

## 7. Comandos úteis do dia a dia

```bash
docker compose logs -f users-api          # logs de um serviço
docker compose restart catalog-api        # reiniciar um serviço
docker compose up -d --build catalog-api  # rebuildar só um serviço

docker compose down                       # para e remove containers (mantém volumes/dados)
docker compose down -v                    # para e APAGA os volumes (banco zerado)

docker compose ps                         # status
docker volume ls                          # ver volumes de dados (prefixo fcgames_)
```

---

## 8. Deploy no Kubernetes

### Estrutura dos Manifestos

Cada microsserviço tem sua pasta `/k8s` com os manifestos Kubernetes:

```
fcg-orchestration/k8s/     ← Namespace + RabbitMQ (infraestrutura)
fcg-users-api/k8s/         ← Users API
fcg-catalog-api/k8s/       ← Catalog API + Worker
fcg-payments-api/k8s/      ← Payments API + Worker
fcg-notifications-api/k8s/ ← Notifications Worker
```

### Deploy Rápido

```bash
# A partir do diretório fcg-orchestration

# Windows PowerShell
.\k8s\deploy.ps1

# Linux/Mac
chmod +x k8s/deploy.sh
./k8s/deploy.sh
```

### Deploy Manual (passo a passo)

```bash
# 1. Buildar as imagens Docker primeiro
cd ../fcg-users-api
docker build -t fcg-users-api:latest .

cd ../fcg-catalog-api
docker build -t fcg-catalog-api:latest -f Dockerfile .
docker build -t fcg-catalog-worker:latest -f Dockerfile.worker .

cd ../fcg-payments-api
docker build -t fcg-payments-api:latest -f Dockerfile .
docker build -t fcg-payments-worker:latest -f Dockerfile.worker .

cd ../fcg-notifications-api
docker build -t fcg-notifications-worker:latest .

# 2. Aplicar manifestos em ordem
cd ../fcg-orchestration

kubectl apply -f k8s/                           # Namespace + RabbitMQ
kubectl wait --for=condition=ready pod -l app=rabbitmq -n fcgames --timeout=300s

kubectl apply -f ../fcg-users-api/k8s/          # Users API
kubectl apply -f ../fcg-catalog-api/k8s/        # Catalog API + Worker
kubectl apply -f ../fcg-payments-api/k8s/       # Payments API + Worker
kubectl apply -f ../fcg-notifications-api/k8s/  # Notifications Worker

# 3. Verificar status
kubectl get pods -n fcgames
kubectl get services -n fcgames
```

### 🌐 Acessar os Serviços (Port Forward)

```bash
# Em terminais separados:
kubectl port-forward -n fcgames svc/users-api 5001:80
kubectl port-forward -n fcgames svc/catalog-api 5002:80
kubectl port-forward -n fcgames svc/payments-api 5003:80
kubectl port-forward -n fcgames svc/rabbitmq 15672:15672
```

Agora acesse:
- http://localhost:5001/swagger - Users API
- http://localhost:5002/swagger - Catalog API
- http://localhost:5003/swagger - Payments API
- http://localhost:15672 - RabbitMQ Management

### Monitoramento

```bash
# Ver todos os pods
kubectl get pods -n fcgames

# Logs de um serviço específico
kubectl logs -n fcgames -l app=users-api -f
kubectl logs -n fcgames -l app=catalog-worker -f
kubectl logs -n fcgames -l app=notifications-worker -f

# Descrever um pod
kubectl describe pod -n fcgames <pod-name>

# Ver eventos
kubectl get events -n fcgames --sort-by='.lastTimestamp'
```

### Limpeza

```bash
# Remover tudo (namespace + todos os recursos)
kubectl delete namespace fcgames
```

## 9. Troubleshooting

| Sintoma | Causa provável | Solução |
|---------|----------------|---------|
| Build falha no `dotnet restore` | `NUGET_AUTH_TOKEN` ausente/expirado | Gerar PAT com `read:packages` e por no `.env` |
| `401` ao chamar endpoints | JWT inválido ou `JWT_KEY` diferente entre serviços | Conferir que `JWT_KEY` é idêntico no `.env` |
| Mensagem não chega no consumer | Nome/namespace do evento divergente | Eventos só do pacote `FCGames.IntegrationEvents` |
| Worker sobe antes da API | corrida de migration | Já tratado via `depends_on: condition: service_healthy` |
| Banco "sujo" entre testes | volume persistido | `docker compose down -v` para zerar |
| Porta ocupada | outro processo na 5001-5004/5672 | parar o processo ou ajustar a porta no compose |
| Pods não iniciam no K8s | Imagens não existem localmente | Buildar imagens antes do `kubectl apply` |
| Worker não consome mensagens | RabbitMQ não está healthy | Aguardar RabbitMQ inicializar completamente |

---
