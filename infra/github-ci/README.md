# infra/github-ci — permissões permanentes do GitHub Actions

Terraform **permanente** (os scripts de ligar/desligar não mexem aqui). O GitHub entra na AWS por
OIDC, sem chave guardada.

| Recurso | Para quê |
|---|---|
| Policy `fcg-github-eks-describe` na role `GitHubActions-ECS-Deploy-Role` | o `ci-cd.yml` dos serviços descobre se o cluster está ligado (`eks:DescribeCluster`): ligado → rolling update; desligado → deploy pulado |
| Role `GitHubActions-EKS-Admin` (AdministratorAccess, sessões de até 2 h) | botões Ligar/Desligar. Só um workflow deste repositório no Environment `aws-eks` consegue assumi-la |

```bash
export AWS_PROFILE=fcg-team
cd infra/github-ci && terraform init && terraform apply
```

## Environment `aws-eks` (configurado uma vez, por um admin do repositório)

- Aceita só a branch `main` (dispatch de outra branch é recusado).
- Secrets: `ADMIN_PASSWORD` (admin do app) e `GRAFANA_PASSWORD` (admin do Grafana), em
  Settings → Environments → `aws-eks`.

```bash
gh api -X PUT repos/FIAP-POS-TECH-TEAM-10/fcg-orchestration/environments/aws-eks \
  -F "deployment_branch_policy[protected_branches]=false" \
  -F "deployment_branch_policy[custom_branch_policies]=true"
gh api -X POST repos/FIAP-POS-TECH-TEAM-10/fcg-orchestration/environments/aws-eks/deployment-branch-policies \
  -f name=main -f type=branch
```
