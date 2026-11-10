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
pip install "graphifyy[terraform,mcp]" && python -m graphify install   # uma vez por máquina
```

Na pasta que contém todos os repositórios:

1. Crie um `.graphifyignore` (sintaxe do `.gitignore`) com `bin/`, `obj/`, `.terraform/`,
   `docs/superpowers/`, `*.db*` e os checkouts que não estiverem na `main`.
2. No Claude Code: `/graphify .` (primeira vez) ou `/graphify . --update` (depois de mudanças; só
   reprocessa o que mudou). Saída em `graphify-out/` (`graph.json`, `GRAPH_REPORT.md`, `graph.html`).
3. Ligue ao agente como MCP (uma vez, só para você):
   `claude mcp add graphify --scope local -- python -m graphify.serve <pasta>/graphify-out/graph.json`
   e confira com `claude mcp get graphify` (Status: Connected).

Consultas: `/graphify query "..."`, `/graphify path "A" "B" --undirected`, `/graphify explain "X"`
(se o nome existir em dois serviços, use `caminho/do/arquivo.cs::Nome`).

Limites: o grafo vem da análise do código, então **não enxerga a comunicação entre serviços pelo
barramento** (ex.: não há caminho do controller de compras até o consumer do payments). Para isso use o
`grafo.yaml` desta skill. `Program.cs` com instruções de nível superior não gera símbolos.
