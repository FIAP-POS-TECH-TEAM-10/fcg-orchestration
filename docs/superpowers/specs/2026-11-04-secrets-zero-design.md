# Zero secrets commitados + observabilidade no EKS — Design

Data: 2026-11-04 · Status: aguardando aprovação (revisão 2) · Repos: fcg-orchestration (principal), fcg-users-api, fcg-observabilidade-service, e os 4 serviços para o item RabbitMQ.

## Intenção

O enunciado da Fase 4 pede **zero credenciais em código/YAML** (K8s Secrets ou Secrets Manager). Uma varredura em 2026-11-04 (branches `main`/`develop` de todos os repos, sem histórico) achou o que ainda fere isso:

1. Senha do admin (um literal fixo) no `Program.cs` do users-api, em scripts (`eks-e2e.sh`), nos `.http` e na documentação.
2. Senhas do MariaDB/Zabbix e do admin do Grafana no `docker-compose.yml` do repo de observabilidade.
3. `guest/guest` do RabbitMQ espalhado em appsettings, `launchSettings`, fallbacks no código, `k8s/*secret.yaml` e `docker-compose.yml`.

Além disso, a observabilidade ficou **sem dado**: roda numa EC2 solta (hoje `stopped`), o Prometheus aponta pros API Gateways (destruídos na Fase 4) e o ALB do EKS não expõe `/metrics`. Ela também expõe Grafana anônimo como Admin e as portas 22/3000/8080/9090/10051 para a internet.

Resultado desejado: nenhum segredo em arquivo versionado dos nossos repos, e Prometheus + Grafana funcionando dentro do cluster, com o Grafana acessível por URL (somente leitura) para mostrar no vídeo.

## Objetivos

- Nenhum literal de senha/chave em arquivo versionado (código, YAML, scripts, `.http`, docs) nos repos do projeto.
- As senhas do admin do app e do admin do Grafana chegam ao cluster só via K8s Secret; a fonte de cada uma é um secret do GitHub Actions.
- Prometheus e Grafana rodam no EKS junto com os serviços, ligam/desligam com o cluster, e o Grafana mostra os dashboards já publicados com dado real.
- O Grafana abre por uma URL do próprio ALB (`/grafana`), em modo leitura, sem login.
- O fluxo de demo (login admin no `.http`) continua simples.

## Não-objetivos

- **Não usar AWS Secrets Manager** (decisão: K8s Secret atende o enunciado e nenhum segredo nosso precisa de rotação/persistência).
- Não reescrever o histórico git dos repos em `main`. A chave JWT antiga e a senha antiga do admin continuam no histórico; a chave antiga não é usada em lugar nenhum (o cluster gera uma aleatória) e a senha do admin muda.
- Não adicionar `/metrics` ao PaymentsAPI (ele não aparece nos painéis; fica como follow-up).
- Zabbix sai de vez (decisão do usuário); não é substituído por nada.
- Sem domínio próprio nem HTTPS: o ALB continua só HTTP e o DNS dele muda a cada vez que o cluster liga.
- A branch `feature-michel-add-secretmanager` não entra aqui (feedback já dado ao autor; é PR dele).
- NotificationsAPI/lambda não muda além do item RabbitMQ.

## Anti-objetivos (seria falha mesmo funcionando)

- Quebrar o `eks-ligar`, o `eks-desligar` ou o desligamento automático das 03:00 BRT.
- Tornar a demo dependente de copiar senha nova a cada ligada.
- Prometheus, ou qualquer acesso com escrita/admin do Grafana, acessível pela internet.
- Digitar uma senha de admin em página servida por HTTP puro.

## Decisões do usuário

- Senha do admin do app: **fixa**, escolhida uma vez, guardada em secret do GitHub Actions (não em arquivo). Entra no cluster como K8s Secret via Terraform.
- Observabilidade: **vai para o EKS**, **sem Zabbix**.
- Acesso ao Grafana: **por URL no mesmo ALB (`/grafana`)**, com **acesso anônimo somente leitura**, e **senha de admin do Grafana separada** da do app (segundo secret).
- RabbitMQ `guest/guest`: **estrita** (remover os literais em todos os arquivos versionados e injetar por `.env`/env var).
- Caminho mais simples possível; fazer todos os itens.

## Design

### 1. Senha do admin do app

- **users-api `Program.cs` (`SeedAdminAsync`)**: lê `Admin:Password` (env `ADMIN__PASSWORD`). Se não existir admin e a config estiver vazia, o app **falha na subida com mensagem clara** (não semeia com valor padrão). E-mail do admin (`admin@fcgames.com`) continua no código (não é segredo). Ambiente `Testing` continua pulando o seed.
- **Terraform `infra/eks`**: `variable "admin_password"` (`sensitive = true`, sem default) e `kubernetes_secret_v1` `fcg-admin` (chave `admin-password`) no namespace da aplicação, ao lado do `fcg-jwt`.
- **`k8s/eks/users-api.yaml`**: env `ADMIN__PASSWORD` via `secretKeyRef` em `fcg-admin`.
- **`scripts/eks-up.sh`**: exige `ADMIN_PASSWORD` e `GRAFANA_PASSWORD` no ambiente (erro claro se faltar) e exporta `TF_VAR_admin_password` / `TF_VAR_grafana_password`. **`eks-down.sh` e o workflow de desligar não podem depender dos valores reais** (usam placeholders só para o Terraform aceitar as variáveis no `destroy`).
- **`eks-ligar.yml`**: passa `ADMIN_PASSWORD` e `GRAFANA_PASSWORD` a partir de `secrets.*`, cadastrados como secrets do **Environment `aws-eks`** (o mesmo que já restringe a role à `main`).
- **`scripts/eks-e2e.sh`**: usa `ADMIN_PASSWORD` (no workflow vem do mesmo secret; local, do ambiente).
- **`.http` (`fcgames.http`, `fcgames.aws.http`, `fcgames.eks.http`)**: a senha vem de `{{$dotenv ADMIN_PASSWORD}}` (VS Code REST Client), lendo um `.env` local já ignorado pelo git. Novo `.env.example` com placeholders. Nota no cabeçalho para quem usa JetBrains (arquivo de ambiente privado, também ignorado).
- **docker-compose local**: `ADMIN__PASSWORD: ${ADMIN_PASSWORD:?defina no .env}`.
- **Docs**: trocar o literal por `<ADMIN_PASSWORD>` no README do users-api, nos specs/planos antigos em `docs/superpowers/` e onde mais aparecer.
- **Ação do usuário (não do agente)**: cadastrar os dois secrets com `gh secret set ADMIN_PASSWORD --env aws-eks` e `gh secret set GRAFANA_PASSWORD --env aws-eks` (os valores são digitados no terminal dele e nunca passam pelo chat) e criar o `.env` local.

### 2. Prometheus + Grafana no EKS

- Novos recursos em `k8s/eks/` (subpasta `observability/` incluída no `kustomization.yaml`), imagens oficiais fixadas nas mesmas versões já usadas (`prom/prometheus:v3.13.3`, `grafana/grafana:13.2.1`), **sem pipeline de imagem nova**: a configuração entra por `configMapGenerator` a partir de arquivos copiados do repo de observabilidade (`prometheus.yml`, provisioning de datasource/dashboards, `fcgames-observability.json`).
- `prometheus.yml`: scrape por DNS interno, `users-api.fcgames.svc` e `catalog-api.fcgames.svc`, path `/metrics`, esquema http. Manter os nomes de job `fcg-users-service` e `fcg-catalog-service` por consistência. Verificado: o dashboard só usa os labels `job`, `code` e `le`, e a lista de serviços vem de `label_values(http_request_duration_seconds_count, job)`; qualquer job com as métricas `http_request_duration_seconds_*` aparece. O `/metrics` das duas APIs é anônimo (foi raspado com sucesso, sem token, pelo Prometheus em set/2026).
- **Prometheus**: Service `ClusterIP`, **sem Ingress**, só acessível dentro do cluster.
- **Grafana — acesso**: Service `ClusterIP` + nova regra no Ingress existente (`ingress.yaml`) para o prefixo `/grafana` (não colide com `/usuarios`, `/jogos` etc.), no mesmo ALB, custo extra zero. O Grafana é configurado para viver em sub-caminho (`GF_SERVER_ROOT_URL` e `GF_SERVER_SERVE_FROM_SUB_PATH=true`). O Ingress hoje usa `/health` como health check do ALB; o Grafana responde em `/grafana/api/health`, então o health check do target group do Grafana precisa ser ajustado (anotação específica para esse Service ou Ingress separado no mesmo grupo do ALB). **É o ponto de maior risco técnico: validar no ciclo real.**
- **Grafana — autenticação**: acesso anônimo ligado com papel **Viewer** (`GF_AUTH_ANONYMOUS_ENABLED=true`, `GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer`); dashboard inicial definido por env. O usuário `admin` continua existindo, com senha do **Secret próprio `fcg-grafana`** (chave `admin-password`, via `secretKeyRef` em `GF_SECURITY_ADMIN_PASSWORD`), alimentado pelo secret do GitHub `GRAFANA_PASSWORD` por uma segunda variável Terraform (`grafana_password`, sensitive, sem default). Como o ALB é HTTP, **o login de admin não deve ser usado pela URL pública**; edições se fazem por `kubectl port-forward svc/grafana 3000:80 -n fcgames` (os dashboards vêm do ConfigMap, então normalmente não há o que editar).
- Exposição aceita: dashboards em modo leitura, acessíveis por qualquer pessoa que tenha a URL, em HTTP, com só métricas agregadas (taxa, latência, código de status; sem dado de usuário). O cluster só fica ligado em sessão e desliga às 03:00 BRT. A tela de login do Grafana continua pública, por isso a senha de admin é separada da do app.
- Datasource do Grafana aponta para `http://prometheus:9090`.
- `eks-up.sh` inclui os dois deployments na espera de rollout e imprime `http://<alb>/grafana` (e o comando de port-forward como alternativa).
- Armazenamento `emptyDir` (efêmero, igual ao SQLite); retenção curta do Prometheus. Requests/limits pequenos (chute inicial: Prometheus ~100m/256Mi, Grafana ~50m/128Mi) **a validar em ciclo real**, porque o cluster tem só 2× `t3.small`.
- PaymentsAPI não aparece nos painéis (sem `/metrics`).

### 3. Aposentar a EC2 de observabilidade

- No repo `fcg-observabilidade-service`: desativar o `deploy.yml` (hoje um push na `develop` recria a EC2 com Zabbix e senhas), remover `docker-compose.yml`, `old_docker-compose.observabilit.yml` e `infra/` (os arquivos com senhas), e deixar o README apontando para `fcg-orchestration/k8s/eks/observability`.
- **Ação destrutiva**: `terraform destroy` da EC2 `i-083fafb773752dfba` (hoje `stopped`), do security group e das IAM roles. Só executa com confirmação explícita do usuário no momento.
- Aviso ao Eric (autor da infra original) antes de mexer no repo dele.

### 4. RabbitMQ `guest/guest` (estrita)

- **Código** (`MassTransitExtensions.cs` de users/catalog/payments e `Program.cs` dos Workers e do notifications): remover o fallback `?? "guest"`; com `RabbitMQ:Host` definido e usuário/senha ausentes, falhar na subida com mensagem clara. Na AWS nada muda (usa SQS/SNS por IAM).
- **appsettings / launchSettings**: remover `Username`/`Password` dos arquivos versionados (inclusive `appsettings.json` base do notifications e Workers de catalog/payments, e os `appsettings.Development.json`).
- **docker-compose.yml do orchestration**: `RABBITMQ_USER`/`RABBITMQ_PASS` obrigatórios (`${...:?}`), vindos do `.env` (já no `.env.example`); remover o `:-guest` de default.
- **Manifests K8s locais** (`k8s/secret.yaml` dos serviços e `k8s/rabbitmq-secret.yaml`): deixar de versionar o valor; o README de cada um passa a documentar a criação do Secret por comando (`kubectl create secret generic ... --from-env-file`).
- Rodar o serviço isolado fora do compose passa a exigir as variáveis no ambiente; documentar no README.

### 5. Ordem de entrega (PRs pequenos, na ordem)

1. `fcg-orchestration`: Terraform (dois secrets) + scripts + workflows + manifests (users-api com `ADMIN__PASSWORD`, observabilidade) + `.http` + docs. É inofensivo para a imagem antiga do users-api.
2. `fcg-users-api`: `Program.cs` + README + compose. Entra depois, porque com o código novo o app exige `ADMIN__PASSWORD`.
3. Ciclo real: `eks-up` → `eks-e2e` → Grafana pela URL `/grafana` com dado → `eks-down`.
4. `fcg-observabilidade-service`: aposentar (itens do bloco 3).
5. RabbitMQ: um PR por repo (users, catalog, payments, notifications) + o do orchestration; o compose do orchestration e os PRs dos serviços entram juntos para não quebrar o ambiente local.

## Chamadas minhas (levantadas pela revisão; conferir)

- **`terraform destroy` com as senhas placeholder**: o destroy remove os Secrets sem comparar valor, então o placeholder só serve para o Terraform aceitar as variáveis obrigatórias. Deve funcionar sem `ignore_changes`. **Validar no primeiro `eks-down` do ciclo real**; plano B: dar `default = ""` às variáveis e validar as senhas só no `eks-up.sh`.
- **Ordem de merge e deploy**: `fcg-orchestration` primeiro, depois `fcg-users-api`. O CI do users-api só faz deploy com o cluster ligado (desligado, pula com aviso). Se o cluster estiver ligado com o estado antigo (sem `fcg-admin`), o pod novo não sobe, o rollout falha e o pod antigo continua atendendo (rolling update, sem queda). Regra: não mergear o users-api com cluster ligado em estado antigo; religar o cluster depois do merge do orchestration.
- **Quem pode ligar o cluster**: qualquer pessoa com escrita no repo roda o workflow, e os secrets são injetados pelo GitHub, então **ninguém precisa saber as senhas para ligar**. Só quem for logar como admin na demo precisa da senha do app (no `.env` local). Cadastrar/trocar os secrets exige permissão de admin no repo (o usuário).

## O que fica para quem for construir

- Nome exato dos arquivos/recursos Kubernetes da observabilidade e estrutura da subpasta.
- Como ajustar o health check do ALB para o Grafana (anotação no Service vs. Ingress separado no mesmo grupo).
- Redação das mensagens de erro e do texto do `.env.example`.
- Ajuste fino de recursos (requests/limits) depois do ciclo real.
- Como o `eks-e2e.sh` obtém a senha quando roda local (variável de ambiente ou `kubectl get secret`).
