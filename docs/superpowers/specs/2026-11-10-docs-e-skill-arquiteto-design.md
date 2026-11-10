# Docs simples + skill `fcg-arquiteto` + Graphify — design

Data: 2026-11-10 · Status: proposta (aguarda aprovação)

## Por quê

A documentação do FCGames cresceu fase a fase e ficou espalhada e em parte desatualizada
(o `API-REFERENCE.md` é de junho, o `k8s/README.md` descreve o Kind local, o CLAUDE.md da raiz
ainda cita ECS e a conta antiga). Quem entra no time, ou a banca, precisa de respostas rápidas e
certas: o que cada peça faz, como os serviços se comunicam, o que existe na AWS e como acessar
cada recurso. Hoje isso exige ler vários arquivos longos e conferir no código.

## Objetivos

1. **Docs commitadas simples e corretas** em todos os repositórios, conferidas contra o código e a
   infra reais. Um PR por repositório.
2. **Skill `fcg-arquiteto`** que responde perguntas sobre o projeto inteiro, organizada por módulos,
   com um grafo curado da arquitetura.
3. **Graphify** sobre os repositórios, ligado ao agente, para perguntas de código.

## Não objetivos

- Banco vetorial / RAG com embeddings.
- Mudar código, infra ou comportamento de qualquer serviço (só docs, salvo erro de doc que exija
  ajuste trivial — nesse caso, perguntar antes).
- Reescrever o histórico do git ou os specs/planos antigos em `docs/superpowers/` (ficam como registro).

## Anti-objetivos (seria falha mesmo "funcionando")

- Docs que repetem a mesma informação em vários lugares (voltam a divergir).
- Skill que afirma algo sem dizer de onde veio, ou que inventa recurso/URL.
- Qualquer senha, chave ou valor de segredo em doc, skill ou grafo.

## Parte 1 — Docs simples

### Padrão por tipo de arquivo

| Arquivo | Conteúdo (e nada além) |
|---|---|
| README de serviço | O que é (1–2 linhas) · tabela de endpoints · tabela de variáveis de ambiente · como rodar local · onde roda na AWS · links |
| `k8s/README.md` de serviço | Só o caminho Kind local: criar o Secret, aplicar, testar (curto) |
| README do `fcg-orchestration` | O que tem no repo · ligar/desligar/testar o EKS · subir local com compose · links |
| README do `fcg-integration-events` | Os 3 eventos (campos) · como consumir o pacote · versionamento |
| Repositório aposentado | 1 README apontando para o substituto |
| `.http` | Só requisições que funcionam hoje, senha via `.env` |

Regras:
- **Uma fonte por fato.** Endpoints: no README do serviço. Contratos de eventos: no
  `fcg-integration-events`. Infra EKS: no `fcg-orchestration`. Os outros arquivos linkam.
- Sem histórico ("na Fase 3 era ECS…"): só o que vale hoje. O histórico fica no git e nos specs.
- Sem troubleshooting longo: no máximo 3–4 problemas reais com a solução em uma linha.
- `API-REFERENCE.md`: deixa de existir como cópia de endpoints; vira um índice curto que aponta
  para os READMEs e o pacote de eventos (ou é removido se o índice ficar vazio de sentido).
- Situação conhecida: `fcg-notifications-api` = worker do compose local; `fcg-notifications-lambda`
  = notificações na AWS. Os dois continuam; cada README diz isso em uma linha.
- `fcg-observabilidade-service` já está reduzido ao README; só conferir.

### Como verificar

Cada afirmação de doc é conferida contra a `origin/main` do repositório (código, `appsettings`,
manifests, Terraform, workflows) e, quando for sobre a AWS, por comandos só de leitura. O que não
der para confirmar sai da doc ou vira pergunta.

### Entrega

Um PR por repositório (até 8), mesclado pelo usuário. Ordem: `fcg-integration-events` →
serviços → `fcg-orchestration` (que linka os outros).

## Parte 2 — Skill `fcg-arquiteto`

**Onde:** `fcg-orchestration/.claude/skills/fcg-arquiteto/` (versionada; vale abrindo o Claude na
raiz do workspace ou dentro do orchestration).

**Estrutura:**

```
fcg-arquiteto/
  SKILL.md                 sumário, regras de resposta, quando usar o Graphify
  grafo.yaml               grafo curado: nós e arestas da arquitetura
  references/
    visao-geral.md         mapa + diagrama Mermaid
    users.md · catalog.md · payments.md · notifications.md
    mensageria.md          eventos, tópicos SNS, filas SQS/RabbitMQ, quem publica/consome
    infra-aws-eks.md       cluster, nodes, ALB, ECR, DynamoDB, Redis, IAM, S3/tfstate
    cicd.md                pipelines, botões ligar/desligar, cron
    seguranca.md           segredos (onde ficam, sem valores), OIDC, Pod Identity
    observabilidade.md     Prometheus, Grafana, logs
    acesso.md              como acessar cada recurso: console, kubectl, URLs, logs, permissões
    operacao.md            ligar, desligar, testar, problemas comuns
    decisoes.md            ADRs resumidos
    pendencias.md          o que falta para a entrega
```

**`grafo.yaml`:** lista de nós (`id`, `tipo`: serviço | evento | fila | tópico | tabela | recurso-aws
| repositório | pipeline, `descrição`, `onde`, `fonte`) e de arestas (`de`, `para`, `relação`:
publica | consome | chama | lê | grava | roda-em | acessa-via | publica-imagem-em). Pequeno
(dezenas de nós), escrito à mão a partir da auditoria.

**Regras da skill:**
- Responder com base nas referências e dizer a fonte (arquivo do repo).
- Quando a resposta importar (comando, URL, permissão), conferir no código ou na AWS com comando
  só de leitura antes de afirmar; cada referência traz "verificado em <data>".
- Nunca mostrar valor de segredo; dizer onde ele fica.
- Perguntas de código (onde está X, quem chama Y): usar o Graphify se o grafo existir.
- `references/atualizar.md` (ou seção do SKILL.md): como revisar a skill depois de mudança grande.

**Teste antes de entregar:** ~10 perguntas reais (ex.: "como o catalog sabe que o pagamento foi
aprovado?", "onde fica a senha do admin?", "como vejo os logs da notificação?", "o que acontece se o
cluster ficar ligado?"), respostas conferidas.

## Parte 3 — Graphify

- Instalado na máquina do usuário (`graphifyy` 0.9.106, skill em `~/.claude/skills/graphify`).
- Grafo construído sobre a raiz do workspace (todos os repos), ignorando `bin/`, `obj/`,
  `.terraform/`, `node_modules/` e `docs/superpowers/`.
- Limitação conhecida: não lê `.yaml`/`.yml`/`.tf`; a infra entra pelo Markdown da skill e das docs.
- `graphify-out/` fica **local** (não versionado): cada pessoa do time gera o seu com `/graphify`.
  O grafo compartilhado do time é o `grafo.yaml` da skill.
- Ligação ao agente: servidor MCP do Graphify registrado para o workspace, e a skill
  `fcg-arquiteto` diz quando consultá-lo.

## Decisões tomadas por mim (revisar)

- Critério de "simples" da tabela acima.
- `API-REFERENCE.md` vira índice curto ou sai.
- `graphify-out/` não versionado; o compartilhado é o `grafo.yaml`.
- Specs e planos antigos ficam como estão.
- O CLAUDE.md da raiz (não versionado) é enxugado no fim para apontar para a skill — só com o "ok" do usuário.
