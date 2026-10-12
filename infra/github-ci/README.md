# infra/github-ci — permissões permanentes do GitHub Actions

Terraform **permanente** (nunca destruído pelos scripts liga/desliga).

| Recurso | Para quê |
|---|---|
| Inline policy `fcg-github-eks-describe` na role `GitHubActions-ECS-Deploy-Role` | `eks:DescribeCluster` no `fcg-eks` — o `ci-cd.yml` dos serviços usa para saber se o cluster está ligado (`ResourceNotFoundException` → deploy pulado; `ACTIVE` → rolling update) |
| Role `GitHubActions-EKS-Admin` (AdministratorAccess, sessões de até 2h) | botões **Ligar/Desligar cluster EKS** (`.github/workflows/eks-*.yml`). Só pode ser assumida por workflow do `fcg-orchestration` no Environment `aws-eks` (que só aceita a branch `main`) |

```bash
export AWS_PROFILE=fcg-team
cd infra/github-ci && terraform init && terraform apply
```
