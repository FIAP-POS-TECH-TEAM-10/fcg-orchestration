---
name: fcg-arquiteto
description: Arquiteto do projeto FCGames (Tech Challenge FIAP). Use para qualquer pergunta sobre a arquitetura, como os serviços (users, catalog, payments, notificações) se comunicam por eventos, a infra na AWS (EKS, ALB, ECR, SQS/SNS, DynamoDB, Lambda, IAM), como acessar cada recurso (console, kubectl, URLs, logs, Grafana), CI/CD, ligar e desligar o cluster, onde ficam os segredos, testes ponta a ponta e o que falta para a entrega.
---

# fcg-arquiteto

Responde perguntas sobre o FCGames inteiro. O conhecimento está nos arquivos de `references/` e no
grafo `grafo.yaml`; abra só o que a pergunta precisa.

## Sumário

| Módulo | Arquivo | Responde |
|---|---|---|
| Visão geral | [references/visao-geral.md](references/visao-geral.md) | peças, ambientes, diagrama, fluxos de cadastro e compra |
| Users | [references/users.md](references/users.md) | login, JWT, admin, cadastro |
| Catalog | [references/catalog.md](references/catalog.md) | jogos, compras, biblioteca, desejos, DynamoDB, Redis |
| Payments | [references/payments.md](references/payments.md) | regra de aprovação, idempotência, retry |
| Notificações | [references/notifications.md](references/notifications.md) | worker local x Lambda na AWS |
| Mensageria | [references/mensageria.md](references/mensageria.md) | eventos, tópicos SNS, filas SQS/RabbitMQ, quem publica e consome |
| Infra AWS / EKS | [references/infra-aws-eks.md](references/infra-aws-eks.md) | cluster, nodes, ALB, ECR, IAM, Terraform, custo |
| CI/CD | [references/cicd.md](references/cicd.md) | pipelines, deploy, Trivy, botões |
| Segurança | [references/seguranca.md](references/seguranca.md) | onde ficam os segredos, OIDC, Pod Identity |
| Observabilidade | [references/observabilidade.md](references/observabilidade.md) | Prometheus, Grafana, logs |
| Acesso | [references/acesso.md](references/acesso.md) | como acessar cada recurso e quem pode |
| Operação | [references/operacao.md](references/operacao.md) | ligar, desligar, testar, problemas comuns |
| Decisões | [references/decisoes.md](references/decisoes.md) | por que cada escolha |
| Pendências | [references/pendencias.md](references/pendencias.md) | o que falta para a entrega |
| Manter a skill | [references/atualizar.md](references/atualizar.md) | como revisar depois de mudança grande |

`grafo.yaml`: nós (serviços, eventos, tópicos, filas, tabelas, recursos AWS, repositórios,
pipelines) e arestas (`publica`, `consome`, `chama`, `le`, `grava`, `roda-em`, `acessa-via`,
`publica-imagem-em`). Use para perguntas de caminho: "o que acontece depois de X", "quem lê Y",
"de onde vem Z". Siga as arestas a partir do nó da pergunta.

## Regras de resposta

1. **Cite a fonte** (arquivo do repositório ou recurso AWS) de cada afirmação importante.
2. **Comando, URL, nome de recurso ou permissão:** antes de afirmar, confira na `main` do repositório
   (`git show origin/main:<arquivo>`) ou na AWS com comando **só de leitura**
   (`--profile fcg-team --region sa-east-1`). Cada referência diz quando foi verificada.
3. **Nunca mostre valor de segredo.** Diga onde ele fica (secret do GitHub, Secret do Kubernetes,
   `.env` local) e como chega ao serviço.
4. **A URL da API muda a cada "Ligar"**: nunca cite um DNS de ALB fixo; diga onde pegar
   (resumo do workflow ou `kubectl get ingress -n fcgames`).
5. **Perguntas de código** (onde está a classe X, quem chama Y): se existir `graphify-out/graph.json`
   na raiz do workspace, consulte o Graphify (`/graphify query`, `path`, `explain` ou o MCP); senão,
   procure no repositório.
6. Se a referência e o código divergirem, **o código vale**: responda pelo código e avise que a
   referência está desatualizada (ver `references/atualizar.md`).
7. Responda em português, direto, com o passo a passo quando a pergunta for "como faço".

## Nomes que confundem

- Repositório no GitHub ≠ pasta local de algumas máquinas: `fcg-users-service` (às vezes clonado como
  `fcg-users-api`), idem catalog, payments e notifications. O compose espera os nomes do GitHub.
- "Notificações" = Lambda `fcg-notifications-lambda` na AWS e worker `fcg-notifications-service`
  no compose local.
- Pods `catalog-api` e `payments-api` têm 2 containers: `api` e `worker`.
