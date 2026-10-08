# Serviços no EKS (`k8s/eks`)

Manifests (YAML + Kustomize) dos serviços do FCGames no cluster `fcg-eks`.
Aplicados automaticamente pelo `scripts/eks-up.sh`. Design:
[`docs/superpowers/specs/2026-10-06-eks-services-design.md`](../../docs/superpowers/specs/2026-10-06-eks-services-design.md).

## O que roda (namespace `fcgames`)

| Deployment | Containers | Porta | Imagem (ECR) |
|---|---|---|---|
| `users-api` | api | 5001 | `fcg-users-service:latest` |
| `catalog-api` | api + worker (mesmo pod, SQLite em `emptyDir`) | 5002 | `fcg-catalog-service:latest` / `:worker-latest` |
| `payments-api` | api + worker (mesmo pod, SQLite em `emptyDir`) | 5003 | `fcg-payments-service:latest` / `:worker-latest` |
| `redis` | redis (cache do catalog) | 6379 | `public.ecr.aws/docker/library/redis:alpine` |

Um Ingress (`fcgames`) cria **um ALB** com rotas por path:
`/usuarios` → users · `/jogos`, `/compras`, `/biblioteca`, `/desejos` → catalog · `/pagamentos` → payments.

Vem do Terraform (`infra/eks`), não daqui: namespace, ServiceAccounts com Pod Identity
(credenciais AWS sem access key) e o Secret `fcg-jwt` (`JWT__KEY`).

**SQLite é efêmero**: cada restart/deploy de pod zera Pedidos/Bibliotecas/Pagamentos/Usuários
(o admin seed é recriado). Jogos e Desejos ficam no DynamoDB e persistem. Por isso `replicas: 1`
e **sem HPA** (cada réplica teria seu próprio banco).

## Comandos

```bash
kubectl apply -k k8s/eks                          # aplicar (o eks-up.sh já faz)
kubectl kustomize k8s/eks                         # ver o YAML final sem aplicar
kubectl get pods -n fcgames
kubectl logs -n fcgames deploy/catalog-api -c worker -f
kubectl rollout restart deploy/users-api -n fcgames  # rolling update sem downtime
./scripts/eks-e2e.sh                              # fluxo completo pelo ALB
```

## Sem downtime — como funciona

`maxSurge: 1` / `maxUnavailable: 0` + readiness `/health` + *pod readiness gate* do ALB
(label no namespace) + `preStop` de 15 s casado com `deregistration_delay` de 15 s no target group.

## Troubleshooting

| Sintoma | Causa provável |
|---|---|
| `ImagePullBackOff` | imagem não existe no ECR (lifecycle mantém só as últimas 10) — rebuild/push |
| `CrashLoopBackOff` no worker | ver `kubectl logs ... -c worker --previous`; 1 restart no 1º start é normal (lock de migração) |
| 502/503 no ALB logo após subir | target group ainda registrando — aguarde 1-2 min |
| Pod `Pending` | memória dos 2× t3.small esgotada — `kubectl describe pod` e `kubectl top pods -n fcgames` |
