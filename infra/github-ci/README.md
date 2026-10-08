# infra/github-ci — permissões permanentes do GitHub Actions

Terraform **permanente** (nunca destruído pelos scripts liga/desliga). Hoje gerencia uma única
inline policy na role `GitHubActions-ECS-Deploy-Role`: `eks:DescribeCluster` no cluster `fcg-eks`.

O pipeline `ci-cd.yml` dos serviços usa essa permissão para saber se o cluster está ligado:
`ResourceNotFoundException` → deploy pulado (run verde); `ACTIVE` → rolling update.

```bash
export AWS_PROFILE=fcg-team
cd infra/github-ci && terraform init && terraform apply
```
