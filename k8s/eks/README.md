# k8s/eks — o que roda no cluster

Manifests (YAML + Kustomize) aplicados pelo `scripts/eks-up.sh` no namespace `fcgames`.

| Deployment | Containers | Imagem |
|---|---|---|
| `users-api` | api (5001) | ECR `fcg-users-service:latest` |
| `catalog-api` | api (5002) + worker | ECR `fcg-catalog-service:latest` / `:worker-latest` |
| `payments-api` | api (5003) + worker | ECR `fcg-payments-service:latest` / `:worker-latest` |
| `redis` | cache do catalog | `redis:alpine` (ECR público) |
| `prometheus` | coleta `/metrics` de users e catalog (sem acesso externo) | `prom/prometheus` |
| `grafana` | painel "FCGames — Observabilidade", anônimo só leitura | `grafana/grafana` |

Um Ingress cria **um ALB** com rotas por caminho: `/usuarios` → users · `/jogos`, `/compras`,
`/biblioteca`, `/desejos` → catalog · `/pagamentos` → payments · `/grafana` → Grafana.
A URL muda a cada "Ligar": veja no resumo do workflow ou com `kubectl get ingress -n fcgames`.

- Configuração comum em `config.env` (ConfigMap); segredos nos Secrets `fcg-jwt`, `fcg-admin` e
  `fcg-grafana`, criados pelo Terraform (`infra/eks`).
- SQLite em disco efêmero: cada restart ou deploy zera usuários, pedidos, bibliotecas e pagamentos
  (o admin é recriado). Por isso 1 réplica e sem HPA. Jogos e desejos ficam no DynamoDB.
- Deploy sem downtime: rolling update com readiness `/health`, readiness gate do ALB e `preStop` de 15 s.
- Grafana como admin (editar painel): `kubectl port-forward svc/grafana 3000:80 -n fcgames` e login
  `admin` com a senha de `GRAFANA_PASSWORD`. O ALB é HTTP, por isso não se loga por ele.

```bash
kubectl get pods -n fcgames
kubectl logs -n fcgames deploy/catalog-api -c worker -f
kubectl rollout restart deploy/users-api -n fcgames
./scripts/eks-e2e.sh                       # fluxo completo pelo ALB + Grafana + Prometheus
```

| Sintoma | Causa provável |
|---|---|
| `ImagePullBackOff` | imagem não existe no ECR (ficam as últimas 10): rode o pipeline do serviço |
| 502/503 logo depois de subir | o ALB ainda está registrando os pods: espere 1–3 min |
| Pod `Pending` | memória dos 2 nodes esgotada: `kubectl describe pod` e `kubectl top pods -n fcgames` |
| 1 restart do worker no início | normal (lock da migração do SQLite) |
