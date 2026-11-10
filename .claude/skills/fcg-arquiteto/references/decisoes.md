# Decisões

Verificado em 2026-11-10. ADRs em `fcg-orchestration/docs/`; specs em `docs/superpowers/specs/`.

| Decisão | Escolha | Por quê |
|---|---|---|
| Orquestração (Fase 4) | AWS EKS, criado e destruído por sessão (Terraform) | o enunciado exige Kubernetes gerenciado (ECS não vale); EKS não tem free tier |
| Nodes | 2× t3.small | plano FREE só aceita tipos elegíveis |
| Rede | VPC default sem NAT | NAT custaria ~US$ 35/mês |
| Entrada | 1 ALB via Ingress | uma URL para tudo; substituiu 3 API Gateways que quebravam ao trocar o IP da EC2 |
| Mensageria | MassTransit; RabbitMQ local, SNS/SQS na AWS | transporte por config, sem mudar código |
| Contratos | pacote NuGet `FCGames.IntegrationEvents` | uma fonte; MassTransit roteia por namespace + tipo |
| Banco | SQLite efêmero por pod; DynamoDB para jogos/desejos | zero custo/setup; NoSQL exigido pelo enunciado |
| Réplicas | 1 por serviço, sem HPA | cada réplica teria o seu SQLite |
| Worker | no mesmo pod da API | os dois precisam do mesmo arquivo SQLite |
| Segredos | K8s Secrets via Terraform + secrets do GitHub | enunciado aceita K8s Secret ou Secrets Manager; quem liga não precisa saber as senhas |
| Credenciais AWS | OIDC no CI, Pod Identity nos pods | nenhuma chave estática |
| Notificações na AWS | Lambda acionada por SQS | não fica um container ligado 24/7 |
| Observabilidade | Prometheus + Grafana dentro do cluster, Grafana em `/grafana` | sem EC2 extra; URL pública só leitura |
| Nomenclatura | domínio em português, scaffolding em inglês | ADR-001 |
| Notificações (worker) | projeto único, sem camadas | ADR-002: não tem domínio nem banco |
| Imagens | Dockerfile multi-stage sdk → aspnet, sem pacotes `-dev` | imagem menor; Trivy 0 CRITICAL/HIGH |
