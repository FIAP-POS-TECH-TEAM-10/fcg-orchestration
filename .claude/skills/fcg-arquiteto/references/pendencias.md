# Pendências para a entrega (Fase 4)

Verificado em 2026-11-10. Confira o PDF do enunciado e o prazo, que não estão nos repositórios.

## Obrigatório

- [ ] **Busca avançada (OpenSearch/Elasticsearch)** no catalog: `/search` com fuzzy e ordenação por
  relevância. Não há código. Decidir onde roda (no cluster aperta a memória dos 2× t3.small).
- [ ] **Testes unitários no catalog** (payments também não tem). O pipeline já roda `dotnet test`
  quando existe `*Tests.csproj`.
- [ ] **Notificação de compra na AWS**: assinar a fila `fiap-fcgames-sqs-notifications-queue` no tópico
  `FCGames_IntegrationEvents-PagamentoProcessadoEvento` (e liberar na política da fila), de
  preferência no Terraform da Lambda.

## Entrega

- [ ] Vídeo com live deploy (conferir no PDF: até 25 ou 20 min).
- [ ] Relatório PDF (nomes, Discord, links).
- [ ] Repositórios acessíveis ao time e à banca.

## Melhorias

- [ ] `/metrics` no payments (entrar no Prometheus).
- [ ] Remover `scripts/ligar-tudo.sh` (religa o ECS destruído) e corrigir/remover `k8s/deploy.sh`
  (aplica os modelos de Secret).
- [ ] Apagar os ECR `fcg-observability-service`, `fcg-prometheus`, `fcg-grafana` (sobras).
- [ ] Transactional Outbox do catalog (branch `feature/transactional-outbox`, não mesclada) — opcional.
- [ ] Limpar branches antigas dos repositórios.

## Já resolvido (não repetir)

EKS, ECR, ALB/Ingress, CI/CD com rolling update, zero segredos versionados, DynamoDB, Redis,
Prometheus/Grafana no cluster, Trivy 0 CRITICAL/HIGH, testes do users, docs simplificadas (11/2026).
