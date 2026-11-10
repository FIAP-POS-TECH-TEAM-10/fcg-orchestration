# Manter a skill atualizada

Revise depois de qualquer mudança que altere endpoints, eventos, filas, infra, segredos ou pipelines.

1. **Atualize primeiro a doc do repositório** que é a fonte do fato (README do serviço,
   `fcg-integration-events`, `fcg-orchestration`). A skill resume; a fonte é o repositório.
2. Ajuste o arquivo de `references/` correspondente e a data "Verificado em".
3. Se mudou quem fala com quem, ajuste o `grafo.yaml` (nós e arestas) e o diagrama de `visao-geral.md`.
   Cada aresta precisa apontar para nós existentes e usar uma relação da lista do cabeçalho.
4. Confira fatos da AWS só com leitura, por exemplo:
   `aws sns list-subscriptions --profile fcg-team --region sa-east-1`,
   `aws sqs list-queues ...`, `aws ecr describe-repositories ...`.
5. Garanta que nada tem valor de segredo (senha, chave, token) antes do commit.
6. Atualize `pendencias.md` quando algo for entregue.

## Graphify (grafo do código)

Grafo do código e das docs, gerado localmente (não versionado):

```bash
pip install graphifyy && python -m graphify install   # uma vez por máquina
```

No Claude Code, na pasta que contém todos os repositórios: `/graphify .` (primeira vez) ou
`/graphify . --update` (depois de mudanças). Saída em `graphify-out/` (`graph.json`,
`GRAPH_REPORT.md`, `graph.html`). Consultas: `/graphify query "..."`, `/graphify path "A" "B"`,
`/graphify explain "X"`. O Graphify não lê `.yaml`/`.tf`; a infra vem destas referências.
