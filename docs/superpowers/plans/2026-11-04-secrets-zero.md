# Zero secrets commitados + observabilidade no EKS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nenhum segredo em arquivo versionado dos repos do projeto, e Prometheus + Grafana rodando no EKS com o Grafana em `http://<alb>/grafana` (somente leitura).

**Architecture:** Duas senhas fixas (`ADMIN_PASSWORD`, `GRAFANA_PASSWORD`) vivem em secrets do GitHub Actions (Environment `aws-eks`), entram no Terraform como variáveis `sensitive` e viram K8s Secrets (`fcg-admin`, `fcg-grafana`); o app e o Grafana leem por `secretKeyRef`. Prometheus e Grafana são Deployments no `k8s/eks` (imagens oficiais, config por ConfigMap), com o Grafana numa regra `/grafana` do Ingress existente. RabbitMQ `guest` e chaves JWT de dev saem de todos os arquivos versionados e passam a vir de `.env`/env var.

**Tech Stack:** Terraform (provider kubernetes), Kustomize, Bash, GitHub Actions, .NET 10 + xUnit, AWS Load Balancer Controller.

**Spec:** `docs/superpowers/specs/2026-11-04-secrets-zero-design.md` (neste repo, `fcg-orchestration`).

## Global Constraints

- Zero literal de senha/chave em arquivo versionado (código, YAML, scripts, `.http`, docs). Placeholders óbvios (`REPLACE_ME`) são aceitos só em manifests de exemplo.
- **Não usar AWS Secrets Manager.** Zabbix sai de vez. Sem domínio/HTTPS (ALB só HTTP).
- Secrets do GitHub (Environment `aws-eks` de `fcg-orchestration`): `ADMIN_PASSWORD`, `GRAFANA_PASSWORD`. K8s Secrets no namespace `fcgames`: `fcg-admin` e `fcg-grafana`, ambos com a chave `admin-password`. Env do app: `ADMIN__PASSWORD`. Variáveis Terraform: `admin_password`, `grafana_password` (`sensitive = true`, sem default).
- Imagens: `prom/prometheus:v3.13.3`, `grafana/grafana:13.2.1`. Jobs do Prometheus: `fcg-users-service`, `fcg-catalog-service`. Grafana: caminho `/grafana`, acesso anônimo papel `Viewer`; Prometheus sem Ingress. PaymentsAPI não ganha `/metrics`.
- `main` do `fcg-orchestration` é protegida (PR obrigatório, sem aprovação exigida). Mensagens de commit/PR **sem linhas de atribuição**. Nunca imprimir valor de senha no chat/log.
- O usuário tem alteração local não commitada em `fcg-orchestration/fcgames.aws.http`; trabalhar sempre em worktree/branch limpa a partir de `origin/main` e não tocar a árvore dele.
- Merge e deploy: `fcg-orchestration` primeiro (Tasks 1-4, 8), depois `fcg-users-api` (Task 5); com cluster ligado em estado antigo não mergear o users-api.

## Review Focus

1. Senha com caracteres especiais (`"`, `$`, `!`) quebra o JSON/shell do e2e e dos `.http` → teste na Task 2 (JSON via Python) e na Task 5 (valor devolvido sem alteração).
2. `eks-down`/desligamento noturno sem as senhas reais no ambiente → Task 2 (placeholder) validado na Task 6.
3. Secret ausente ou senha vazia derruba o pod com erro legível, não semeia admin com valor padrão → Task 5 (testes) e Task 3 (sem `optional: true`).
4. Grafana atrás do ALB em sub-caminho com assets/redirect quebrados ou health check do target group falhando → Task 2 (e2e checa `/grafana/api/health` e o dashboard) e Task 6.
5. Prometheus de pé mas com os targets `down` (nome/porta de Service errados) deixa o dashboard vazio sem erro → Task 2 (e2e checa os dois targets `up`).

---

## Task 0: Publicar spec e plano

**Files:** branch `docs/secrets-zero-spec` (já existe local, a partir de `origin/main`) com os dois documentos.

- [ ] **Step 1:** `git push -u origin docs/secrets-zero-spec`, abrir PR "Design e plano: zero secrets + observabilidade no EKS" contra `main` e mergear.
- [ ] **Step 2:** Confirmar `git ls-tree origin/main docs/superpowers/specs/ docs/superpowers/plans/` lista `2026-11-04-secrets-zero-design.md` e `2026-11-04-secrets-zero.md`.

## Task 1: Terraform — variáveis e Secrets

**Files:** Modify `infra/eks/variables.tf`, `infra/eks/secrets.tf`. Branch `feature/secrets-zero` (a partir de `origin/main`, worktree limpo).

**Interfaces:**
- Produces: variáveis `admin_password`, `grafana_password` (string, sensitive); Secrets `fcg-admin` e `fcg-grafana` (chave `admin-password`) no namespace `kubernetes_namespace_v1.app` — consumidos pelas Tasks 3 e 2.

- [ ] **Step 1:** Em `variables.tf`, acrescentar `variable "admin_password"` e `variable "grafana_password"`: `type = string`, `sensitive = true`, sem `default`, com `description` dizendo de onde vem (secret do GitHub / env `TF_VAR_*`).
- [ ] **Step 2:** Em `secrets.tf`, acrescentar `kubernetes_secret_v1.admin` (`name = "fcg-admin"`) e `kubernetes_secret_v1.grafana` (`name = "fcg-grafana"`), mesmo molde do `kubernetes_secret_v1.jwt`, `data = { "admin-password" = var.<...> }`.
- [ ] **Step 3: Verificar.** `cd infra/eks && terraform init -backend=false -input=false && terraform validate && terraform fmt -check`. Esperado: `Success! The configuration is valid.` e `fmt` sem saída.
- [ ] **Step 4:** `git commit -m "terraform(eks): senhas do admin e do Grafana como variaveis sensitive e K8s Secrets"`.

## Task 2: Scripts e workflows

**Files:** Modify `scripts/eks-up.sh`, `scripts/eks-down.sh`, `scripts/eks-e2e.sh`, `.github/workflows/eks-ligar.yml`; Create `.env.example`. Mesma branch `feature/secrets-zero`.

**Interfaces:**
- Consumes: variáveis Terraform da Task 1; Deployments `prometheus` e `grafana` e Service `grafana` da Task 3.
- Produces: contrato de ambiente — `eks-up.sh` exige `ADMIN_PASSWORD` e `GRAFANA_PASSWORD`; `eks-down.sh` não exige nada; `eks-e2e.sh` usa `ADMIN_PASSWORD` (ou o Secret `fcg-admin`).

- [ ] **Step 1: `eks-up.sh`.** Logo depois dos `set`/definições e **antes de qualquer chamada AWS**: carregar `$ROOT_DIR/.env` se existir (`set -a; . "$ROOT_DIR/.env"; set +a`), exigir as duas variáveis com `${VAR:?mensagem}` (mensagem diz para exportar ou colocar no `.env`) e exportar `TF_VAR_admin_password` e `TF_VAR_grafana_password`. Incluir `prometheus grafana` na lista do `for deploy in ...`; ao final, depois da URL do ALB, `log "Grafana: http://$alb_host/grafana  (alternativa: kubectl port-forward svc/grafana 3000:80 -n fcgames)"`.
- [ ] **Step 2: Verificar falha rápida.** `bash -n scripts/eks-up.sh` e `env -u ADMIN_PASSWORD -u GRAFANA_PASSWORD AWS_PROFILE=inexistente ./scripts/eks-up.sh` (com `.env` ausente). Esperado: sai com código ≠ 0 e a mensagem cita `ADMIN_PASSWORD` (e não um erro da AWS).
- [ ] **Step 3: `eks-down.sh`.** Antes do subshell do `terraform destroy`: `export TF_VAR_admin_password="${ADMIN_PASSWORD:-destroy-placeholder}"` e idem `grafana`. `bash -n` deve passar.
- [ ] **Step 4: `eks-e2e.sh`.** (a) Resolver a senha: `ADMIN_PASSWORD` do ambiente, senão `kubectl get secret fcg-admin -n fcgames -o jsonpath='{.data.admin-password}' | base64 -d`, senão `fail`. (b) Montar o corpo do login do admin com `$PY` e `os.environ["ADMIN_PASSWORD"]` (`json.dumps`), nunca com interpolação de shell. (c) Novo passo final "9) Grafana": `GET $BASE/grafana/api/health` = 200 e `GET $BASE/grafana/api/search?query=` contém `fcgames-observability`. (d) Novo passo "10) Prometheus": até 60 s, `kubectl exec -n fcgames deploy/prometheus -- wget -qO- http://localhost:9090/api/v1/targets` contém `"job":"fcg-users-service"` e `"job":"fcg-catalog-service"` ambos com `"health":"up"`.
- [ ] **Step 5: Verificar JSON com caracteres especiais.** `ADMIN_PASSWORD='a"b$c!' python3 -c '<mesmo trecho do passo (b)>' | python3 -c 'import json,sys; assert json.load(sys.stdin)["senha"]=="a\"b$c!"'`. Esperado: sem saída e código 0. `bash -n scripts/eks-e2e.sh` passa.
- [ ] **Step 6: `eks-ligar.yml`.** No step "Ligar" acrescentar `env:` com `ADMIN_PASSWORD: ${{ secrets.ADMIN_PASSWORD }}` e `GRAFANA_PASSWORD: ${{ secrets.GRAFANA_PASSWORD }}`; no step do e2e, `env: ADMIN_PASSWORD`. No "Resumo", imprimir também `**Grafana:** http://${host}/grafana`. Verificar: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/eks-ligar.yml'))"` sem erro.
- [ ] **Step 7: `.env.example`.** Criar com as chaves `NUGET_AUTH_TOKEN`, `JWT_KEY`, `RABBITMQ_USER`, `RABBITMQ_PASS`, `ADMIN_PASSWORD`, `GRAFANA_PASSWORD`, todas **sem valor** e com um comentário de uma linha por chave. Verificar: `git check-ignore -v .env` mostra a regra `*.env`; `git check-ignore .env.example` não imprime nada.
- [ ] **Step 8:** `git commit -m "scripts/workflows(eks): senhas via ambiente, e2e valida Grafana e Prometheus"`.

## Task 3: Manifests — admin no users-api e observabilidade

**Files:** Modify `k8s/eks/users-api.yaml`, `k8s/eks/ingress.yaml`, `k8s/eks/kustomization.yaml`; Create `k8s/eks/observability/{prometheus.yaml,grafana.yaml,prometheus.yml,grafana-datasource.yml,grafana-dashboards-provider.yml,fcgames-observability.json}`. Mesma branch.

**Interfaces:**
- Consumes: Secrets `fcg-admin`, `fcg-grafana` (Task 1).
- Produces: Deployments `prometheus` e `grafana` (nomes usados por `eks-up.sh`/e2e); Service `prometheus` (porta 9090) e `grafana` (porta 80 → container 3000, porta nomeada `http`).

- [ ] **Step 1: users-api.** Em `users-api.yaml`, acrescentar ao `env` do container `api`: `ADMIN__PASSWORD` via `secretKeyRef` (`name: fcg-admin`, `key: admin-password`), **sem** `optional`.
- [ ] **Step 2: Copiar a config.** De `fcg-observabilidade-service` (`origin/develop`): `grafana/dashboards/fcgames-observability.json` → `observability/fcgames-observability.json`; `grafana/provisioning/datasources/datasource.yml` → `observability/grafana-datasource.yml`; `grafana/provisioning/dashboards/dashboards.yml` → `observability/grafana-dashboards-provider.yml` (manter `path: /etc/grafana/provisioning/dashboards-data`). Usar `git show origin/develop:<path> > <destino>`.
- [ ] **Step 3: `prometheus.yml`.** `scrape_interval: 15s`; jobs `fcg-users-service` → `users-api.fcgames.svc:80` e `fcg-catalog-service` → `catalog-api.fcgames.svc:80`, `metrics_path: /metrics`, esquema http. Comentário: payments ainda não expõe `/metrics`.
- [ ] **Step 4: `prometheus.yaml`.** Deployment (1 réplica, imagem fixada, args `--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=2d`, `emptyDir` em `/prometheus`, ConfigMap `prometheus-config` montado em `/etc/prometheus`, readiness `/-/ready`, requests ~100m/256Mi) e Service `ClusterIP` `prometheus:9090`. **Sem Ingress.**
- [ ] **Step 5: `grafana.yaml`.** Deployment (1 réplica, imagem fixada, porta nomeada `http` 3000): env `GF_SERVER_ROOT_URL=%(protocol)s://%(domain)s/grafana/`, `GF_SERVER_SERVE_FROM_SUB_PATH=true`, `GF_AUTH_ANONYMOUS_ENABLED=true`, `GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer`, `GF_SECURITY_ADMIN_USER=admin`, `GF_SECURITY_ADMIN_PASSWORD` via `secretKeyRef` (`fcg-grafana`/`admin-password`, sem `optional`), `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/provisioning/dashboards-data/fcgames-observability.json`. Três ConfigMaps montados: datasource em `/etc/grafana/provisioning/datasources`, provider em `/etc/grafana/provisioning/dashboards`, JSON em `/etc/grafana/provisioning/dashboards-data`. Readiness em `/grafana/api/health`, requests ~50m/128Mi. Service `grafana` (porta 80, `targetPort: http`) com a anotação `alb.ingress.kubernetes.io/healthcheck-path: /grafana/api/health`.
- [ ] **Step 6: Ingress.** Em `ingress.yaml`, nova regra `path: /grafana`, `pathType: Prefix`, backend `grafana` porta `http`.
- [ ] **Step 7: Kustomization.** Em `kustomization.yaml`: `resources` ganha `observability/prometheus.yaml` e `observability/grafana.yaml`; `configMapGenerator` ganha `prometheus-config` (arquivo `prometheus.yml`), `grafana-datasources` (`grafana-datasource.yml`), `grafana-dashboards-provider` (`grafana-dashboards-provider.yml`) e `grafana-dashboards` (`fcgames-observability.json`), todos a partir de `observability/`. Os nomes que os Deployments referenciam devem ser os do gerador (o sufixo de hash é reescrito pelo Kustomize).
- [ ] **Step 8: Verificar.** `kubectl kustomize k8s/eks > "$TMP/render.yaml"` sai com 0; `grep -c '^kind: Deployment' "$TMP/render.yaml"` = `6`; `grep -n 'name: fcg-admin' "$TMP/render.yaml"` e `grep -n 'name: fcg-grafana' "$TMP/render.yaml"` acham o `secretKeyRef`; `grep -n 'path: /grafana' "$TMP/render.yaml"` acha a regra; `grep -n 'optional' "$TMP/render.yaml"` não acha nada ligado a `fcg-admin`/`fcg-grafana`.
- [ ] **Step 9:** `git commit -m "k8s(eks): ADMIN__PASSWORD no users-api e Prometheus/Grafana (/grafana) no cluster"`.

## Task 4: `.http`, docs, compose (admin) e PR do orchestration

**Files:** Modify `fcgames.http`, `fcgames.aws.http`, `fcgames.eks.http`, `docker-compose.yml`, `README.md`, `docs/superpowers/plans/2026-10-06-eks-services.md`, `docs/superpowers/plans/2026-10-08-eks-cicd.md`. Mesma branch.

- [ ] **Step 1: `.http`.** Nos três arquivos, o login do admin passa a usar `"senha": "{{$dotenv ADMIN_PASSWORD}}"` e o comentário do cabeçalho do bloco admin deixa de citar a senha ("senha em `ADMIN_PASSWORD` do `.env`"). Acrescentar no cabeçalho de cada arquivo duas linhas: REST Client lê `.env` desta pasta; JetBrains usa `http-client.private.env.json` (ignorado pelo git).
- [ ] **Step 2: compose.** No serviço `users-api` de `docker-compose.yml`, acrescentar `ADMIN__PASSWORD: ${ADMIN_PASSWORD:?defina no .env}`.
- [ ] **Step 3: README e docs.** Na tabela de variáveis do `README.md`, acrescentar `ADMIN_PASSWORD` e `GRAFANA_PASSWORD`; nos dois planos antigos em `docs/superpowers/plans/`, trocar o literal antigo da senha por `<ADMIN_PASSWORD>` (no `curl` do e2e: `"senha":"$ADMIN_PASSWORD"`).
- [ ] **Step 4: Verificar.** `git grep -n -I 'Admin@1[2]3'` (a árvore inteira, incluindo `docs/`) não imprime nada; `docker compose config -q` com um `.env` temporário preenchido (placeholders) passa; `docker compose config` sem `ADMIN_PASSWORD` falha com "defina no .env".
- [ ] **Step 5:** `git commit -m "docs/http/compose: senha do admin vem do .env"`, `git push -u origin feature/secrets-zero`, abrir PR e mergear.

## Task 5: users-api — senha do admin por configuração

**Files:** Create `app/src/Fiap.FCGames.Users.CrossCutting/Extensions/AdminSeedConfig.cs`, `app/src/Fiap.FCGames.Users.Tests/Fiap.FCGames.Users.Tests.csproj`, `app/src/Fiap.FCGames.Users.Tests/AdminSeedConfigTests.cs`; Modify `app/src/Fiap.FCGames.Users.slnx`, `app/src/Fiap.FCGames.Users.Api/Program.cs` (`SeedAdminAsync`), `README.md` (tabela do admin). Repo `fcg-users-api`, branch `feature/admin-password-config` a partir de `origin/main`. **Só mergear depois do PR da Task 4 e com o cluster desligado.**

**Interfaces:**
- Produces: `public static string AdminSeedConfig.RequirePassword(IConfiguration configuration)` — devolve `configuration["Admin:Password"]` exatamente como está; lança `InvalidOperationException("Configuração Admin:Password não encontrada. Defina a env var ADMIN__PASSWORD.")` se nulo, vazio ou só espaços.

- [ ] **Step 1: Projeto de teste.** xUnit (`net10.0`) com referência a `Fiap.FCGames.Users.CrossCutting`; adicioná-lo à solution: `dotnet sln app/src/Fiap.FCGames.Users.slnx add app/src/Fiap.FCGames.Users.Tests`. O CI já roda `dotnet test` quando existe `*Tests.csproj`.
- [ ] **Step 2: Testes que falham.** Em `AdminSeedConfigTests.cs`, com `ConfigurationBuilder().AddInMemoryCollection(...)`: `RequirePassword_devolve_o_valor_sem_alterar` (`"a\"b$c!"` volta idêntico), `RequirePassword_lanca_quando_ausente`, `RequirePassword_lanca_quando_so_espacos` (`"   "`); as duas últimas com `Assert.Throws<InvalidOperationException>` e mensagem contendo `ADMIN__PASSWORD`.
- [ ] **Step 3: Ver falhar.** `dotnet test app/src/Fiap.FCGames.Users.slnx` → falha de compilação (`AdminSeedConfig` não existe).
- [ ] **Step 4: Implementar** `AdminSeedConfig.RequirePassword` (assinatura acima, no namespace `Fiap.FCGames.Users.CrossCutting.Extensions`, mesmo estilo de mensagem do `JwtAutenticacaoExtensions`).
- [ ] **Step 5: Ver passar.** `dotnet test app/src/Fiap.FCGames.Users.slnx` → 3 testes passando.
- [ ] **Step 6: `Program.cs`.** Em `SeedAdminAsync`, **depois** do `if (hasAdmin) return;`, obter a senha com `AdminSeedConfig.RequirePassword(services.GetRequiredService<IConfiguration>())` e usá-la em `GerarHash`; trocar o `LogInformation` final para `"Seed: usuário Admin criado ({Email})"` (sem senha). `README.md`: onde a tabela mostra a senha, passar a "definida em `ADMIN_PASSWORD` (ver fcg-orchestration)".
- [ ] **Step 7: Verificar.** `dotnet build app/src/Fiap.FCGames.Users.slnx -c Release` sem erros; `git grep -n -I 'Admin@1[2]3'` não imprime nada; subir a API (`dotnet run --project app/src/Fiap.FCGames.Users.Api`) com `JWT__KEY` definido e **sem** `ADMIN__PASSWORD`, num banco novo → o processo encerra com código ≠ 0 e o log contém `ADMIN__PASSWORD`.
- [ ] **Step 8:** `git commit -m "users: senha do admin vem de Admin:Password (ADMIN__PASSWORD), sem literal"`; PR e merge.

## Task 6: Ciclo real no EKS (validação)

**Pré-requisito do usuário (não do agente):** `gh secret set ADMIN_PASSWORD --env aws-eks -R FIAP-POS-TECH-TEAM-10/fcg-orchestration` e o mesmo para `GRAFANA_PASSWORD` (valor digitado no terminal dele), e criar o `.env` local com `ADMIN_PASSWORD` para o `.http`.

- [ ] **Step 1:** Rodar o workflow "Ligar cluster EKS" (`main`, `testar=true`). Esperado: `eks-up` verde e `eks-e2e` verde, incluindo os passos 9 e 10 (Grafana e targets do Prometheus).
- [ ] **Step 2:** Abrir `http://<alb>/grafana/` no navegador: abre direto no dashboard "FCGames — Observabilidade", sem login, com dado (o e2e gerou tráfego). Conferir também: `http://<alb>/prometheus` e `http://<alb>:9090` **não** respondem (404/sem conexão).
- [ ] **Step 3:** Rodar "Desligar cluster EKS". Esperado: verde ("Destroy complete"). **Isso valida o `destroy` com senha placeholder.** Se falhar, aplicar o plano B do design: `default = ""` nas duas variáveis e validar as senhas só no `eks-up.sh`.
- [ ] **Step 4:** Se o health check do Grafana ficar `unhealthy` no target group, usar o fallback: segundo Ingress `grafana` com `alb.ingress.kubernetes.io/group.name` igual ao do principal (adicionar a anotação nos dois) e a anotação de health check nele; repetir Steps 1-3.

## Task 7: Aposentar a EC2 de observabilidade

**Pré-requisito:** "vai" explícito do usuário e aviso ao Eric. Repo `fcg-observabilidade-service`.

- [ ] **Step 1 (destrutivo, só com o "vai"):** `cd infra && terraform init && terraform destroy` com `AWS_PROFILE=fcg-team`. Esperado: `Destroy complete!`; `aws ec2 describe-instances --instance-ids i-083fafb773752dfba --query 'Reservations[0].Instances[0].State.Name'` → `terminated`.
- [ ] **Step 2:** Branch a partir de `origin/develop`: remover tudo exceto `README.md` (`deploy.yml`, `docker-compose.yml`, `old_docker-compose.observabilit.yml`, `infra/`, `grafana/`, `prometheus/`, `prometheus.yml`) e reescrever o README em poucas linhas apontando para `fcg-orchestration/k8s/eks/observability`.
- [ ] **Step 3: Verificar.** `git ls-files` lista só `README.md`. PR contra `develop` e merge (o push na `develop` não dispara mais nada, o workflow saiu junto).

## Task 8: Orchestration — RabbitMQ sem literal (compose, README, k8s local)

**Files:** Modify `docker-compose.yml`, `README.md` (linhas das variáveis do broker e do login do Management UI), `k8s/rabbitmq-secret.yaml`. Repo `fcg-orchestration`, branch `feature/rabbitmq-sem-literal`. **Mergear antes das Tasks 9-12.**

- [ ] **Step 1:** Em `docker-compose.yml`, todas as ocorrências `${RABBITMQ_USER:-guest}` / `${RABBITMQ_PASS:-guest}` viram `${RABBITMQ_USER:?defina no .env}` / `${RABBITMQ_PASS:?defina no .env}`.
- [ ] **Step 2:** `README.md`: a linha de `RABBITMQ_USER`/`RABBITMQ_PASS` deixa de citar o default e o login do Management UI passa a "usuário/senha do `.env`".
- [ ] **Step 3:** `k8s/rabbitmq-secret.yaml`: valores viram `REPLACE_ME` (o arquivo continua existindo porque `k8s/validate.sh` o valida), com comentário "crie o Secret real com `kubectl create secret generic rabbitmq-secret --from-env-file=.env` antes do apply".
- [ ] **Step 4: Verificar.** `git grep -n -I -w guest` (fora de `docs/superpowers`) não imprime nada; `docker compose config -q` passa com `.env` temporário e falha sem `RABBITMQ_USER`; `bash k8s/validate.sh` (se rodar localmente) segue passando.
- [ ] **Step 5:** `git commit -m "compose/k8s: RabbitMQ sem credencial padrao versionada"`; PR e merge.

## Tasks 9-12: Serviços — RabbitMQ, chave JWT de dev e Secrets locais

Uma task por repo, mesmo padrão. **Lacuna do design que fecho aqui por coerência com o Objetivo 1:** a chave JWT de dev (`launchSettings.json` e `appsettings.Development.json`) e os valores de `k8s/secret.yaml` também são literais versionados; se preferir mantê-los, descarte só os passos marcados (JWT) / (Secret).

**Padrão (em cada repo, branch `feature/sem-literais`, a partir de `origin/main`):**
- [ ] **Step A (código):** onde há `?? "guest"` (arquivos na tabela), trocar por `?? throw new InvalidOperationException("Configuração RabbitMQ:Username não encontrada. Defina a env var RABBITMQ__USERNAME.")` (idem `Password`/`RABBITMQ__PASSWORD`).
- [ ] **Step B (config):** nos arquivos da tabela, remover as propriedades `Username`/`Password` de `RabbitMQ` (manter `Host`), remover `RabbitMQ__Username`/`RabbitMQ__Password` dos `launchSettings.json` e, (JWT) remover `JWT__KEY` dos `launchSettings.json` e `Jwt:Key` dos `appsettings.Development.json`.
- [ ] **Step C (Secret):** (Secret) em `k8s/secret.yaml`, valores viram `REPLACE_ME` (mantendo as chaves) e `k8s/README.md`, na seção "Secret", passa a mostrar `kubectl create secret generic <nome> --from-literal=...="$VAR"` com variáveis do ambiente.
- [ ] **Step D (README):** o README do serviço ganha 3 linhas "para rodar fora do compose": exportar `RABBITMQ__USERNAME`, `RABBITMQ__PASSWORD` e `JWT__KEY`.
- [ ] **Step E (verificar):** `dotnet build` da solution sem erros; `git grep -n -I -E -w 'guest|ChaveSegred[o][A-Za-z0-9]*'` fora de `docs/` não imprime nada; iniciar o Worker/API com `RabbitMQ__Host=localhost` e **sem** `RABBITMQ__USERNAME` → falha com a mensagem do Step A.
- [ ] **Step F:** commit `"<repo>: remove credenciais padrao versionadas (RabbitMQ, JWT dev)"`, PR, merge.

| Task | Repo | Arquivos |
|---|---|---|
| 9 | `fcg-payments-api` | `Payments.CrossCutting/Extensions/MassTransitExtensions.cs:42-43`, `Payments.Worker/Program.cs:57-58`, `Payments.Worker/appsettings.json:25-26`, `Payments.Api/appsettings.Development.json:25,33-34` (JWT + Rabbit), `k8s/secret.yaml`, `k8s/README.md` |
| 10 | `fcg-catalog-api` | `Catalogo.CrossCutting/Extensions/MassTransitExtensions.cs:42-43`, `Catalogo.Worker/Program.cs:62-63`, `Catalogo.Worker/appsettings.json:22-23`, `Catalogo.Api/Properties/launchSettings.json:11,15-16`, `Catalogo.Api/appsettings.Development.json:25,38-39`, `k8s/secret.yaml`, `k8s/README.md` |
| 11 | `fcg-notifications-api` | `Notifications.Worker/Program.cs:54-55`, `Notifications.Worker/appsettings.json:19-20`, `Notifications.Worker/appsettings.Development.json:26-27`, `k8s/secret.yaml`, `k8s/README.md` (sem JWT: o serviço não autentica) |
| 12 | `fcg-users-api` | `Users.CrossCutting/Extensions/MassTransitExtensions.cs:45-46`, `Users.Api/Properties/launchSettings.json:10`, `Users.Api/appsettings.Development.json:16`, `k8s/secret.yaml`, `k8s/README.md` |

## Task 13: Verificação final

- [ ] **Step 1:** Para cada repo (`fcg-users-api`, `fcg-catalog-api`, `fcg-payments-api`, `fcg-notifications-api`, `fcg-orchestration`, `fcg-observabilidade-service`): `git fetch` e `git grep -n -I -E 'Admin@1[2]3|zabbix_pas[s]|root_pas[s]|ChaveSegred[o][A-Za-z0-9]*' origin/main -- .` e `git grep -n -I -w guest origin/main -- . ':!docs/superpowers'`. Esperado: nenhuma linha em nenhum repo.
- [ ] **Step 2:** `gh secret list --env aws-eks -R FIAP-POS-TECH-TEAM-10/fcg-orchestration` lista `ADMIN_PASSWORD` e `GRAFANA_PASSWORD`.
- [ ] **Step 3:** Atualizar o `CLAUDE.md` do projeto (seção Fase 4): senhas via secrets do GitHub → K8s Secrets, Grafana em `/grafana`, EC2 de observabilidade aposentada.
