# Fase 4 — Parte 3a: Pipeline CI/CD dos serviços (design)

**Data:** 2026-10-08
**Responsável:** Daniel
**Status:** aprovado no brainstorming, aguardando plano de implementação
**Depende de:** parte 1 (cluster `fcg-eks`) e parte 2 (serviços em `k8s/eks`) — ambas mergeadas na `main`.

## Contexto

O PDF da Fase 4 exige CI/CD (GitHub Actions) cobrindo no mínimo UsersAPI e CatalogAPI, com:
Build & Test (testes unitários), containerização com tags, Security Scan (desejável), push para o
registry da cloud e deploy sem downtime (rolling update) no Kubernetes. O vídeo pede um
**live deploy**: alterar código, dar push e mostrar a pipeline atualizando produção.

A parte 3 foi dividida:
- **3a (este documento):** pipeline dos serviços users, catalog e payments.
- **3b (futuro, opcional):** ligar/desligar o cluster pelo GitHub (exige role IAM mais poderosa).

### Situação de partida

- Workflows antigos: `deploy-on-pr-merge.yml` (ECS — desarmado na parte 2, só `workflow_dispatch`)
  e `terraform-pr-develop.yml` (plan do ECR em PR para `develop`).
- Secret `PAT_PACKAGES` (`read:packages`, para o pacote `FCGames.IntegrationEvents`) atualizado em
  2026-10-08 em users, catalog e payments.
- Role OIDC `GitHubActions-ECS-Deploy-Role`: trust `repo:FIAP-POS-TECH-TEAM-10/*`; já tem push no ECR.
  `eks:DescribeCluster` hoje vem de uma inline policy criada pelo Terraform do cluster (`infra/eks`),
  que é destruída junto com o cluster.
- Access entry da role no cluster (AmazonEKSEditPolicy no namespace `fcgames`) criado pelo Terraform
  do cluster a cada `eks-up`.
- Repos **públicos** → code scanning (aba Security) gratuito.
- **Nenhum serviço tem testes unitários.**

## Decisões

| Tema | Decisão | Alternativas descartadas |
|---|---|---|
| Escopo | users, catalog **e payments** | só users + catalog (mínimo do PDF) |
| Organização | **um `ci-cd.yml` completo em cada repo** (substitui `deploy-on-pr-merge.yml`) | reusable workflow no orchestration; composite action (acesso cross-repo, pipeline "escondido") |
| Testes | etapa `dotnet test` presente; **sem criar testes agora** (passa vazio) | criar testes nesta parte |
| Trivy | **só reporta** (resumo do run + SARIF na aba Security), não bloqueia | bloquear CRITICAL; bloquear CRITICAL+HIGH |
| Cluster desligado | deploy **pulado com aviso**, run verde; imagem `:latest` entra no próximo `eks-up` | falhar; ligar o cluster no pipeline |
| `eks:DescribeCluster` | policy **permanente** em `infra/github-ci/` (novo, nunca destruído); removida de `infra/eks` | manter no Terraform do cluster (AccessDenied com cluster desligado) |
| Deploy | `kubectl set image …:<sha>` + `kubectl rollout status` (rolling update da parte 2) | `kubectl apply -k` (manifests ficam no orchestration) |

### Pendência registrada (fora do escopo, obrigatória para a entrega)

O PDF exige **execução de testes unitários automatizados** ao menos em users e catalog. O pipeline já
roda `dotnet test` na solution: basta alguém criar `tests/Fiap.FCGames.{Serviço}.Tests` (xUnit) e
adicioná-lo à `.slnx` que os testes passam a rodar sem mudar o workflow. Sugestões levantadas:
validators e login/token (users); RealizarCompra e transições de Pedido (catalog); regra de
aprovação (payments — exige extrair a regra do consumer para uma classe testável).

## Componentes

### `.github/workflows/ci-cd.yml` (users, catalog, payments)

**Gatilhos:** `pull_request` → `main`; `push` → `main`; `workflow_dispatch`.

**Permissões:** `id-token: write`, `contents: read`, `security-events: write`.

**Concorrência:** `group: ci-cd-${{ github.ref }}`; `cancel-in-progress` só para PRs
(`${{ github.event_name == 'pull_request' }}`) — na `main` os deploys entram em fila.

**Variáveis (env do workflow):**

| Variável | users | catalog | payments |
|---|---|---|---|
| `ECR_REPOSITORY` | `fcg-users-service` | `fcg-catalog-service` | `fcg-payments-service` |
| `DEPLOYMENT` | `users-api` | `catalog-api` | `payments-api` |
| `SOLUTION` | `app/src/Fiap.FCGames.Users.slnx` | `app/src/Fiap.FCGames.Catalogo.Api.slnx` | `app/src/Fiap.FCGames.Payments.Api.slnx` |
| worker | — | `Dockerfile.worker` → tag `worker-*`, container `worker` | idem |

Comuns: `AWS_REGION=sa-east-1`, `ROLE_TO_ASSUME=arn:aws:iam::915153720516:role/GitHubActions-ECS-Deploy-Role`,
`EKS_CLUSTER=fcg-eks`, `K8S_NAMESPACE=fcgames`.

**Job `build-test`** (todos os gatilhos):
1. checkout; `actions/setup-dotnet` (10.0.x).
2. `dotnet restore $SOLUTION` com `NUGET_AUTH_TOKEN: ${{ secrets.PAT_PACKAGES }}`.
3. `dotnet build --no-restore -c Release`.
4. `dotnet test --no-build -c Release` (sem projetos de teste → passa).

**Job `image`** (needs build-test; todos os gatilhos):
1. `docker build` da API (e do worker em catalog/payments) com
   `--secret id=GITHUB_TOKEN,env=NUGET_AUTH_TOKEN` (token do `PAT_PACKAGES`), tags
   `$REGISTRY/$ECR_REPOSITORY:${{ github.sha }}` e `:latest` (worker: `worker-<sha>`, `worker-latest`).
   Nos PRs o registry é um nome local (sem login na AWS).
2. Trivy (`aquasecurity/trivy-action`) em cada imagem, `severity: CRITICAL,HIGH`, `exit-code: 0`:
   - formato `table` → anexado ao `$GITHUB_STEP_SUMMARY`;
   - formato `sarif` → `github/codeql-action/upload-sarif` (categoria por imagem).
3. **Só em `push`/`workflow_dispatch`:** OIDC (`aws-actions/configure-aws-credentials`), login no
   ECR (`aws-actions/amazon-ecr-login`), `docker push` das 2 (ou 4) tags.
4. Output `image_tag=${{ github.sha }}`.

**Job `deploy`** (needs image; só `push`/`workflow_dispatch`):
1. OIDC com a mesma role.
2. `aws eks describe-cluster --name fcg-eks`:
   - `ResourceNotFoundException` → escreve no resumo "⏭️ deploy pulado: cluster fcg-eks
     desligado — a imagem `:latest` entra no próximo `eks-up`" e termina com sucesso;
   - outro erro → falha;
   - sucesso → segue.
3. `aws eks update-kubeconfig`; `kubectl set image deploy/$DEPLOYMENT api=<img>:<sha>`
   (+ `worker=<img>:worker-<sha>`) `-n fcgames`; `kubectl rollout status --timeout=600s`.
4. Resumo: imagem implantada, `kubectl get pods -n fcgames -l app=$DEPLOYMENT`.

Ações de terceiros fixadas por versão maior (`@v4` etc.); `kubectl` vem pré-instalado no
`ubuntu-latest`.

Removido: `.github/workflows/deploy-on-pr-merge.yml`. Mantido: `terraform-pr-develop.yml`.

### `fcg-orchestration/infra/github-ci/` (novo, permanente)

Terraform mínimo, state `s3://fiap-tech-challenge-tfstate-123456-915153720516-sa-east-1-an/github-ci/terraform.tfstate`
(mesma tabela de lock). Um recurso: `aws_iam_role_policy` `fcg-github-eks-describe` na role
`GitHubActions-ECS-Deploy-Role` com `eks:DescribeCluster` em
`arn:aws:eks:sa-east-1:915153720516:cluster/fcg-eks`. **Nunca** destruído pelos scripts liga/desliga.

`infra/eks/eks.tf`: remove `aws_iam_role_policy.github_deploy_eks` (passa a ser do github-ci).
Ordem: aplicar `infra/github-ci` **antes** de remover do `infra/eks` (o `infra/eks` não tem state
ativo com o cluster desligado — a remoção só afeta o próximo `eks-up`).

### Documentação

- README de cada serviço: seção "Pipeline (CI/CD)" — gatilhos, jobs, comportamento com cluster
  desligado, onde ver o Trivy, como fazer o live deploy.
- `CLAUDE.md`: seção da Fase 4 parte 3a.

## Validação

Sem custo:
- `actionlint` (via `docker run rhysd/actionlint`) nos 3 workflows.
- `terraform validate` + `plan` em `infra/github-ci` e `validate` em `infra/eks`.
- PR real em cada serviço: run verde em `build-test` e `image`, tabela Trivy no resumo, SARIF na aba
  Security, **sem** push no ECR e **sem** job `deploy`.
- Merge com cluster desligado: imagens `:<sha>`/`:latest` no ECR, `deploy` "pulado", run verde.

Ciclo real (~45 min, ~US$ 0,20 dos créditos — com confirmação do usuário):
1. `eks-up.sh`.
2. `workflow_dispatch` do `ci-cd` no users → `deploy` roda, rollout OK, pod com imagem `:<sha>`.
3. Ensaio do live deploy: mudança pequena e visível no users (ex.: campo de versão no `/health`
   ou log de startup) → push na `main` → pipeline atualiza o pod; loop de `curl` durante o
   rollout sem erros.
4. `eks-e2e.sh` continua passando.
5. `eks-down.sh`.

## Definição de pronto

- `ci-cd.yml` mergeado e verde nos 3 serviços; `deploy-on-pr-merge.yml` removido.
- `infra/github-ci` aplicado; policy removida do `infra/eks`.
- Ciclo real passou (inclui o ensaio do live deploy).
- READMEs e `CLAUDE.md` atualizados; pendência dos testes registrada.

## Fora do escopo

Criar testes unitários (pendência acima); ligar/desligar o cluster pelo GitHub (parte 3b);
Trivy bloqueante; notifications (Lambda, pipeline próprio); restringir o trust da role OIDC por
repo/branch.
