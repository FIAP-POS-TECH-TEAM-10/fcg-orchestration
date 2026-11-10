# Operação

Verificado em 2026-11-10. Fonte: `fcg-orchestration/README.md`, `scripts/`, `k8s/eks/README.md`.

## Ligar, testar, desligar (EKS)

1. GitHub → `fcg-orchestration` → Actions → **Ligar cluster EKS** → Run workflow (deixe "testar"
   marcado). ~15 min. O resumo traz a URL da API e do Grafana.
2. O teste ponta a ponta (`eks-e2e.sh`) faz: espera o ALB → cadastro → login → biblioteca criada →
   compra aprovada e rejeitada → pagamento → jogo na biblioteca → Grafana → targets do Prometheus.
3. Teste manual: `fcgames.eks.http` com a URL do ALB.
4. **Desligue** ao terminar: Actions → **Desligar cluster EKS** (~12 min). Rede de segurança: 03:00 BRT.

Pela máquina (Git Bash, profile `fcg-team`, senhas no `.env`): `./scripts/eks-up.sh`,
`./scripts/eks-e2e.sh`, `./scripts/eks-down.sh`.

## Deploy de uma mudança

PR no repositório do serviço → CI (build, testes, Trivy) → merge na `main` → imagem no ECR e rolling
update (~2,5 min) se o cluster estiver ligado. Acompanhe: `kubectl get pods -n fcgames -w`.

## Local

`docker compose up -d --build` no `fcg-orchestration` (repositórios clonados com os nomes do GitHub,
`.env` preenchido), roteiro em `fcgames.http`, `docker compose down -v` zera os dados.

## Problemas comuns

| Sintoma | Causa / solução |
|---|---|
| 502/503 logo após ligar | ALB registrando os pods: 1–3 min |
| `ImagePullBackOff` | imagem sumiu do ECR (ficam 10): rode o pipeline do serviço |
| Pod `Pending` | memória dos 2× t3.small: `kubectl top pods -n fcgames` |
| "state locked" no Terraform | script local e workflow juntos: espere o outro terminar |
| Ligar falhou no meio | rode o Desligar (limpa sobras) e ligue de novo |
| `dotnet restore` 401 | token do pacote vencido: `gh auth refresh -s read:packages`, `NUGET_AUTH_TOKEN=$(gh auth token)` |
| Dados sumiram após deploy | esperado: SQLite efêmero; jogos ficam no DynamoDB |
