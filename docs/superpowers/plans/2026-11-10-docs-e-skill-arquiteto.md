# Docs simples + skill `fcg-arquiteto` + Graphify — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deixar as docs commitadas de todos os repositórios simples e corretas (um PR por repo), criar a skill `fcg-arquiteto` com grafo curado e ligar o Graphify ao agente.

**Architecture:** Cada repositório é auditado contra a própria `origin/main` (código, appsettings, manifests, Terraform, workflows) e reescrito no padrão do spec. Um verificador local (`check_docs.py`, descartável, fora dos repos) funciona como "teste" de cada PR. A skill vive no `fcg-orchestration` e é validada por um verificador do grafo e por perguntas reais. O Graphify roda na raiz do workspace e é exposto como MCP.

**Tech Stack:** Markdown, YAML, Python 3.14 (verificadores), git/gh, Graphify 0.9.106.

**Spec:** `docs/superpowers/specs/2026-11-10-docs-e-skill-arquiteto-design.md`

## Global Constraints

- Nenhum valor de senha, chave ou token em nenhum arquivo (docs, `.http`, skill, grafo). Dizer **onde** o segredo fica, nunca o valor.
- Uma fonte por fato: endpoints no README do serviço; eventos no `fcg-integration-events`; infra EKS no `fcg-orchestration`. Os demais arquivos linkam.
- Sem histórico de fases antigas; só o que vale hoje. Troubleshooting: no máximo 4 itens de 1 linha.
- Português no texto; nomes de código como estão.
- Tudo conferido contra `origin/main`; fatos de AWS por comando só de leitura (o cluster fica desligado: o que só existe com ele ligado é conferido nos manifests/Terraform).
- Trabalho em worktree limpo a partir de `origin/main` (caminho curto no scratchpad); nunca mexer nos checkouts do usuário (`fcg-orchestration` e `fcg-observabilidade-service` têm alterações locais).
- Um PR por repositório; o usuário mescla. Commits e PRs sem linhas de atribuição.

## Review Focus

1. README cita rota ou variável de ambiente que não existe no código → o verificador falha (Task 1, checks `rotas` e `envs`).
2. Link quebrado depois de mover/remover arquivo (ex.: `API-REFERENCE.md`), inclusive link para outro repo → o verificador falha (check `links`).
3. Segredo vazando em doc, skill ou grafo → o verificador falha (check `segredos`), rodado também na pasta da skill.
4. Aresta do `grafo.yaml` apontando para nó inexistente ou com relação fora da lista → `check_grafo.py` falha (Task 9).
5. Skill responde URL fixa do ALB (muda a cada Ligar) → pergunta de teste exige a resposta "a URL sai no resumo do Ligar / `kubectl get ingress`" (Task 10).

---

### Task 1: Verificador de docs

**Files:**
- Create: `<scratchpad>/check_docs.py` (descartável, não vai para repo)

**Interfaces:**
- Produces: `python check_docs.py <raiz-do-worktree> [--repos-dir C:/GIT/FIAP/FIAP-POS-TECH-TEAM-10]` → imprime uma linha por falha (`[segredos|links|rotas|envs] arquivo:linha: motivo`) e sai com código 1 se houver falha, 0 se não.

Checks:
- `segredos`: regex sobre todos os `.md`, `.http`, `.yaml`, `.yml`, `.json` versionados: `Admin@1[2]3`, `Chave[S]egred[o]`, `guest/guest`, `ghp_[A-Za-z0-9]{20,}`, `AKIA[0-9A-Z]{16}`, `"senha"\s*:\s*"[^{"]` (senha literal em `.http`/JSON).
- `links`: todo link Markdown relativo resolve para arquivo existente; link `https://github.com/FIAP-POS-TECH-TEAM-10/<repo>/(blob|tree)/main/<path>` resolve para `<path>` existente na `origin/main` do repo local correspondente (mapa nome-no-GitHub → pasta: `fcg-users-service→fcg-users-api`, `fcg-catalog-service→fcg-catalog-api`, `fcg-payments-service→fcg-payments-api`, `fcg-notifications-service→fcg-notifications-api`, demais iguais).
- `rotas`: em README de serviço, cada linha de tabela no formato `` | `MÉTODO /caminho` | `` tem o 1º segmento do caminho presente como `[Route("<segmento>")]` em algum `.cs` do repo (`/health` e `/metrics` são liberados).
- `envs`: cada variável em tabela `` | `NOME__COM__DUPLO` | `` existe no repo como a chave correspondente (`A__B` ↔ `"A": { "B"` em `appsettings*.json`, ou `A:B`/`"A__B"`/`A__B` em `.cs`, `.yaml`, `.yml`, `docker-compose.yml` do orchestration).

- [ ] **Step 1:** Criar um worktree de teste com um README falso contendo `Admin@1[2]3` (escrito literal no arquivo de teste), um link para `nao-existe.md`, a linha `` | `GET /inexistente` | `` e `` | `NAO__EXISTE` | ``.
- [ ] **Step 2:** Rodar `python check_docs.py <teste>` → Expected: 4 falhas, uma de cada check, saída 1.
- [ ] **Step 3:** Implementar os 4 checks.
- [ ] **Step 4:** Rodar no `origin/main` atual de users → registrar as falhas de hoje (linha de base da Task 3); rodar no README de teste → 4 falhas; num README correto → 0 falhas, saída 0.

### Task 2: `fcg-integration-events`

**Files:** Modify: `README.md`

- [ ] **Step 1:** Rodar o verificador → registrar falhas.
- [ ] **Step 2:** Reescrever no padrão: os 3 eventos com os campos exatos de `src/FCGames.IntegrationEvents/Events/*.cs`, quem publica/consome cada um, como consumir (`nuget.config` + `NUGET_AUTH_TOKEN` com PAT `read:packages`, sem valor), versionamento (preview na `main`, estável por tag `v*`) conferido no workflow de publicação.
- [ ] **Step 3:** Verificador → 0 falhas; conferir campos com `git show origin/main:<arquivo>` de cada evento.
- [ ] **Step 4:** Commit, push, PR "docs: README simples e conferido".

### Task 3: `fcg-users-service`

**Files:** Modify: `README.md`, `k8s/README.md`, `app/src/Fiap.FCGames.Users.Api/Fiap.FCGames.Users.Api.http`

- [ ] **Step 1:** Verificador → linha de base.
- [ ] **Step 2:** README no padrão: endpoints do `UsuariosController` (rota, verbo, auth: anônimo/autenticado/Admin conferido nos atributos), `/health`, `/health/live`, `/metrics`; variáveis (`JWT__KEY`, `JWT__ISSUER`, `ADMIN__PASSWORD`, `ConnectionStrings__DefaultConnection`, `Messaging__Provider`, `RabbitMQ__*`) conferidas no código; local (compose do orchestration ou `dotnet run`); AWS (pod `users-api` no EKS, imagem no ECR `fcg-users-service`, pipeline `ci-cd.yml`).
- [ ] **Step 3:** `k8s/README.md` reduzido ao caminho Kind (criar Secret → aplicar manifestos sem o `secret.yaml` → testar). `.http` só com requisições que existem.
- [ ] **Step 4:** Verificador → 0 falhas.
- [ ] **Step 5:** Commit, push, PR.

### Task 4: `fcg-catalog-service`

**Files:** Modify: `README.md`, `k8s/README.md`, `app/src/Fiap.FCGames.Catalogo.Api/dotnet.teste.http`

- [ ] **Step 1:** Verificador → linha de base.
- [ ] **Step 2:** README: endpoints de `jogos`, `compras`, `biblioteca`, `desejos` (conferidos nos controllers), API + worker (consumers e filas conferidos no código), DynamoDB (tabelas `Jogos`, `Desejos`), Redis, SQLite; variáveis conferidas; AWS (pod com 2 containers, ECR `fcg-catalog-service` com tags `worker-*`).
- [ ] **Step 3:** `k8s/README.md` (Kind, curto); `.http` atualizado ou removido se não servir mais (decidir pelo conteúdo: se só repete o `fcgames.http` do orchestration, remover).
- [ ] **Step 4:** Verificador → 0 falhas.
- [ ] **Step 5:** Commit, push, PR.

### Task 5: `fcg-payments-service`

**Files:** Modify: `README.md`, `k8s/README.md`, `app/src/Fiap.FCGames.Payments.Api/dotnet.teste.http`

- [ ] **Step 1:** Verificador → linha de base.
- [ ] **Step 2:** README: `GET /pagamentos/{orderId}`, worker e a regra de aprovação (Preço ≤ 0 → "Valor inválido"; Preço > 100 → "Limite de crédito excedido"; demais → Aprovado) conferida no consumer; idempotência por `PedidoId`; variáveis; AWS.
- [ ] **Step 3:** `k8s/README.md` e `.http` como na Task 4.
- [ ] **Step 4:** Verificador → 0 falhas.
- [ ] **Step 5:** Commit, push, PR.

### Task 6: `fcg-notifications-service` (worker) e `fcg-notifications-lambda`

**Files:** Modify: `fcg-notifications-api/README.md`, `fcg-notifications-api/k8s/README.md`, `fcg-notifications-lambda/README.md`

- [ ] **Step 1:** Verificador nos dois → linha de base.
- [ ] **Step 2:** Worker: "notificações no `docker-compose` local (RabbitMQ); na AWS quem notifica é a Lambda" em uma linha; consumers, filas e formato do log conferidos no código; sem "Fase 2" no título.
- [ ] **Step 3:** Lambda: o que dispara (fila SQS, nome conferido em `infra/sqs.tf`), o que loga, como ver os logs (CloudWatch da função `fiap-fcgames-notifications-lambda`), deploy (workflows conferidos), variáveis.
- [ ] **Step 4:** Verificador → 0 falhas nos dois.
- [ ] **Step 5:** Commit, push, um PR em cada repo.

### Task 7: `fcg-observabilidade-service`

- [ ] **Step 1:** Ler o README da `origin/main`; se aponta corretamente para `fcg-orchestration/k8s/eks/observability` e o verificador dá 0, **não abrir PR** (registrar "sem mudança"). Senão, corrigir e abrir PR.

### Task 8: `fcg-orchestration` (docs)

**Files:**
- Modify: `README.md`, `infra/eks/README.md`, `infra/github-ci/README.md`, `k8s/README.md`, `k8s/eks/README.md`, `fcgames.http`, `fcgames.eks.http`, `fcgames.aws.http`, `docs/ADR-001-convencao-nomenclatura.md`, `docs/ADR-002-notifications-projeto-unico.md` (só se houver erro)
- Modify or Delete: `docs/API-REFERENCE.md`
- Create: o spec e este plano (já no worktree `docs/spec-docs-e-skill`)

- [ ] **Step 1:** Verificador → linha de base.
- [ ] **Step 2:** README: o que tem no repo; ligar/desligar/testar o EKS (botões, `eks-up.sh`, `eks-e2e.sh`, cron 03:00); subir local (`docker compose up` + `.env` a partir de `.env.example`); links para cada serviço e para a skill.
- [ ] **Step 3:** `API-REFERENCE.md` → índice curto (link para o README de cada serviço e para o pacote de eventos). Atualizar todo link que apontava para ele (inclusive nos outros repos já tratados: rodar o verificador neles de novo).
- [ ] **Step 4:** `infra/eks/README.md`, `infra/github-ci/README.md`, `k8s/eks/README.md` conferidos com os `.tf`/manifests; `k8s/README.md` (Kind) reduzido; `.http`: `fcgames.aws.http` aponta para o ambiente ECS destruído → remover ou reapontar para o EKS (se `fcgames.eks.http` já cobre, remover).
- [ ] **Step 5:** Verificador → 0 falhas.
- [ ] **Step 6:** Commit (docs + spec + plano), push, PR.

### Task 9: Skill `fcg-arquiteto`

**Files (no worktree do orchestration, branch nova `feat/skill-fcg-arquiteto` a partir da `main` já com a Task 8 mesclada):**
- Create: `.claude/skills/fcg-arquiteto/SKILL.md`, `.claude/skills/fcg-arquiteto/grafo.yaml`, `.claude/skills/fcg-arquiteto/references/{visao-geral,users,catalog,payments,notifications,mensageria,infra-aws-eks,cicd,seguranca,observabilidade,acesso,operacao,decisoes,pendencias,atualizar}.md`
- Create: `<scratchpad>/check_grafo.py` (descartável)

**Interfaces:**
- `grafo.yaml`: `nos: [{id, tipo, descricao, onde, fonte}]`, `arestas: [{de, para, relacao}]`; `tipo` ∈ {servico, evento, fila, topico, tabela, recurso-aws, repositorio, pipeline}; `relacao` ∈ {publica, consome, chama, le, grava, roda-em, acessa-via, publica-imagem-em}.
- `check_grafo.py <grafo.yaml>` → falha se: id duplicado, aresta com nó inexistente, `tipo`/`relacao` fora da lista, nó sem `fonte`.
- `SKILL.md` frontmatter: `name: fcg-arquiteto`; `description` em português dizendo quando usar (perguntas sobre arquitetura, comunicação entre serviços, infra AWS/EKS, como acessar recursos, CI/CD, segredos, pendências do FCGames).

- [ ] **Step 1:** Criar `check_grafo.py` e um `grafo.yaml` de teste com 1 aresta para nó inexistente → Expected: falha.
- [ ] **Step 2:** Escrever `grafo.yaml` a partir das docs da Task 2–8 (serviços, 3 eventos, tópicos SNS, filas SQS/RabbitMQ, tabelas, recursos AWS, repositórios, pipelines) → `check_grafo.py` → 0 falhas.
- [ ] **Step 3:** Escrever `SKILL.md` (sumário dos módulos + regras do spec: citar fonte, conferir antes de afirmar comando/URL, nunca mostrar segredo, usar Graphify para perguntas de código) e as referências, cada uma com "verificado em 2026-11-xx" e links de fonte; `visao-geral.md` com o diagrama Mermaid.
- [ ] **Step 4:** `check_docs.py` na pasta da skill → 0 falhas (segredos e links).
- [ ] **Step 5:** Commit; PR só depois da Task 10.

### Task 10: Teste da skill

- [ ] **Step 1:** Para cada pergunta abaixo, responder usando só a skill e conferir a resposta na fonte; anotar acerto/erro:
  1. Como o catalog sabe que o pagamento foi aprovado?
  2. O que acontece, passo a passo, depois de um `POST /compras` de um jogo de R$ 150?
  3. Onde fica a senha do admin e como ela chega ao pod?
  4. Qual é a URL da API? (esperado: sai no resumo do Ligar / `kubectl get ingress -n fcgames`; não pode citar DNS fixo)
  5. Como vejo os logs da notificação na AWS?
  6. Como entro no Grafana como admin?
  7. Quem pode ligar o cluster e o que acontece se ninguém desligar?
  8. Em que tabela ficam os jogos e por que eles sobrevivem ao desligar?
  9. Como faço deploy de uma mudança no users?
  10. O que falta para a entrega?
- [ ] **Step 2:** Corrigir as referências onde houve erro; repetir só as perguntas que falharam → 10/10.
- [ ] **Step 3:** Push e PR da skill.

### Task 11: Graphify

**Files:** Create (local, não versionado): `C:/GIT/FIAP/FIAP-POS-TECH-TEAM-10/.graphifyignore`, `.../graphify-out/`

- [ ] **Step 1:** Confirmar no pacote instalado o nome e o formato do arquivo de ignore; criar com `bin/`, `obj/`, `.terraform/`, `node_modules/`, `docs/superpowers/`, `graphify-out/`, `*.db*`.
- [ ] **Step 2:** Rodar `/graphify .` na raiz do workspace (depois das Tasks 2–9 mescladas e checkouts na `main`) → Expected: `graphify-out/graph.json` e `GRAPH_REPORT.md` gerados.
- [ ] **Step 3:** Conferir 3 consultas: `explain "PagamentoProcessadoEventoConsumer"`, `path` entre o controller de compras e o consumer do payments, `query "onde o catalog grava a biblioteca"` → respostas batem com o código.
- [ ] **Step 4:** Registrar o MCP do Graphify para o workspace (escopo local, comando `python -m graphify.serve <raiz>/graphify-out/graph.json`, conferido no pacote) e confirmar que as ferramentas aparecem numa sessão nova.
- [ ] **Step 5:** Documentar em `references/atualizar.md` da skill como (re)gerar o grafo e religar o MCP (PR pequeno se a Task 10 já tiver sido mesclada).

### Task 12: CLAUDE.md da raiz (só com o ok do usuário)

- [ ] **Step 1:** Propor ao usuário a versão enxuta (visão geral curta + "use a skill `fcg-arquiteto`" + regras de trabalho); aplicar só se aprovada.
