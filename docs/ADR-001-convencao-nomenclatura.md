# ADR-001 — Convenção de Nomenclatura: Domínio em Português, Scaffolding em Inglês

**Data:** 2026-06-20
**Status:** Aceito
**Autores:** Time FCGames (FIAP Pós-Tech Team 10)

---

## Contexto

O projeto FCGames migra um monólito .NET para 4 microsserviços. A equipe precisou decidir
o idioma a adotar em: nomes de entidades de domínio, tabelas de banco, campos de eventos,
rotas HTTP e nomes de classes de infraestrutura.

## Decisão

**Português** para tudo que é domínio de negócio.
**Inglês** para todo scaffolding técnico.

---

## Justificativa

- O time é fluente em português e o domínio do negócio (usuários, jogos, pedidos, pagamentos)
  é naturalmente expresso em português.
- Evita tradução forçada de termos com significado específico no contexto brasileiro
  (ex: "Compra" vs "Purchase", "Biblioteca" vs "Library").
- Reduz churn: apenas o UsersAPI tinha código real no momento da decisão; todos os demais
  serviços foram iniciados após o alinhamento.
- Consistência total entre camadas de domínio sem tradução:
  `Pedido` no controller → `Pedido` no evento → `Pedidos` na tabela.

---

## O que é "scaffolding técnico" (fica em Inglês)

Estes termos **nunca** devem ser traduzidos, independentemente do contexto:

| Termo | Categoria |
|-------|-----------|
| Repository, UnitOfWork | Padrão de acesso a dados |
| Command, Query, Handler | CQRS / MediatR |
| Behavior, Pipeline | MediatR pipeline |
| Application, Domain, Infra, CrossCutting | Camadas da arquitetura |
| Controller, Middleware, Extension | ASP.NET Core |
| Consumer, Publisher | MassTransit |
| Migration, DbContext, DbSet | EF Core |
| CorrelationId | Tracing (cross-cutting concern técnico) |
| Namespace | Roteamento MassTransit — nunca traduzir |

---

## Exceções documentadas

| Item | Regra | Motivo |
|------|-------|--------|
| `CorrelationId` | Permanece em inglês | Conceito técnico de distributed tracing, não de domínio. Mudá-lo quebraria tooling padrão de observabilidade. |
| Namespaces | Permanecem em inglês | MassTransit roteia mensagens por namespace + nome do tipo. `FCGames.IntegrationEvents` é parte do contrato e não pode ser traduzido. |
| Nomes de packages/assemblies | Permanecem em inglês | `FCGames.IntegrationEvents`, `Fiap.FCGames.Catalog.Api`, etc. |

---

## Glossário Canônico PT (fonte de verdade)

> Use esta tabela para garantir que os 5 desenvolvedores usem exatamente os mesmos nomes.
> Em caso de dúvida, consulte aqui antes de criar qualquer classe, tabela ou rota.

### Entidades de domínio e tabelas

| Conceito | Classe/Entidade | Tabela | Rota HTTP |
|----------|-----------------|--------|-----------|
| Usuário | `Usuario` | `Usuarios` | `/usuarios` |
| Tipo de acesso | `TipoAcesso` (enum) | — | — |
| Jogo | `Jogo` | `Jogos` | `/jogos` |
| Pedido / Compra | `Pedido` | `Pedidos` | `/compras` |
| Biblioteca | `Biblioteca` | `Bibliotecas` | `/biblioteca` |
| Item da biblioteca | `ItemBiblioteca` | `ItensBiblioteca` | — |
| Pagamento | `Pagamento` | `Pagamentos` | `/pagamentos` |

### Campos comuns

| Campo | Tipo |
|-------|------|
| `Nome` | `string` |
| `Email` | `string` |
| `SenhaHash` | `string` |
| `Preco` | `decimal` |
| `Status` | `int` (enum) |
| `Motivo` | `string?` |
| `CriadoEm` | `DateTime` |
| `DataCadastro` | `DateTime` |
| `DataAdicao` | `DateTime` |
| `ProcessadoEm` | `DateTime` |

### Enum Status (compartilhado por Pedidos e Pagamentos)

| Valor | Inteiro |
|-------|---------|
| `Pendente` | 0 |
| `Aprovado` | 1 |
| `Rejeitado` | 2 |

### Eventos de integração

| Evento | Campos principais |
|--------|-------------------|
| `UsuarioCriadoEvento` | `UsuarioId`, `Nome`, `Email`, `CriadoEmUtc`, `CorrelationId` |
| `PedidoRealizadoEvento` | `PedidoId`, `UsuarioId`, `JogoId`, `NomeJogo`, `Preco`, `RealizadoEmUtc`, `CorrelationId` |
| `PagamentoProcessadoEvento` | `PedidoId`, `UsuarioId`, `JogoId`, `NomeJogo`, `Preco`, `Status`, `Motivo`, `ProcessadoEmUtc`, `CorrelationId` |

> `Status` nos eventos é `string`: `"Aprovado"` \| `"Rejeitado"`

---

## Consequências

**Positivas:**
- Nomes de entidades auto-documentados para desenvolvedores brasileiros.
- Diagramas de sequência e fluxos legíveis sem tradução mental.
- Sem necessidade de mapeamento PT↔EN em nenhuma camada de domínio.

**Negativas / tradeoffs:**
- Integração com sistemas externos (ex: logs indexados em Kibana, dashboards em inglês)
  pode exigir mapeamento pontual.
- Novos membros não-lusófonos terão curva de aprendizado extra no domínio.
- Atenção redobrada para não misturar idiomas: sempre consultar este glossário.

---

## Links relacionados

- [CLAUDE.md — Arquitetura geral](../../CLAUDE.md)
- [API-REFERENCE.md — Detalhamento técnico](./API-REFERENCE.md)
- [fcg-integration-events — Pacote de eventos](https://github.com/FIAP-POS-TECH-TEAM-10/fcg-integration-events)
