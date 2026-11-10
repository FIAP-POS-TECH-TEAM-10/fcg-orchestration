# Infra AWS / EKS

Verificado em 2026-11-10. Fonte: `fcg-orchestration/infra/eks`, `infra/github-ci`, `k8s/eks`, AWS (só leitura).

Conta `915153720516`, região `sa-east-1` (São Paulo). A conta está no **plano FREE**: créditos
(~US$ 146, válidos até 02/2027) e só tipos de EC2 elegíveis (t3.micro/small, t4g.*, c7i-flex.large,
m7i-flex.large); `t3.medium` é recusado e o node group trava em CREATING.

## Só existe com o cluster ligado (~US$ 0,20/h)

| Recurso | Detalhe |
|---|---|
| EKS `fcg-eks` | Kubernetes 1.36, VPC default, subnets públicas, sem NAT |
| Nodes | 2× `t3.small` (node group gerenciado) |
| Addons | vpc-cni, coredns, kube-proxy, eks-pod-identity-agent, metrics-server (porta 10251 liberada no SG) |
| AWS Load Balancer Controller | Ingress → **um ALB** (`k8s-fcgames-*`), rotas `/usuarios`, `/jogos`, `/compras`, `/biblioteca`, `/desejos`, `/pagamentos`, `/grafana` |
| Namespace `fcgames` | pods `users-api`, `catalog-api` (api+worker), `payments-api` (api+worker), `redis`, `prometheus`, `grafana`; 1 réplica cada, sem HPA (SQLite por pod) |
| Pod Identity | roles `fcg-eks-users-api`, `fcg-eks-catalog-api`, `fcg-eks-payments-api` |
| Secrets | `fcg-jwt`, `fcg-admin`, `fcg-grafana` |

Deploy sem downtime: `maxUnavailable: 0`, readiness `/health`, readiness gate do ALB (label no
namespace), `startupProbe`, `preStop` 15 s, `deregistration_delay` 15 s (medido: 582/582 respostas 200).

## Sempre existe (sobrevive ao desligar)

| Recurso | Nome |
|---|---|
| ECR | `fcg-users-service`, `fcg-catalog-service`, `fcg-payments-service` (lifecycle: últimas 10 imagens) |
| DynamoDB | `Jogos`, `Desejos`, `fiap-tech-challenge-tflocks` (lock do Terraform) |
| SNS / SQS | ver `mensageria.md` |
| Lambda | `fiap-fcgames-notifications-lambda` + log group no CloudWatch |
| S3 | `fiap-tech-challenge-tfstate-123456-915153720516-sa-east-1-an` (estado de `eks/`, `github-ci/`, Lambda, ECR) |
| IAM | `GitHubActions-ECS-Deploy-Role`, `GitHubActions-EKS-Admin`, provider OIDC do GitHub |

Sobras para limpar: ECR `fcg-observability-service`, `fcg-prometheus`, `fcg-grafana` (da EC2 de
observabilidade aposentada).

## Terraform

- `infra/eks`: o cluster (criado/destruído por `eks-up.sh`/`eks-down.sh`). Variáveis sensíveis
  `admin_password` e `grafana_password` viram os Secrets.
- `infra/github-ci`: permanente (roles do GitHub). Nunca destruído pelos scripts.
- `fcg-notifications-lambda/infra`: a Lambda e a fila dela.
- Nunca mudar recurso gerenciado pelo Terraform pelo console: o próximo Ligar/Desligar desfaz ou falha.

Histórico: a Fase 3 rodava em ECS on EC2 com 3 API Gateways (conta antiga `704516098616`); tudo
destruído na migração para o EKS.
