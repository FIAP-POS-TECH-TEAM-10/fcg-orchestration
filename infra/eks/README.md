# Cluster EKS — fcg-eks

Cluster Kubernetes gerenciado (AWS EKS) da Fase 4. **Liga e desliga a cada sessão** para
não gerar custo — ele não fica de pé entre sessões.

Design: [`docs/superpowers/specs/2026-10-06-eks-cluster-design.md`](../../docs/superpowers/specs/2026-10-06-eks-cluster-design.md)

## Custo

~**US$ 0,20/h** ligado (control plane US$ 0,10 + 1× t3.medium ~0,07 + ALB ~0,03).
EKS não tem free tier. **Sempre rode o `eks-down.sh` ao terminar.**

## Pré-requisitos

- AWS CLI v2, Terraform ≥ 1.5, kubectl (no Windows, rodar os scripts pelo Git Bash)
- Profile AWS da conta do time: `aws configure --profile fcg-team` (conta `915153720516`)
- Seu usuário IAM em `admin_principal_arns` (`variables.tf`) — confira com
  `aws sts get-caller-identity`

## Ligar / desligar

```bash
./scripts/eks-up.sh     # ~15-20 min — cria tudo e configura o kubectl
./scripts/eks-down.sh   # ~10-15 min — apaga Ingress/ALB e destrói o cluster
```

Para usar outro profile: `AWS_PROFILE=meu-profile ./scripts/eks-up.sh`.

## O que é criado

| Recurso | Detalhe |
|---|---|
| Cluster `fcg-eks` | Kubernetes 1.36, VPC default, subnets públicas (sem NAT) |
| Node group | 1× t3.medium (AL2023). 2 nodes: `TF_VAR_node_desired_size=2 ./scripts/eks-up.sh` |
| Addons | vpc-cni, coredns, kube-proxy, eks-pod-identity-agent, metrics-server |
| AWS Load Balancer Controller | Ingress `ingressClassName: alb` → ALB internet-facing |
| Namespace `fcgames` | onde os serviços rodam |
| ServiceAccounts | `users-api`, `catalog-api`, `payments-api` — cada uma com role IAM via Pod Identity (SQS/SNS; catalog também DynamoDB) |
| Secret `fcg-jwt` | chave `jwt-key`, gerada aleatoriamente a cada criação |
| Acesso | admins do time (cluster-admin); role do GitHub Actions (edit só em `fcgames`) |

Fica **fora** do cluster e sobrevive ao destroy: ECR, DynamoDB, SQS/SNS, state no S3.

## Smoke test

```bash
kubectl apply -f infra/eks/manifests/smoke-test.yaml
kubectl get ingress smoke-nginx -w        # espera aparecer o ADDRESS (2-3 min)
curl http://<ADDRESS>/                    # página do nginx
kubectl delete -f infra/eks/manifests/smoke-test.yaml
```

## Troubleshooting

| Sintoma | Causa / solução |
|---|---|
| `error: You must be logged in to the server (Unauthorized)` | seu ARN não está em `admin_principal_arns` |
| `eks-up.sh` falhou no meio | rode de novo — o Terraform continua de onde parou |
| `eks-down.sh` parou com "ainda existem ALBs do cluster" | `kubectl get ingress -A`; logs: `kubectl logs -n kube-system deploy/aws-load-balancer-controller` |
| `eks-down.sh` com AVISO de cluster inacessível / parou com ALBs restantes | se os ALBs do cluster realmente já sumiram (`aws elbv2 describe-load-balancers`), rode `cd infra/eks && terraform destroy` manualmente |
| Service `type: LoadBalancer` | também cria um NLB `k8s-...` — apague (`kubectl delete svc <nome>`) antes do `eks-down.sh` |
| Ingress sem ADDRESS | `kubectl describe ingress <nome>` — normalmente subnet sem tag ou controller sem permissão |
| Versão do k8s entrou em extended support (US$ 0,60/h) | subir `kubernetes_version` em `variables.tf` |
