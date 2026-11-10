# fcg-orchestration

Infraestrutura e roteiros do FCGames: o `docker-compose` da stack local, o cluster EKS da AWS
(Terraform + manifests + botões de ligar/desligar) e os arquivos `.http` de teste.

## O que tem aqui

| Pasta / arquivo | O que é |
|---|---|
| `docker-compose.yml` · `.env.example` | stack local: RabbitMQ, DynamoDB local, as APIs e os workers |
| `infra/eks/` | Terraform do cluster `fcg-eks` (liga e desliga a cada sessão) — [README](infra/eks/README.md) |
| `infra/github-ci/` | permissões permanentes do GitHub Actions na AWS — [README](infra/github-ci/README.md) |
| `k8s/eks/` | manifests dos serviços e da observabilidade no EKS — [README](k8s/eks/README.md) |
| `k8s/` | caminho antigo com Kubernetes local (Kind) — [README](k8s/README.md) |
| `scripts/` | `eks-up.sh`, `eks-down.sh`, `eks-e2e.sh` |
| `.github/workflows/` | botões **Ligar cluster EKS** e **Desligar cluster EKS** |
| `fcgames.http` · `fcgames.eks.http` | fluxo de ponta a ponta (local e EKS) |
| `docs/` | [índice das referências](docs/API-REFERENCE.md), ADRs, specs e planos |

Os serviços ficam cada um no seu repositório: `fcg-users-service`, `fcg-catalog-service`,
`fcg-payments-service`, `fcg-notifications-service`, `fcg-notifications-lambda` e
`fcg-integration-events` (contratos dos eventos).

## Rodar local (docker compose)

1. Clone os repositórios lado a lado, **com os nomes do GitHub** (o compose monta as imagens a partir
   de `../fcg-users-service`, `../fcg-catalog-service`, `../fcg-payments-service` e
   `../fcg-notifications-service`).
2. `cp .env.example .env` e preencha. Valores sem `"`, `\`, `$` nem espaço.

| Variável do `.env` | O que é |
|---|---|
| `NUGET_AUTH_TOKEN` | token do GitHub com `read:packages` (ex.: `gh auth token`) |
| `JWT_KEY` | chave do JWT, a mesma para todos os serviços (32+ caracteres) |
| `RABBITMQ_USER` · `RABBITMQ_PASS` | credenciais do RabbitMQ local |
| `ADMIN_PASSWORD` | senha do `admin@fcgames.com` (também usada pelos `.http`) |
| `GRAFANA_PASSWORD` | senha do admin do Grafana (só para ligar o EKS pela sua máquina) |

3. Suba e teste:

```bash
docker compose up -d --build
docker compose ps                                  # tudo healthy
docker compose logs -f notifications-worker        # "e-mails" simulados
```

| Serviço | Porta local |
|---|---|
| users · catalog · payments | 5001 · 5002 · 5003 (Swagger em http://localhost:5001/swagger; catalog e payments só têm Swagger rodando em Development) |
| notifications-worker | 5004 (só `/health`) |
| RabbitMQ | 5672 · painel em http://localhost:15672 |
| DynamoDB local | 8000 |

O roteiro de teste está em [`fcgames.http`](fcgames.http) (REST Client do VS Code ou HTTP Client do
Rider): cadastro → login → jogos → compra aprovada (Hades) e rejeitada (Cyberpunk, > R$ 100) →
pedido → pagamento → biblioteca. `docker compose down -v` zera os dados.

## Cluster EKS na AWS

O cluster `fcg-eks` **não fica ligado** (~US$ 0,20/h, sai dos créditos da conta). Pela aba
**Actions** deste repositório, qualquer pessoa com escrita:

| Workflow | O que faz |
|---|---|
| **Ligar cluster EKS** | `scripts/eks-up.sh` (~15 min): cluster, serviços, Prometheus e Grafana. Com "testar" marcado, roda o `eks-e2e.sh`. O resumo mostra a URL da API e a do Grafana (`/grafana`) |
| **Desligar cluster EKS** | `scripts/eks-down.sh` (~12 min): apaga o ALB e destrói o cluster |
| **Desligar cluster EKS** (automático) | toda noite às 03:00 (BRT), se estiver ligado |

- As senhas do admin e do Grafana vêm dos secrets `ADMIN_PASSWORD` e `GRAFANA_PASSWORD` do
  Environment `aws-eks`; quem liga não precisa saber os valores.
- Pela máquina: `./scripts/eks-up.sh` / `./scripts/eks-down.sh` (Git Bash, profile `fcg-team`, senhas
  no `.env`). Script e workflow ao mesmo tempo dão "state locked", sem dano: espere.
- Se o Ligar falhar no meio, rode o Desligar.
- O GitHub desativa agendamentos após 60 dias sem atividade no repositório: confira de vez em quando
  que o **Desligar cluster EKS** continua habilitado.
- Testar à mão: [`fcgames.eks.http`](fcgames.eks.http) com a URL do ALB do resumo.

## Problemas comuns

| Sintoma | Solução |
|---|---|
| Build falha no `dotnet restore` (401) | `NUGET_AUTH_TOKEN` vencido: `gh auth refresh -s read:packages` e use `gh auth token` |
| `401` nos endpoints | `JWT_KEY` diferente entre serviços, ou token vencido: faça login de novo |
| Compose não acha os serviços | pastas clonadas com outro nome (ver "Rodar local", passo 1) |
| 502/503 logo depois de ligar o EKS | o ALB leva 1–3 min para registrar os pods |
