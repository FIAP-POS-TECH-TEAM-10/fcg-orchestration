# Notificações

Verificado em 2026-11-10 (código + `aws sns list-subscriptions`, `aws lambda`, CloudWatch).

Os dois só escrevem logs simulando e-mails: `email-boas-vindas`, `email-confirmacao-compra`
(Aprovado), `email-pagamento-rejeitado` (Rejeitado).

## Local: `fcg-notifications-service` (worker)

- Roda no `docker compose` (`notifications-worker`, `/health` em :5004), consumindo do RabbitMQ:
  filas `notifications-usuario-criado` e `notifications-pagamento-processado`.
- Ver: `docker compose logs -f notifications-worker`.
- Projeto único `Fiap.FCGames.Notifications.Worker` (ADR-002). Não tem deploy na AWS.

## AWS: `fcg-notifications-lambda`

- Função `fiap-fcgames-notifications-lambda` (.NET 10, `provided.al2023`, ARM64, 512 MB, 30 s),
  gatilho na fila `fiap-fcgames-sqs-notifications-queue` (lotes de 10; DLQ `...-dlq`).
- Descobre o tipo pelo atributo `EventType` ou pelo envelope SNS/MassTransit.
- **Hoje só recebe `UsuarioCriadoEvento`**: a fila está assinada só no tópico
  `FCGames_IntegrationEvents-UsuarioCriadoEvento` (assinatura criada fora do Terraform). O tópico do
  `PagamentoProcessadoEvento` não está assinado e a política da fila não o permite → notificação de
  compra não acontece na AWS. Pendência.
- Logs: CloudWatch `/aws/lambda/fiap-fcgames-notifications-lambda` (Console → Lambda → Monitor →
  View CloudWatch logs). Rodou sem erros em 11/10 e 04/11/2026.
- Deploy: push na `main` do repositório → `deploy-on-pr-merge.yml` (build + `terraform apply`).
  Estado no S3 em `notification-lambda/terraform.tfstate`. Fica ligada sempre (custo só por invocação).
