# payments (fcg-payments-service)

Verificado em 2026-11-10. Fonte: `fcg-payments-service/README.md`, `Worker/Consumers/PedidoRealizadoEventoConsumer.cs`, `Worker/Program.cs`.

- `Payments.Api` (HTTP :5003): só `GET /pagamentos/{orderId}` (autenticado), `/health`, `/health/live`.
  Não expõe `/metrics`.
- `Payments.Worker`: consome `PedidoRealizadoEvento` na fila `payments-pedido-realizado`.
  1. Pedido já tem pagamento → ignora (idempotência por `PedidoId`, índice único).
  2. Regra: preço ≤ 0 → Rejeitado "Valor inválido"; preço > 100 → Rejeitado "Limite de crédito
     excedido"; demais → Aprovado (`AplicarRegra`).
  3. Grava `Pagamento` e publica `PagamentoProcessadoEvento`.
- Retry do consumer: 3 tentativas com 5 s, 10 s e 30 s.
- Dados: SQLite `Pagamentos` (API e worker no mesmo arquivo; efêmero no EKS).
- Variáveis: `JWT__KEY`, `JWT__ISSUER`, `ConnectionStrings__DefaultConnection`, `Messaging__Provider`,
  `AWS__Region`, `RabbitMQ__*`.
- AWS: pod `payments-api` (containers `api` e `worker`), ECR `fcg-payments-service`, role
  `fcg-eks-payments-api` (SQS/SNS).
- Sem projeto de testes.
