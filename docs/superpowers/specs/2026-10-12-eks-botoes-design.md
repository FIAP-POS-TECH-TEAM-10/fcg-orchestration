# Fase 4 — Parte 3b: Ligar/desligar o cluster pelo GitHub (design)

**Data:** 2026-10-12
**Responsável:** Daniel
**Status:** aprovado no brainstorming, aguardando plano de implementação
**Depende de:** partes 1, 2 e 3a (cluster, serviços e CI/CD) — mergeadas na `main`.

## Contexto

Hoje o cluster `fcg-eks` só liga/desliga pela máquina de quem tem Terraform, kubectl, AWS CLI e o
profile `fcg-team` (`scripts/eks-up.sh` / `eks-down.sh`). O objetivo é que qualquer pessoa do time
ligue/desligue por **botões no GitHub Actions** do `fcg-orchestration`, e que um **desligamento
automático noturno** evite créditos queimados por esquecimento (a conta está no plano FREE —
US$ ~147 de créditos; o cluster custa ~US$ 0,20/h ≈ US$ 5/dia se esquecido).

A role OIDC atual (`GitHubActions-ECS-Deploy-Role`) não tem permissão para o Terraform do cluster
(EKS, IAM, EC2, ELB…) e é compartilhada por todos os repos da org — não deve ganhar esse poder.

## Decisões

| Tema | Decisão | Alternativas descartadas |
|---|---|---|
| Permissões | role nova **`GitHubActions-EKS-Admin`** com `AdministratorAccess`, trust restrito a `repo:FIAP-POS-TECH-TEAM-10/fcg-orchestration:environment:aws-eks` | policy enxuta (várias tentativas de apply pagas); PowerUser + IAM restrito |
| Quem dispara | qualquer pessoa com escrita no repo, **sem aprovação**; Environment `aws-eks` aceita só a branch `main` | aprovação para ligar; aprovação para ambos |
| Auto-desligamento | **toda noite às 03:00 BRT** (`0 6 * * *` UTC), no-op se já desligado | sem automação; desligar após X horas ligado |
| Organização | **dois workflows** (`eks-ligar.yml`, `eks-desligar.yml`) que chamam os scripts existentes | um workflow com menu; passos reescritos em YAML |

## Componentes

### `infra/github-ci/` (Terraform permanente — já existe)

Novo arquivo `eks-admin-role.tf`:
- `aws_iam_role` `GitHubActions-EKS-Admin`:
  - trust: `Federated = arn:aws:iam::915153720516:oidc-provider/token.actions.githubusercontent.com`,
    `sts:AssumeRoleWithWebIdentity`, condições
    `token.actions.githubusercontent.com:aud = sts.amazonaws.com` e
    `token.actions.githubusercontent.com:sub = repo:FIAP-POS-TECH-TEAM-10/fcg-orchestration:environment:aws-eks`
    (StringEquals — sem curinga);
  - `max_session_duration = 3600`.
- `aws_iam_role_policy_attachment` → `arn:aws:iam::aws:policy/AdministratorAccess`.
- output `eks_admin_role_arn`.

### `infra/eks/variables.tf`

`admin_principal_arns` ganha `arn:aws:iam::915153720516:role/GitHubActions-EKS-Admin` — sem isso os
providers helm/kubernetes do Terraform e o `kubectl apply` do `eks-up.sh` não têm acesso ao cluster
criado pelo próprio workflow.

### `scripts/eks-up.sh`, `scripts/eks-down.sh` (e `eks-e2e.sh` não muda)

Troca `export AWS_PROFILE="${AWS_PROFILE:-fcg-team}"` por: só define o profile padrão quando **não**
há credencial no ambiente:

```bash
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -z "${AWS_PROFILE:-}" ]; then
  export AWS_PROFILE="fcg-team"
fi
```

(No GitHub o `aws-actions/configure-aws-credentials` exporta `AWS_ACCESS_KEY_ID`/`SECRET`/`SESSION_TOKEN`.)
Mensagens de erro que citam `$AWS_PROFILE` passam a funcionar com o profile vazio.

### GitHub Environment `aws-eks` (repo `fcg-orchestration`)

Criado uma vez via `gh api` (Daniel é admin do repo):
- `deployment_branch_policy`: `custom_branch_policies: true` + política de branch `main`;
- sem revisores obrigatórios.

Comandos documentados no README do orchestration.

### `.github/workflows/eks-ligar.yml` — "Ligar cluster EKS"

- `on: workflow_dispatch` com input boolean `testar` (default `true`): roda `eks-e2e.sh` após ligar.
- `concurrency: { group: eks-cluster, cancel-in-progress: false }`.
- `permissions: { id-token: write, contents: read }`.
- job `ligar`: `environment: aws-eks`, `timeout-minutes: 45`, `runs-on: ubuntu-latest`.
- passos: checkout → `aws-actions/configure-aws-credentials@v4` (`role-to-assume` = EKS-Admin,
  `role-duration-seconds: 3600`, região `sa-east-1`) → `hashicorp/setup-terraform@v3`
  (`terraform_wrapper: false`) → `./scripts/eks-up.sh` → (se `testar`) `./scripts/eks-e2e.sh`.
- resumo: URL do ALB (`kubectl get ingress fcgames`), `kubectl get pods -n fcgames`, aviso de custo
  e do desligamento das 03:00, link para o workflow "Desligar cluster EKS".
- `if: failure()`: resumo "⚠️ o cluster pode ter ficado LIGADO — rode **Desligar cluster EKS** (ou
  o desligamento automático das 03:00 desliga)".

### `.github/workflows/eks-desligar.yml` — "Desligar cluster EKS"

- `on: workflow_dispatch` + `schedule: - cron: '0 6 * * *'` (03:00 BRT).
- mesma concurrency, permissions, environment, OIDC e setup-terraform; `timeout-minutes: 40`.
- passo "cluster existe?": `aws eks describe-cluster --name fcg-eks` →
  `ResourceNotFoundException` → resumo "💤 nada a fazer: cluster já desligado", passos seguintes
  pulados, run verde; outro erro → falha.
- se existe: `./scripts/eks-down.sh`; resumo com o resultado (e sobras, se houver).

### Documentação

README do `fcg-orchestration` (seção nova "Ligar/desligar pelo GitHub"): onde ficam os botões,
o que cada um faz, desligamento das 03:00, custo, como criar o Environment, conflito de lock se
alguém rodar o script local ao mesmo tempo. `infra/github-ci/README.md`: a role nova e por quê.
`CLAUDE.md`: parte 3b.

## Riscos aceitos

- Quem tem escrita no `fcg-orchestration` e altera um workflow na `main` ganha poder de admin na
  conta via essa role. Mitigação: trust só para o Environment `aws-eks` que só aceita `main`
  (alteração exige merge na `main`).
- Rodar o script local e o workflow ao mesmo tempo → o segundo falha com "state locked" (sem dano).

## Validação

Sem custo:
- `terraform plan` em `infra/github-ci`: cria só a role e o attachment; `terraform validate` em `infra/eks`.
- `actionlint` nos 2 workflows; `bash -n` nos scripts.
- Script local intacto: `./scripts/eks-down.sh` com cluster desligado (usa o profile `fcg-team`, termina "Cluster desligado").
- Environment `aws-eks` existe com política de branch `main`.
- Trava: disparar "Desligar cluster EKS" a partir de uma branch ≠ `main` → recusado pelo Environment.

Ciclo real (~45 min, ~US$ 0,20 — com confirmação do usuário):
1. Botão "Ligar cluster EKS" (`testar=true`) → run verde, e2e OK, URL do ALB no resumo.
2. Da máquina do Daniel: `aws eks update-kubeconfig` + `kubectl get pods -n fcgames` funciona.
3. Botão "Desligar cluster EKS" → run verde, sem sobras na AWS.
4. "Desligar cluster EKS" de novo (cluster desligado) → "nada a fazer", run verde.

## Definição de pronto

Workflows, role, Environment e ajustes mergeados/aplicados; ciclo real passou; README do
orchestration, `infra/github-ci/README.md` e `CLAUDE.md` atualizados.

## Fora do escopo

Notificações (e-mail/Slack); travas de orçamento (AWS Budgets); restringir ainda mais a role.
