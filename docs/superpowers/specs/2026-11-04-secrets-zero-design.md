# Zero secrets commitados + observabilidade no EKS — Design

Data: 2026-11-04 · Status: aguardando aprovação · Repos: fcg-orchestration (principal), fcg-users-api, fcg-observabilidade-service, e os 4 serviços para o item RabbitMQ.

## Intenção

O enunciado da Fase 4 pede **zero credenciais em código/YAML** (K8s Secrets ou Secrets Manager). Uma varredura em 2026-11-04 (branches `main`/`develop` de todos os repos, sem histórico) achou o que ainda fere isso:

1. Senha do admin (um literal fixo) no `Program.cs` do users-api, em scripts (`eks-e2e.sh`), nos `.http` e na documentação.
2. Senhas do MariaDB/Zabbix e do admin do Grafana no `docker-compose.yml` do repo de observabilidade.
3. `guest/guest` do RabbitMQ espalhado em appsettings, `launchSettings`, fallbacks no código e `k8s/*secret.yaml` (ver "Decisões pendentes").

Além disso, a observabilidade ficou **sem dado**: roda numa EC2 solta (hoje `stopped`), o Prometheus aponta pros API Gateways (destruídos na Fase 4) e o ALB do EKS não expõe `/metrics`. Ela também expõe Grafana anônimo como Admin e as portas 22/3000/8080/9090/10051 para a internet.

Resultado desejado: nenhum segredo em arquivo versionado dos nossos repos, e Prometheus + Grafana funcionando dentro do cluster para mostrar no vídeo.

## Objetivos

- Nenhum literal de senha/chave em arquivo versionado (código, YAML, scripts, `.http`, docs) nos repos do projeto.
- A senha do admin chega ao app só via K8s Secret; a fonte é um secret do GitHub Actions.
- Prometheus e Grafana rodam no EKS junto com os serviços, ligam/desligam com o cluster, e o Grafana mostra os dashboards já publicados com dado real.
- O fluxo de demo (login admin no `.http`) continua simples.

## Não-objetivos

- **Não usar AWS Secrets Manager** (decisão: K8s Secret atende o enunciado e nenhum segredo nosso precisa de rotação/persistência).
- Não reescrever o histórico git dos repos em `main`. A chave JWT antiga e a senha antiga do admin continuam no histórico; a chave antiga não é usada em lugar nenhum (o cluster gera uma aleatória) e a senha do admin muda.
- Não adicionar `/metrics` ao PaymentsAPI (ele não aparece nos painéis; fica como follow-up).
- Zabbix sai de vez (decisão do usuário); não é substituído por nada.
- A branch `feature-michel-add-secretmanager` não entra aqui (feedback já dado ao autor; é PR dele).
- NotificationsAPI/lambda não muda além do item RabbitMQ.

## Anti-objetivos (seria falha mesmo funcionando)

- Quebrar o `eks-ligar`, o `eks-desligar` ou o desligamento automático das 03:00 BRT.
- Tornar a demo dependente de copiar senha nova a cada ligada.
- Qualquer painel/Grafana acessível publicamente.

## Decisões do usuário

- Senha do admin: **fixa**, escolhida uma vez, guardada em secret do GitHub Actions (não em arquivo). Ela entra no cluster como K8s Secret via Terraform.
- Observabilidade: **vai para o EKS**, **sem Zabbix**, uso apenas para o vídeo (acesso por `kubectl port-forward`).
- Caminho mais simples possível; fazer todos os itens.

## Design

### 1. Senha do admin

- **users-api `Program.cs` (`SeedAdminAsync`)**: lê `Admin:Password` (env `ADMIN__PASSWORD`). Se não existir admin e a config estiver vazia, o app **falha na subida com mensagem clara** (não semeia com valor padrão). E-mail do admin (`admin@fcgames.com`) continua no código (não é segredo). Ambiente `Testing` continua pulando o seed.
- **Terraform `infra/eks`**: `variable "admin_password"` (`sensitive = true`, sem default) e `kubernetes_secret_v1` `fcg-admin` (chave `admin-password`) no namespace da aplicação, ao lado do `fcg-jwt`.
- **`k8s/eks/users-api.yaml`**: env `ADMIN__PASSWORD` via `secretKeyRef` em `fcg-admin`.
- **`scripts/eks-up.sh`**: exige `ADMIN_PASSWORD` no ambiente (erro claro se faltar) e exporta `TF_VAR_admin_password`. **`eks-down.sh` e o workflow de desligar não podem depender do valor real** (usam um placeholder só para o Terraform aceitar a variável no `destroy`).
- **`eks-ligar.yml`**: passa `ADMIN_PASSWORD` a partir de `secrets.ADMIN_PASSWORD`, cadastrado como secret do **Environment `aws-eks`** (o mesmo que já restringe a role à `main`).
- **`scripts/eks-e2e.sh`**: usa `ADMIN_PASSWORD` (no workflow vem do mesmo secret; local, do ambiente).
- **`.http` (`fcgames.http`, `fcgames.aws.http`, `fcgames.eks.http`)**: a senha vem de `{{$dotenv ADMIN_PASSWORD}}` (VS Code REST Client), lendo um `.env` local já ignorado pelo git. Novo `.env.example` com placeholders. Nota no cabeçalho para quem usa JetBrains (arquivo de ambiente privado, também ignorado).
- **docker-compose local**: `ADMIN__PASSWORD: ${ADMIN_PASSWORD:?defina no .env}`.
- **Docs**: trocar o literal por `<ADMIN_PASSWORD>` no README do users-api, nos specs/planos antigos em `docs/superpowers/` e onde mais aparecer.
- **Ação do usuário (não do agente)**: cadastrar o secret com `gh secret set ADMIN_PASSWORD --env aws-eks` (o valor é digitado no terminal dele e nunca passa pelo chat) e criar o `.env` local.

### 2. Prometheus + Grafana no EKS

- Novos recursos em `k8s/eks/` (subpasta `observability/` incluída no `kustomization.yaml`), imagens oficiais fixadas nas mesmas versões já usadas (`prom/prometheus:v3.13.3`, `grafana/grafana:13.2.1`), **sem pipeline de imagem nova**: a configuração entra por `configMapGenerator` a partir de arquivos copiados do repo de observabilidade (`prometheus.yml`, provisioning de datasource/dashboards, `fcgames-observability.json`).
- `prometheus.yml`: scrape por DNS interno, `users-api.fcgames.svc` e `catalog-api.fcgames.svc`, path `/metrics`, esquema http. Manter os nomes de job `fcg-users-service` e `fcg-catalog-service` por consistência. Verificado: o dashboard só usa os labels `job`, `code` e `le`, e a lista de serviços vem de `label_values(http_request_duration_seconds_count, job)`; qualquer job com as métricas `http_request_duration_seconds_*` aparece. O `/metrics` das duas APIs é anônimo (foi raspado com sucesso, sem token, pelo Prometheus em set/2026).
- Datasource do Grafana aponta para `http://prometheus:9090`.
- Grafana: usuário `admin`, senha do mesmo Secret `fcg-admin` (`GF_SECURITY_ADMIN_PASSWORD` via `secretKeyRef`); **acesso anônimo desligado**; dashboard inicial definido por env. Decisão minha (a confirmar): reaproveitar a mesma senha do admin do app para não criar um segundo secret.
- Serviços `ClusterIP`; **sem Ingress e sem porta pública**. Acesso: `kubectl port-forward svc/grafana 3000:80 -n fcgames`. `eks-up.sh` imprime esse comando no final e inclui os dois deployments na espera de rollout.
- Armazenamento `emptyDir` (efêmero, igual ao SQLite); retenção curta do Prometheus. Requests/limits pequenos (chute inicial: Prometheus ~100m/256Mi, Grafana ~50m/128Mi) **a validar em ciclo real**, porque o cluster tem só 2× `t3.small`.
- PaymentsAPI não aparece nos painéis (sem `/metrics`).

### 3. Aposentar a EC2 de observabilidade

- No repo `fcg-observabilidade-service`: desativar o `deploy.yml` (hoje um push na `develop` recria a EC2 com Zabbix e senhas), remover `docker-compose.yml`, `old_docker-compose.observabilit.yml` e `infra/` (os arquivos com senhas), e deixar o README apontando para `fcg-orchestration/k8s/eks/observability`.
- **Ação destrutiva**: `terraform destroy` da EC2 `i-083fafb773752dfba` (hoje `stopped`), do security group e das IAM roles. Só executa com confirmação explícita do usuário no momento.
- Aviso ao Eric (autor da infra original) antes de mexer no repo dele.

### 4. Ordem de entrega (PRs pequenos, na ordem)

1. `fcg-orchestration`: Terraform + scripts + workflows + manifests (users-api passa a injetar `ADMIN__PASSWORD`, observabilidade) + `.http` + docs. É inofensivo para a imagem antiga do users-api.
2. `fcg-users-api`: `Program.cs` + README + compose. Entra depois, porque com o código novo o app exige `ADMIN__PASSWORD`.
3. Ciclo real: `eks-up` → `eks-e2e` → Grafana por port-forward com dado → `eks-down`.
4. `fcg-observabilidade-service`: aposentar (itens do bloco 3).
5. RabbitMQ (depende da decisão abaixo).

## Chamadas minhas (levantadas pela revisão; conferir)

- **`terraform destroy` com a senha placeholder**: o destroy remove o Secret sem comparar valor, então o placeholder só serve para o Terraform aceitar a variável obrigatória. Deve funcionar sem `ignore_changes`. **Validar no primeiro `eks-down` do ciclo real**; plano B: dar `default = ""` à variável e validar a senha só no `eks-up.sh`.
- **Ordem de merge e deploy**: `fcg-orchestration` primeiro, depois `fcg-users-api`. O CI do users-api só faz deploy com o cluster ligado (desligado, pula com aviso). Se o cluster estiver ligado com o estado antigo (sem `fcg-admin`), o pod novo não sobe, o rollout falha e o pod antigo continua atendendo (rolling update, sem queda). Regra: não mergear o users-api com cluster ligado em estado antigo; religar o cluster depois do merge do orchestration.
- **Senha do Grafana**: reaproveita o `fcg-admin` (um secret só). Confirmar na aprovação deste documento; se preferirem separado, vira um segundo secret do GitHub e um segundo Secret do K8s.
- **Quem pode ligar o cluster**: qualquer pessoa com escrita no repo roda o workflow, e o secret é injetado pelo GitHub, então **ninguém precisa saber a senha para ligar**. Só quem for logar como admin na demo precisa dela (no `.env` local). Cadastrar/trocar o secret exige permissão de admin no repo (o usuário).

## Decisões pendentes (do usuário)

- **RabbitMQ `guest/guest`** aparece em ~17 arquivos de 5 repos (appsettings, `launchSettings`, fallback `?? "guest"` no código, `k8s/*secret.yaml`, `docker-compose.yml`, `k8s/rabbitmq-secret.yaml`). É a senha padrão do broker e só vale local; não existe na AWS (lá é SQS/SNS por IAM). Duas opções: **estrita** (remover tudo e injetar por `.env`/env var, o grep de segredos fica zerado) ou **pragmática** (remover só fallbacks no código e o `appsettings.json` base do notifications; manter o exemplo documentado em arquivos de dev). Recomendação: estrita, já que o objetivo declarado é "0 secrets commitados".

## O que fica para quem for construir

- Nome exato dos arquivos/recursos Kubernetes da observabilidade e estrutura da subpasta.
- Redação das mensagens de erro e do texto do `.env.example`.
- Ajuste fino de recursos (requests/limits) depois do ciclo real.
- Como o `eks-e2e.sh` obtém a senha quando roda local (variável de ambiente ou `kubectl get secret`).
