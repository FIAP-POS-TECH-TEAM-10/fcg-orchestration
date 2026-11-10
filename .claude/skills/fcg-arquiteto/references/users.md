# users (fcg-users-service)

Verificado em 2026-11-10. Fonte: `fcg-users-service/README.md`, `UsuariosController.cs`, `Program.cs`.

- **Único emissor de JWT** (issuer `AppFiapFcGames`); os outros serviços só validam com a mesma
  `JWT__KEY`. `ValidateAudience = false`.
- Endpoints: `POST /usuarios` e `POST /usuarios/login` (anônimos); `GET /usuarios`,
  `GET /usuarios/{id}`, `PUT /usuarios/{id}` (Admin); `/health`, `/health/live`, `/metrics`.
- Publica `UsuarioCriadoEvento` após o cadastro (`CriarUsuarioCommandHandler`).
- **Admin**: na primeira subida cria `admin@fcgames.com` com a senha de `ADMIN__PASSWORD`
  (`AdminSeedConfig.RequirePassword`); sem ela o app não sobe. No EKS a senha vem do Secret `fcg-admin`.
- Dados: SQLite `Usuarios`. No EKS o arquivo é efêmero: cada deploy zera os usuários e recria o admin.
- Transporte escolhido por config (`MassTransitExtensions.AddMassTransitMessaging`):
  `Messaging__Provider=Sqs` → SNS/SQS; `RabbitMQ__Host` → RabbitMQ; nenhum → em memória.
- Swagger sempre registrado (`/swagger`), mas o ALB não roteia esse caminho.
- Testes: `app/src/Fiap.FCGames.Users.Tests` (3 testes do `AdminSeedConfig`), rodados no `ci-cd.yml`.
- AWS: pod `users-api`, ECR `fcg-users-service`, role `fcg-eks-users-api` (Pod Identity, SQS/SNS).
