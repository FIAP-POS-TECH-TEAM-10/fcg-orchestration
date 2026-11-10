# infra/eks — cluster fcg-eks

Terraform do cluster Kubernetes gerenciado (AWS EKS, conta `915153720516`, `sa-east-1`). **Liga e
desliga a cada sessão**: ~US$ 0,20/h ligado (control plane + 2× t3.small + ALB), pago com os créditos
da conta, que está no plano FREE. EKS não tem free tier.

## Ligar / desligar

Pelos botões do GitHub (ver o [README da raiz](../../README.md)) ou pela máquina, no Git Bash:

```bash
./scripts/eks-up.sh     # ~15 min; exige ADMIN_PASSWORD e GRAFANA_PASSWORD (ambiente ou .env)
./scripts/eks-down.sh   # ~12 min; apaga o ALB e destrói tudo (não precisa das senhas)
```

Pela máquina: AWS CLI v2, Terraform ≥ 1.5, kubectl, profile `fcg-team` e seu usuário IAM em
`admin_principal_arns` (`variables.tf`). Estado no S3 com lock no DynamoDB.

## O que é criado

| Recurso | Detalhe |
|---|---|
| Cluster `fcg-eks` | Kubernetes 1.36, VPC default, subnets públicas, sem NAT |
| Node group | 2× `t3.small` (o plano FREE recusa tipos maiores, como t3.medium) |
| Addons | vpc-cni, coredns, kube-proxy, eks-pod-identity-agent, metrics-server |
| AWS Load Balancer Controller | transforma o Ingress em um ALB público |
| Namespace `fcgames` + ServiceAccounts | `users-api`, `catalog-api`, `payments-api`, cada uma com role IAM própria via Pod Identity (SQS/SNS; o catalog também DynamoDB) |
| Secrets | `fcg-jwt` (chave do JWT, aleatória a cada criação), `fcg-admin` e `fcg-grafana` (senhas vindas de `ADMIN_PASSWORD`/`GRAFANA_PASSWORD`) |
| Acesso | admins do time (cluster-admin) e a role do GitHub Actions |

Fica **fora** do cluster e sobrevive ao desligar: ECR, DynamoDB (`Jogos`, `Desejos`), SQS/SNS,
Lambda de notificações e o estado do Terraform.

## Problemas comuns

| Sintoma | Solução |
|---|---|
| `Unauthorized` no kubectl | seu ARN não está em `admin_principal_arns` |
| `eks-up.sh` falhou no meio | rode de novo (continua de onde parou) ou rode o desligar |
| `eks-down.sh` parou com "ainda existem ALBs" | `kubectl get ingress -A` e os logs do `aws-load-balancer-controller` |
| Node group preso em CREATING | tipo de instância fora do plano FREE (`aws autoscaling describe-scaling-activities`) |
