# catalog (fcg-catalog-service)

Verificado em 2026-11-10. Fonte: `fcg-catalog-service/README.md`, controllers, `Worker/Consumers`, `SeedData.cs`.

- Projetos: `Catalogo.Api` (HTTP :5002) e `Catalogo.Worker` (consumers), mais Application/Domain/Infra/CrossCutting.
- Endpoints: `GET /jogos` (autenticado); `POST/PUT/DELETE /jogos` (Admin); `POST /compras` (202 +
  `orderId`); `GET /compras/{orderId}`; `GET /biblioteca/{usuarioId}`; `GET/POST /desejos`,
  `DELETE /desejos/{jogoId}`; `/health`, `/health/live`, `/metrics`.
- `UsuarioId` vem do JWT, não do corpo.
- Publica `PedidoRealizadoEvento` (`RealizarCompraCommandHandler`). Consome `UsuarioCriadoEvento`
  (fila `catalog-usuario-criado`: cria a biblioteca, ignora se já existe) e
  `PagamentoProcessadoEvento` (fila `catalog-pagamento-processado`: aprova ou rejeita o pedido,
  ignora pedido já finalizado).
- **Não há Transactional Outbox na main** (o código ficou na branch `feature/transactional-outbox`,
  não mesclada). A idempotência é a checagem nos consumers.
- Dados:
  - DynamoDB `Jogos` e `Desejos`: fora do cluster, persistem. A API cria as tabelas se faltarem e
    semeia Hades (R$ 49,90), Hollow Knight (R$ 29,90) e Cyberpunk 2077 (R$ 149,90) se estiver vazia.
  - SQLite `Bibliotecas`, `ItensBiblioteca`, `Pedidos`: API e worker no mesmo arquivo (no EKS, mesmo pod).
  - Redis: cache da listagem de jogos, invalidado ao criar/editar/remover; sem `ConnectionStrings__Redis`
    usa cache em memória.
- Variáveis: `JWT__KEY`, `JWT__ISSUER`, `ConnectionStrings__DefaultConnection`, `ConnectionStrings__Redis`,
  `DynamoDb__ServiceUrl` (vazio = DynamoDB da AWS), `DynamoDb__Region`, `Messaging__Provider`,
  `AWS__Region`, `RabbitMQ__*`.
- Swagger só em Development (no compose e no EKS roda Production).
- AWS: pod `catalog-api` (containers `api` e `worker`), ECR `fcg-catalog-service` (`latest`,
  `worker-latest`), role `fcg-eks-catalog-api` (SQS/SNS + DynamoDB `Jogos`/`Desejos`).
- Sem projeto de testes.
