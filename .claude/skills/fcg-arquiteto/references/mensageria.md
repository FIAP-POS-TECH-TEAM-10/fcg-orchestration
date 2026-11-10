# Mensageria

Verificado em 2026-11-10 (código + `aws sns list-topics/list-subscriptions`, `aws sqs list-queues`).

## Eventos (pacote `FCGames.IntegrationEvents` 1.0.0-preview.2, namespace `FCGames.IntegrationEvents`)

| Evento | Campos | Publica | Consome |
|---|---|---|---|
| `UsuarioCriadoEvento` | UsuarioId, Nome, Email, CriadoEmUtc, CorrelationId | users-api | catalog-worker, notificações |
| `PedidoRealizadoEvento` | PedidoId, UsuarioId, JogoId, NomeJogo, Preco, RealizadoEmUtc, CorrelationId | catalog-api | payments-worker |
| `PagamentoProcessadoEvento` | PedidoId, UsuarioId, JogoId, NomeJogo, Preco, Status, Motivo?, ProcessadoEmUtc, CorrelationId | payments-worker | catalog-worker, notificações (só local) |

Nunca copiar os records nos serviços: o MassTransit roteia por namespace + nome do tipo. Mudar
campo: editar em `fcg-integration-events`, publicar nova versão, atualizar os `PackageReference`.

## Transporte

`Messaging__Provider=Sqs` → SNS/SQS (EKS, `config.env`); vazio + `RabbitMQ__Host` → RabbitMQ (compose);
nenhum → em memória. O código de domínio não muda.

## Na AWS (sa-east-1)

| Tópico SNS | Fila SQS assinada | Consumidor |
|---|---|---|
| `FCGames_IntegrationEvents-UsuarioCriadoEvento` | `catalog-usuario-criado` | catalog-worker |
| ″ | `fiap-fcgames-sqs-notifications-queue` | Lambda de notificações |
| `FCGames_IntegrationEvents-PedidoRealizadoEvento` | `payments-pedido-realizado` | payments-worker |
| `FCGames_IntegrationEvents-PagamentoProcessadoEvento` | `catalog-pagamento-processado` | catalog-worker |

- Tópicos e filas dos serviços são criados pelo MassTransit na primeira conexão (não estão em Terraform).
- Erros: `catalog-pagamento-processado_error` e o tópico `MassTransit-Fault--...PagamentoProcessadoEvento--`
  guardam falhas; fila vazia é o normal.
- IAM: `sqs:ListQueues` e `sns:ListTopics` só aceitam `Resource: "*"`; sem isso o `Publish()` falha em silêncio.

## Local (RabbitMQ)

Filas `catalog-usuario-criado`, `catalog-pagamento-processado`, `payments-pedido-realizado`,
`notifications-usuario-criado`, `notifications-pagamento-processado`. Painel em
http://localhost:15672 (usuário e senha do `.env`).
