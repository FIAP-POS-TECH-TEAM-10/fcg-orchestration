# ADR-002 — NotificationsAPI como Worker de Projeto Único

**Data:** 2026-06-21
**Status:** Aceito
**Autores:** Time FCGames (FIAP Pós-Tech Team 10)

---

## Contexto

O template base dos microsserviços (CatalogAPI) define uma estrutura de 5 camadas:
`Api`, `Application`, `CrossCutting`, `Domain`, `Infra` (+ `Worker` nos serviços que
consomem eventos). Essa estrutura faz sentido em serviços com domínio, banco e CQRS
(Users, Catalog, Payments).

O **NotificationsAPI** é diferente: é stateless, **sem banco**, **sem domínio** e
**sem CQRS**. Seu único propósito é consumir `UsuarioCriadoEvento` e
`PagamentoProcessadoEvento` e gerar logs JSON estruturados. A casca inicial gerada
pelo template trazia as 5 camadas — incluindo um projeto `Infra` com EF Core
meio-desmontado que **não compilava**.

## Decisão

NotificationsAPI será um **único projeto**: `Fiap.FCGames.Notifications.Worker`.

Foram **removidos** os projetos `Api`, `Application`, `Domain`, `CrossCutting` e `Infra`.
Não há EF Core, DbContext, MediatR, FluentValidation, JWT nem Swagger.

```
app/src/Fiap.FCGames.Notifications.Worker/
  Program.cs       — fiação MassTransit + MapHealthChecks("/health")
  Consumers/       — UsuarioCriadoEventoConsumer, PagamentoProcessadoEventoConsumer (só logs)
  Middleware/      — propagação do x-correlation-ID
```

---

## Justificativa

- **Não há o que separar em camadas:** sem domínio/banco/CQRS, `Application`/`Domain`/`Infra`
  ficariam vazios ou com scaffolding morto.
- **Layout de consumer alinhado ao time:** consumers em `Worker/Consumers/` e MassTransit
  fiado no `Program.cs` é exatamente o que o `.Worker` de payments/catalog já faz.
- **Manter projeto só "por consistência de template" não se justifica** — adiciona
  complexidade e arquivos mortos sem benefício.

---

## SDK: `Microsoft.NET.Sdk.Web` (e não `Sdk.Worker`)

| Opção | HTTP `/health`? | Decisão |
|-------|-----------------|---------|
| `Sdk.Web` + `WebApplication` | ✅ nativo | **Escolhido** |
| `Sdk.Worker` + `Host` (puro) | ❌ exigiria probe TCP/exec ou rehospedar HTTP | Recusado |

O CLAUDE.md exige `GET /health` por HTTP para o liveness/readiness probe do k8s, e o
NotificationsAPI não tem um projeto `.Api` separado para hospedá-lo. Logo, mantém-se o
`Sdk.Web` **apenas** para expor `/health`; o MassTransit roda como hosted service em
background. O SDK web aqui não significa "é uma API" — é o jeito idiomático de um worker
servir um endpoint de health.

---

## Consequências

**Positivas:**
- Serviço enxuto (1 projeto, ~6 arquivos) e fácil de entender.
- Sem dependências/pacotes mortos (EF Core, MediatR, JWT, Swagger removidos).
- Build limpo (0 erros / 0 warnings).

**Negativas / tradeoffs:**
- **Diverge do template de 5 projetos** dos demais serviços — exceção que precisa ser
  conhecida pelo time (documentada também no CLAUDE.md §2.4).
- Um projeto `.Worker` usando `Sdk.Web` é incomum à primeira vista (o `.Worker` de
  payments/catalog usa `Sdk.Worker`); a justificativa é o requisito de `/health` HTTP.

---

## Links relacionados

- [CLAUDE.md §2.4 — fcg-notifications-api](../../CLAUDE.md)
- [ADR-001 — Convenção de Nomenclatura](./ADR-001-convencao-nomenclatura.md)
- [fcg-notifications-api](https://github.com/FIAP-POS-TECH-TEAM-10/fcg-notifications-api)
