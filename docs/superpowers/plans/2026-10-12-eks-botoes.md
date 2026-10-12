# Ligar/desligar o cluster pelo GitHub (Fase 4 — Parte 3b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Botões "Ligar cluster EKS" e "Desligar cluster EKS" no GitHub Actions do `fcg-orchestration` (com desligamento automático às 03:00 BRT), usando uma role IAM dedicada restrita ao Environment `aws-eks`.

**Architecture:** Dois workflows `workflow_dispatch` (o de desligar também com `schedule`) que assumem via OIDC a role nova `GitHubActions-EKS-Admin` (criada no Terraform permanente `infra/github-ci`) e chamam os scripts existentes `scripts/eks-up.sh` / `eks-down.sh`. Os scripts passam a usar o profile `fcg-team` só quando não há credencial no ambiente.

**Tech Stack:** GitHub Actions (`actions/checkout@v4`, `aws-actions/configure-aws-credentials@v4`, `hashicorp/setup-terraform@v3`), GitHub Environments, Terraform ≥ 1.5 (AWS provider ~> 5.95), bash.

**Spec:** `fcg-orchestration/docs/superpowers/specs/2026-10-12-eks-botoes-design.md`

---

## Convenções para quem executa

- Repo `C:\GIT\FIAP\FIAP-POS-TECH-TEAM-10\fcg-orchestration`, branch `feature/eks-botoes` (sem upstream). Nunca commitar `fcgames.aws.http`. Nunca dar push sem o usuário pedir.
- Git Bash no Windows. AWS: `export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1` (conta `915153720516`); `| tr -d '\r'` ao capturar saída do AWS CLI.
- Usar Write/Edit para YAML e scripts; `.sh` e `.yml` com LF.
- ⚠️ = pedir confirmação ao usuário antes.

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `infra/github-ci/eks-admin-role.tf` (novo) | role `GitHubActions-EKS-Admin` + AdministratorAccess + output |
| `infra/github-ci/README.md` (modificar) | documentar a role nova |
| `infra/eks/variables.tf` (modificar) | role nova em `admin_principal_arns` |
| `scripts/eks-up.sh`, `scripts/eks-down.sh` (modificar) | profile `fcg-team` só sem credencial no ambiente |
| `.github/workflows/eks-ligar.yml` (novo) | botão Ligar |
| `.github/workflows/eks-desligar.yml` (novo) | botão Desligar + cron 03:00 BRT |
| `README.md` (modificar) | seção "Ligar/desligar pelo GitHub" |
| `CLAUDE.md` (raiz do workspace, fora de git) | parte 3b |

Detalhe além do spec: os steps que usam `| tee` declaram `set -o pipefail` (o shell padrão do GitHub sem `shell: bash` explícito não tem pipefail — sem isso uma falha do script seria engolida pelo `tee`).

---

### Task 1: Role `GitHubActions-EKS-Admin` (`infra/github-ci`)

**Files:**
- Create: `infra/github-ci/eks-admin-role.tf`
- Modify: `infra/github-ci/README.md`

- [ ] **Step 1: `infra/github-ci/eks-admin-role.tf`**

```hcl
# Role usada SÓ pelos botões "Ligar/Desligar cluster EKS" (.github/workflows/eks-*.yml).
# O Terraform do cluster (infra/eks) cria/destrói EKS, EC2, ELB, IAM roles e OIDC provider,
# então a role precisa de AdministratorAccess. A porta de entrada é estreita: só um workflow
# do repo fcg-orchestration rodando no GitHub Environment `aws-eks` — que só aceita a branch
# main — consegue assumi-la (sub exato, sem curinga).
locals {
  github_oidc_provider_arn = "arn:aws:iam::915153720516:oidc-provider/token.actions.githubusercontent.com"
  eks_admin_subject        = "repo:FIAP-POS-TECH-TEAM-10/fcg-orchestration:environment:aws-eks"
}

resource "aws_iam_role" "eks_admin" {
  name                 = "GitHubActions-EKS-Admin"
  description          = "Botoes liga/desliga do cluster fcg-eks (fcg-orchestration, environment aws-eks)"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.eks_admin_subject
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_admin" {
  role       = aws_iam_role.eks_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "eks_admin_role_arn" {
  value = aws_iam_role.eks_admin.arn
}
```

- [ ] **Step 2: `infra/github-ci/README.md`** — substituir o conteúdo inteiro por:

````markdown
# infra/github-ci — permissões permanentes do GitHub Actions

Terraform **permanente** (nunca destruído pelos scripts liga/desliga).

| Recurso | Para quê |
|---|---|
| Inline policy `fcg-github-eks-describe` na role `GitHubActions-ECS-Deploy-Role` | `eks:DescribeCluster` no `fcg-eks` — o `ci-cd.yml` dos serviços usa para saber se o cluster está ligado (`ResourceNotFoundException` → deploy pulado; `ACTIVE` → rolling update) |
| Role `GitHubActions-EKS-Admin` (AdministratorAccess) | botões **Ligar/Desligar cluster EKS** (`.github/workflows/eks-*.yml`). Só pode ser assumida por workflow do `fcg-orchestration` no Environment `aws-eks` (que só aceita a branch `main`) |

```bash
export AWS_PROFILE=fcg-team
cd infra/github-ci && terraform init && terraform apply
```
````

- [ ] **Step 3: Validar e conferir o plano**

```bash
export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1
cd fcg-orchestration/infra/github-ci
terraform init -input=false -no-color >/dev/null && terraform validate && terraform fmt -check
terraform plan -input=false -no-color | grep -E "^Plan:|will be"
```
Expected: `Success!`; `Plan: 2 to add, 0 to change, 0 to destroy.` com `aws_iam_role.eks_admin` e `aws_iam_role_policy_attachment.eks_admin` (a policy `github_eks_describe` existente sem mudança).

- [ ] **Step 4: Aplicar** (cria uma role IAM — sem custo; aprovado no design)

```bash
terraform apply -input=false -auto-approve -no-color | grep -E "^Apply complete|eks_admin_role_arn"
aws iam get-role --role-name GitHubActions-EKS-Admin --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals' --output json | tr -d '\r'
```
Expected: `Apply complete! Resources: 2 added`; o `sub` exato `repo:FIAP-POS-TECH-TEAM-10/fcg-orchestration:environment:aws-eks`.

- [ ] **Step 5: Commit**

```bash
cd fcg-orchestration
git add infra/github-ci/eks-admin-role.tf infra/github-ci/README.md
git commit -m "feat(ci): role GitHubActions-EKS-Admin para os botões liga/desliga (environment aws-eks)"
```

---

### Task 2: Role nova como admin do cluster

**Files:**
- Modify: `infra/eks/variables.tf` (variável `admin_principal_arns`)

- [ ] **Step 1: Editar** — no `default` de `admin_principal_arns`, depois da linha `"arn:aws:iam::915153720516:user/dev-admin",` adicionar:

```hcl
    # Botões Ligar/Desligar do GitHub Actions (infra/github-ci) — sem isso o eks-up rodando no
    # GitHub cria o cluster mas não consegue instalar o LB Controller nem aplicar os serviços.
    "arn:aws:iam::915153720516:role/GitHubActions-EKS-Admin",
```

- [ ] **Step 2: Validar**

Run: `cd fcg-orchestration/infra/eks && terraform validate && terraform fmt -check; echo exit=$?`
Expected: `Success!` e `exit=0`.

- [ ] **Step 3: Commit**

```bash
cd fcg-orchestration
git add infra/eks/variables.tf
git commit -m "feat(eks): role GitHubActions-EKS-Admin como admin do cluster"
```

---

### Task 3: Scripts aceitam credencial do ambiente

**Files:**
- Modify: `scripts/eks-up.sh`, `scripts/eks-down.sh`

- [ ] **Step 1: `scripts/eks-up.sh`** — substituir a linha:

```bash
export AWS_PROFILE="${AWS_PROFILE:-fcg-team}"
```
por:
```bash
# Local: usa o profile fcg-team. No GitHub Actions (OIDC) as credenciais já vêm no ambiente
# (AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN) e um profile inexistente quebraria a autenticação.
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -z "${AWS_PROFILE:-}" ]; then
  export AWS_PROFILE="fcg-team"
fi
```
E nas duas mensagens de erro da checagem de conta, trocar `'$AWS_PROFILE'` por `'${AWS_PROFILE:-credenciais do ambiente}'` (com `set -u`, `$AWS_PROFILE` vazio/indefinido quebraria a própria mensagem):
```bash
  echo "Erro: não autenticou na AWS com o profile '${AWS_PROFILE:-credenciais do ambiente}'."
```
```bash
  echo "Erro: profile '${AWS_PROFILE:-credenciais do ambiente}' aponta para a conta $account (esperado $EXPECTED_ACCOUNT)."
```

- [ ] **Step 2: `scripts/eks-down.sh`** — exatamente as mesmas três trocas do Step 1 (a linha `export AWS_PROFILE=...` e as duas mensagens de erro).

- [ ] **Step 3: Sintaxe e LF**

Run: `cd fcg-orchestration && bash -n scripts/eks-up.sh && bash -n scripts/eks-down.sh && echo OK; tr -cd '\r' < scripts/eks-up.sh | wc -c; tr -cd '\r' < scripts/eks-down.sh | wc -c; grep -c 'AWS_PROFILE:-credenciais' scripts/eks-up.sh scripts/eks-down.sh`
Expected: `OK`, `0`, `0`, `2` em cada arquivo.

- [ ] **Step 4: Teste local (cluster desligado — inofensivo, ~1–2 min)**

Run: `cd fcg-orchestration && env -u AWS_PROFILE -u AWS_ACCESS_KEY_ID ./scripts/eks-down.sh 2>&1 | tail -4`
Expected: termina com `Cluster desligado.` (usou o profile `fcg-team` automaticamente; o destroy num state vazio não faz nada). Se o state tiver sobras de um ciclo anterior, elas são destruídas — conferir a saída e reportar.

- [ ] **Step 5: Commit**

```bash
git add scripts/eks-up.sh scripts/eks-down.sh
git commit -m "feat(eks): scripts usam credenciais do ambiente quando existirem (GitHub Actions)"
```

---

### Task 4: Workflows

**Files:**
- Create: `.github/workflows/eks-ligar.yml`, `.github/workflows/eks-desligar.yml`

- [ ] **Step 1: `.github/workflows/eks-ligar.yml`**

```yaml
# Botão "Ligar cluster EKS": cria o cluster fcg-eks + serviços (scripts/eks-up.sh) com a role
# GitHubActions-EKS-Admin (infra/github-ci). Custa ~US$ 0,20/h — desligue ao terminar; o workflow
# "Desligar cluster EKS" também roda sozinho toda noite às 03:00 (BRT).
name: Ligar cluster EKS

on:
  workflow_dispatch:
    inputs:
      testar:
        description: Rodar o teste ponta a ponta (scripts/eks-e2e.sh) depois de ligar
        type: boolean
        default: true

# Ligar e desligar nunca rodam ao mesmo tempo (mesmo grupo nos dois workflows); o segundo espera.
concurrency:
  group: eks-cluster
  cancel-in-progress: false

permissions:
  id-token: write # OIDC com a AWS
  contents: read

jobs:
  ligar:
    name: Ligar cluster (eks-up)
    runs-on: ubuntu-latest
    environment: aws-eks # só a branch main pode usar (trust da role exige este environment)
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      - name: Login na AWS (OIDC → GitHubActions-EKS-Admin)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::915153720516:role/GitHubActions-EKS-Admin
          role-duration-seconds: 3600
          aws-region: sa-east-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_wrapper: false

      - name: Ligar (scripts/eks-up.sh)
        run: ./scripts/eks-up.sh

      - name: Teste ponta a ponta (scripts/eks-e2e.sh)
        if: inputs.testar
        run: ./scripts/eks-e2e.sh

      - name: Resumo
        run: |
          host="$(kubectl get ingress fcgames -n fcgames -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || true)"
          {
            echo "### ✅ Cluster \`fcg-eks\` ligado"
            echo "**URL pública:** http://${host:-ainda-sem-endereco}"
            echo '```'
            kubectl get pods -n fcgames
            echo '```'
            echo "💸 Custa ~US\$ 0,20/h. Ao terminar, rode **[Desligar cluster EKS](${{ github.server_url }}/${{ github.repository }}/actions/workflows/eks-desligar.yml)**."
            echo "🌙 Se ninguém desligar, o desligamento automático roda às 03:00 (BRT)."
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Aviso de falha
        if: failure()
        run: |
          {
            echo "### ⚠️ O ligar falhou — o cluster pode ter ficado LIGADO (cobrando)"
            echo "Rode **[Desligar cluster EKS](${{ github.server_url }}/${{ github.repository }}/actions/workflows/eks-desligar.yml)** ou espere o desligamento automático das 03:00 (BRT)."
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 2: `.github/workflows/eks-desligar.yml`**

```yaml
# Botão "Desligar cluster EKS" (scripts/eks-down.sh) + desligamento automático toda noite às
# 03:00 (BRT), caso alguém tenha esquecido o cluster ligado. Com o cluster já desligado não faz nada.
name: Desligar cluster EKS

on:
  workflow_dispatch:
  schedule:
    - cron: "0 6 * * *" # 06:00 UTC = 03:00 BRT

# Mesmo grupo do "Ligar cluster EKS": nunca rodam ao mesmo tempo.
concurrency:
  group: eks-cluster
  cancel-in-progress: false

permissions:
  id-token: write # OIDC com a AWS
  contents: read

jobs:
  desligar:
    name: Desligar cluster (eks-down)
    runs-on: ubuntu-latest
    environment: aws-eks # só a branch main pode usar (trust da role exige este environment)
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@v4

      - name: Login na AWS (OIDC → GitHubActions-EKS-Admin)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::915153720516:role/GitHubActions-EKS-Admin
          role-duration-seconds: 3600
          aws-region: sa-east-1

      - name: Cluster existe?
        id: cluster
        run: |
          if aws eks describe-cluster --name fcg-eks --query cluster.status --output text 2>err.txt; then
            echo "existe=true" >> "$GITHUB_OUTPUT"
          elif grep -q ResourceNotFoundException err.txt; then
            echo "existe=false" >> "$GITHUB_OUTPUT"
            echo "### 💤 Nada a fazer: o cluster \`fcg-eks\` já está desligado" >> "$GITHUB_STEP_SUMMARY"
          else
            cat err.txt
            exit 1
          fi

      - uses: hashicorp/setup-terraform@v3
        if: steps.cluster.outputs.existe == 'true'
        with:
          terraform_wrapper: false

      - name: Desligar (scripts/eks-down.sh)
        if: steps.cluster.outputs.existe == 'true'
        run: |
          set -o pipefail
          ./scripts/eks-down.sh | tee eks-down.log

      - name: Resumo
        if: steps.cluster.outputs.existe == 'true'
        run: |
          {
            echo "### 🛑 Cluster \`fcg-eks\` desligado"
            echo '```'
            grep -E "Destroy complete|ATENÇÃO|aws elbv2 delete|Clusters EKS" eks-down.log || true
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 3: Lint**

Run (na raiz do workspace): `MSYS_NO_PATHCONV=1 docker run --rm -v "$(cygpath -w "$PWD/fcg-orchestration"):/repo" -w /repo rhysd/actionlint:latest -color=false`
Expected: nenhuma saída (exit 0). (Docker Desktop precisa estar rodando.)

- [ ] **Step 4: LF**

Run: `cd fcg-orchestration && tr -cd '\r' < .github/workflows/eks-ligar.yml | wc -c; tr -cd '\r' < .github/workflows/eks-desligar.yml | wc -c`
Expected: `0` e `0`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/eks-ligar.yml .github/workflows/eks-desligar.yml
git commit -m "feat(ci): botões Ligar/Desligar cluster EKS + desligamento automático às 03:00 BRT"
```

---

### Task 5: README do orchestration

**Files:**
- Modify: `README.md` (raiz do `fcg-orchestration`)

- [ ] **Step 1: Inserir seção** logo **antes** da linha `## 9. Troubleshooting`:

````markdown
## 8.1 Cluster EKS (AWS) — ligar/desligar pelo GitHub

O cluster `fcg-eks` (Fase 4) **não fica ligado**: custa ~US$ 0,20/h (sai dos créditos da conta).
Qualquer pessoa do time com acesso de escrita ao repo liga/desliga pela aba **Actions**:

| Workflow | O que faz |
|---|---|
| **Ligar cluster EKS** (Run workflow) | `scripts/eks-up.sh` (~20 min): cluster + serviços de `k8s/eks`; opção "testar" roda o `eks-e2e.sh`. O resumo do run mostra a **URL do ALB** |
| **Desligar cluster EKS** (Run workflow) | `scripts/eks-down.sh` (~12 min): apaga Ingress/ALB e destrói o cluster |
| **Desligar cluster EKS** (automático) | toda noite às **03:00 (BRT)** — se estiver ligado, desliga; se não, "nada a fazer" |

- Os dois rodam no Environment `aws-eks` (só a branch `main`) com a role `GitHubActions-EKS-Admin` (ver `infra/github-ci/`). Nunca rodam ao mesmo tempo.
- Também dá para rodar os scripts da própria máquina (`./scripts/eks-up.sh` / `eks-down.sh`, profile `fcg-team`). Se o workflow estiver rodando ao mesmo tempo, o segundo falha com "state locked" — sem dano, é só esperar.
- Se o "Ligar" falhar no meio, o cluster pode ter ficado ligado: rode o "Desligar".

Criação do Environment (uma vez, precisa de admin no repo):

```bash
gh api -X PUT repos/FIAP-POS-TECH-TEAM-10/fcg-orchestration/environments/aws-eks \
  -F "deployment_branch_policy[protected_branches]=false" \
  -F "deployment_branch_policy[custom_branch_policies]=true"
gh api -X POST repos/FIAP-POS-TECH-TEAM-10/fcg-orchestration/environments/aws-eks/deployment-branch-policies \
  -f name=main -f type=branch
```

````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README — ligar/desligar o cluster EKS pelo GitHub"
```

---

### Task 6: Environment `aws-eks`

- [ ] **Step 1: Criar** (usuário é admin do repo; aprovado no design)

```bash
gh api -X PUT repos/FIAP-POS-TECH-TEAM-10/fcg-orchestration/environments/aws-eks \
  -F "deployment_branch_policy[protected_branches]=false" \
  -F "deployment_branch_policy[custom_branch_policies]=true" --jq '.name'
gh api -X POST repos/FIAP-POS-TECH-TEAM-10/fcg-orchestration/environments/aws-eks/deployment-branch-policies \
  -f name=main -f type=branch --jq '.name'
```
Expected: `aws-eks` e `main`.

- [ ] **Step 2: Conferir**

```bash
gh api repos/FIAP-POS-TECH-TEAM-10/fcg-orchestration/environments/aws-eks --jq '{name, policy: .deployment_branch_policy, rules: [.protection_rules[].type]}'
gh api repos/FIAP-POS-TECH-TEAM-10/fcg-orchestration/environments/aws-eks/deployment-branch-policies --jq '[.branch_policies[].name]'
```
Expected: `custom_branch_policies: true`, `protected_branches: false`; branch policies `["main"]`; `rules` com `branch_policy` (sem `required_reviewers`).

---

### Task 7: ⚠️ PR, merge e teste da trava

- [ ] **Step 1: Pedir confirmação** para push + PR.

- [ ] **Step 2: Push + PR**

```bash
cd fcg-orchestration
git push -u origin feature/eks-botoes
gh pr create --base main --head feature/eks-botoes \
  --title "Fase 4 parte 3b: botões Ligar/Desligar cluster EKS no GitHub" \
  --body "Botões **Ligar cluster EKS** e **Desligar cluster EKS** (Actions), com desligamento automático às 03:00 BRT. Role \`GitHubActions-EKS-Admin\` (infra/github-ci, já aplicada) só assumível pelo Environment \`aws-eks\` (branch main). Scripts passam a usar o profile \`fcg-team\` só sem credencial no ambiente. Ver docs/superpowers/specs/2026-10-12-eks-botoes-design.md."
```

- [ ] **Step 3: Usuário mergeia o PR** (os workflows só aparecem como botão depois de estarem na `main`).

- [ ] **Step 4: Teste da trava** — disparar o Desligar a partir da branch (que ainda existe no remoto):

```bash
gh workflow run eks-desligar.yml -R FIAP-POS-TECH-TEAM-10/fcg-orchestration --ref feature/eks-botoes
sleep 10
id=$(gh run list -R FIAP-POS-TECH-TEAM-10/fcg-orchestration --workflow eks-desligar.yml --branch feature/eks-botoes --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch $id -R FIAP-POS-TECH-TEAM-10/fcg-orchestration --exit-status; echo exit=$?
gh run view $id -R FIAP-POS-TECH-TEAM-10/fcg-orchestration --log-failed 2>&1 | head -5; gh run view $id -R FIAP-POS-TECH-TEAM-10/fcg-orchestration --json jobs --jq '.jobs[].conclusion'
```
Expected: run **falha**, job sem executar passos, mensagem do tipo "Branch \"feature/eks-botoes\" is not allowed to deploy to aws-eks due to environment protection rules".

- [ ] **Step 5: Desligar na `main` com cluster desligado** (sem custo)

```bash
gh workflow run eks-desligar.yml -R FIAP-POS-TECH-TEAM-10/fcg-orchestration --ref main
```
Acompanhar o run: Expected `success`, resumo "💤 Nada a fazer: o cluster `fcg-eks` já está desligado" — valida OIDC + trust + Environment + `describe-cluster` com a role nova.

---

### Task 8: ⚠️ Ciclo real pelos botões (~US$ 0,20 — pedir confirmação)

- [ ] **Step 1: Ligar** — `gh workflow run eks-ligar.yml -R FIAP-POS-TECH-TEAM-10/fcg-orchestration --ref main -f testar=true` e acompanhar (~25 min, `gh run watch`).
Expected: run verde; passos `eks-up.sh` e `eks-e2e.sh` OK (`OK — fluxo completo passou`); resumo com a URL do ALB e os pods.

- [ ] **Step 2: Acesso da máquina local**

```bash
export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1
aws eks update-kubeconfig --name fcg-eks --region sa-east-1 >/dev/null && kubectl get pods -n fcgames
```
Expected: os 4 deployments `Running` (cluster criado pela role do GitHub continua acessível aos admins humanos).

- [ ] **Step 3: Desligar** — `gh workflow run eks-desligar.yml -R FIAP-POS-TECH-TEAM-10/fcg-orchestration --ref main` e acompanhar (~12 min).
Expected: verde; resumo com `Destroy complete!` e `Clusters EKS na conta: (nenhum)`, sem "ATENÇÃO". Conferir:
```bash
aws eks list-clusters --query clusters --output text | tr -d '\r'   # vazio
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text | tr -d '\r'   # vazio
```

- [ ] **Step 4: Desligar de novo** (cluster desligado) → "💤 Nada a fazer", verde.

---

### Task 9: CLAUDE.md

- [ ] **Step 1:** em `C:\GIT\FIAP\FIAP-POS-TECH-TEAM-10\CLAUDE.md`, seção 2.6, substituir a linha `- Próximo (opcional): parte 3b — ligar/desligar o cluster pelo GitHub.` por:

```markdown
**Fase 4 — parte 3b: botões no GitHub** (feito):
- Actions do `fcg-orchestration`: **Ligar cluster EKS** (`eks-ligar.yml` → `eks-up.sh` + opcional `eks-e2e.sh`; resumo com a URL do ALB) e **Desligar cluster EKS** (`eks-desligar.yml` → `eks-down.sh`). Qualquer pessoa com escrita no repo, sem aprovação.
- **Desligamento automático toda noite às 03:00 BRT** (cron `0 6 * * *`); no-op se já desligado.
- Role `GitHubActions-EKS-Admin` (AdministratorAccess) em `infra/github-ci/` — trust **só** `repo:FIAP-POS-TECH-TEAM-10/fcg-orchestration:environment:aws-eks`; Environment `aws-eks` aceita só a `main`. Também está em `admin_principal_arns` do cluster.
- Scripts usam o profile `fcg-team` só quando não há credencial no ambiente (no GitHub vem do OIDC).
- Ligar e desligar compartilham o grupo de concorrência `eks-cluster`; script local + workflow ao mesmo tempo → "state locked" (sem dano).
```

- [ ] **Step 2: Mostrar ao usuário** o resumo final.
