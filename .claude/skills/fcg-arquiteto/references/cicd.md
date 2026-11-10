# CI/CD

Verificado em 2026-11-10. Fonte: `.github/workflows/` de cada repositório.

## Serviços: `ci-cd.yml` (users, catalog, payments)

| Gatilho | O que roda |
|---|---|
| PR para `main` | build → testes (se houver `*Tests.csproj`) → imagem(ns) → Trivy |
| push na `main` ou manual na `main` | o mesmo + push no ECR (`:<sha7>`, `:latest`, `worker-*`) + `kubectl set image` e `rollout status` no EKS |
| manual em outra branch | só build, testes, imagem e Trivy |

- Cluster desligado → o deploy é pulado com aviso e o run fica verde; a `:latest` entra no próximo Ligar.
- Merge na `main` → pod novo em ~2,5 min, sem downtime.
- Autenticação AWS por OIDC (`GitHubActions-ECS-Deploy-Role`); pacote de eventos com o secret `PAT_PACKAGES`.
- Trivy só reporta (não bloqueia): tabela no resumo do run e alertas em **Security → Code scanning**.
  Desde 10/11/2026 as imagens estão com 0 CRITICAL e 0 HIGH (removidos `libicu-dev`/`icu-devtools`,
  SQLite nativo 3.53.3, `Microsoft.OpenApi` 2.13.0).

## Orchestration: botões

- **Ligar cluster EKS** (`eks-ligar.yml`): `eks-up.sh` (~15 min) + opção "testar" (`eks-e2e.sh`);
  resumo com a URL da API e do Grafana.
- **Desligar cluster EKS** (`eks-desligar.yml`): manual ou automático às 03:00 BRT (cron `0 6 * * *`).
  O GitHub desativa cron após 60 dias sem atividade no repositório.
- Ambos no Environment `aws-eks` (só `main`), role `GitHubActions-EKS-Admin`, mesmo grupo de
  concorrência. Qualquer pessoa com escrita no repo pode rodar, sem aprovação.
- `main` do orchestration protegida: só por PR (sem aprovação exigida), sem force push.

## Outros

- Lambda: push na `main` → `deploy-on-pr-merge.yml` (build + `terraform apply`); PR para `develop`
  → `terraform-pr-develop.yml` (plan comentado no PR).
- Pacote de eventos: `publish.yml` (preview `1.0.0-preview.<run>` na `main`; tag `v*.*.*` = estável).
