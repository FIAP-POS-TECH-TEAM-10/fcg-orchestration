# Segurança e segredos

Verificado em 2026-11-10. **Nunca escreva o valor de um segredo** em resposta, doc ou commit.

Nenhum valor de senha ou chave está em arquivo versionado (varredura de 2026-11-04 = 0). O histórico
do git ainda contém valores de exemplo antigos.

| Segredo | Onde fica | Como chega ao serviço |
|---|---|---|
| Chave do JWT | EKS: Secret `fcg-jwt`, gerado aleatório pelo Terraform a cada criação. Local: `JWT_KEY` no `.env` | env `JWT__KEY` |
| Senha do admin do app | GitHub: secret `ADMIN_PASSWORD` do Environment `aws-eks` → Terraform → Secret `fcg-admin`. Local: `.env` | env `ADMIN__PASSWORD` (users) |
| Senha do admin do Grafana | GitHub: `GRAFANA_PASSWORD` → Secret `fcg-grafana` | env do pod do Grafana |
| RabbitMQ | só local: `RABBITMQ_USER`/`RABBITMQ_PASS` no `.env` | `RabbitMQ__Username`/`__Password` |
| Pacote NuGet | `NUGET_AUTH_TOKEN` (local), secret `PAT_PACKAGES` (CI) | build da imagem (`--secret id=GITHUB_TOKEN`) |

- Credenciais AWS: nenhuma chave estática. CI usa OIDC; pods usam **Pod Identity** (uma role por
  serviço, só com as permissões dele).
- Sem as variáveis obrigatórias os serviços **não sobem** (falha explícita), em vez de usar padrão.
- `.env` é ignorado pelo git (modelo em `.env.example`), lido literalmente pelo `eks-up.sh`
  (nunca `source`). Evite `"`, `\`, `$` e espaço nos valores.
- `http-client.private.env.json` (JetBrains) é ignorado pelo git.
- Os `secret.yaml` dos caminhos Kind são modelos com `REPLACE_ME`.
- Decisão: K8s Secret em vez de AWS Secrets Manager (o enunciado aceita os dois).
- Riscos aceitos: senhas também ficam no estado do Terraform (S3); PR na `main` do orchestration não
  exige aprovação.
