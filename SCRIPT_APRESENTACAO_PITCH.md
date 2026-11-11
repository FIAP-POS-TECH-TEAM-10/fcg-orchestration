# 🎬 Script Apresentação Final - FCGames Pitch (25 min)

## 📋 Estrutura Geral

| Seção | Timing | Duração | O que Fazer |
|-------|--------|---------|------------|
| 1. Abertura + Contexto | 0:00-2:00 | 2 min | Problema, solução, arquitetura |
| 2. Infra AWS (Console) | 2:00-5:30 | 3.5 min | Mostrar recursos, cluster, custo |
| 3. Cluster EKS Rodando | 5:30-8:00 | 2.5 min | kubectl, pods, Grafana, ALB |
| 4. Live Deploy (CI/CD) | 8:00-15:00 | 7 min | Alterar código → push → pipeline → prod |
| 5. Busca Avançada + Cache | 15:00-20:00 | 5 min | Elasticsearch, fuzzy search, perf |
| 6. Integração NoSQL | 20:00-24:00 | 4 min | DynamoDB, arquitetura, decisões |
| 7. Encerramento | 24:00-25:00 | 1 min | Destaques, entrega completa |

---

## 🎤 SEÇÃO 1: Abertura + Contexto (0:00 - 2:00)

### Slide/Tela: Título do Projeto
```
FCGames - Plataforma de E-commerce de Jogos
Tech Challenge FIAP - Fase 4
```

**Fala (Eric):**
> "Olá! Apresentamos FCGames, uma plataforma de e-commerce de jogos rodando em **microsserviços .NET 10** 
> na **AWS com Kubernetes (EKS)**, com **eventos**, **busca avançada com Elasticsearch** e **cache com Redis**.
> 
> Arquitetura: **4 serviços** (Users, Catalog, Payments, Notifications) conversam por **eventos** (SNS/SQS).
> Dados: **DynamoDB** para catalogo, **SQLite** para transações, **Redis** para performance.
> 
> Hoje vocês vão ver a **infra na AWS**, um **deploy ao vivo** via GitHub Actions, e como a **busca avançada** 
> impacta a experiência do usuário."

**Ação técnica:**
- Abrir navegador com AWS console já logado (aba 1)
- Terminal com kubectl pronto (aba 2)
- VS Code com repositório git clonado (aba 3)

---

## 🌥️ SEÇÃO 2: Infra AWS (2:00 - 5:30)

### Passo 1: Console AWS - Visão Geral Recursos (2:00-3:30)

**Fala (Eric):**
> "Vamos ao console da AWS. A infraestrutura está em São Paulo (sa-east-1) e usa créditos da conta FREE tier."

**Ação:**
1. Abrir **AWS Console** → **EC2 Dashboard**
   ```
   Mostrar:
   - Region: sa-east-1 (São Paulo) ✓
   - No instances rodando (só o cluster EKS)
   ```

2. Navegar para **EKS** → Cluster `fcg-eks`
   ```
   Apontar:
   - Cluster name: fcg-eks
   - Kubernetes version: 1.36
   - Status: ACTIVE ✓
   - Node group: 2× t3.small (t3.micro no FREE tier)
   ```

3. **ECR** (Elastic Container Registry) - repositórios de imagens
   ```
   Mostrar:
   - fcg-users-service (latest + X imagens históricas)
   - fcg-catalog-service (latest + X imagens)
   - fcg-payments-service (latest + X imagens)
   Falar: "Cada push para main dispara a pipeline, constrói e push automático aqui"
   ```

4. **DynamoDB** - Tabelas
   ```
   Mostrar:
   - Jogos (com seed: Hades, Hollow Knight, Cyberpunk 2077)
   - Desejos
   Falar: "Dados persistem entre deploys. Sem cold starts no DynamoDB."
   ```

**Fala (Eric):**
> "Toda a infra é **código** (Terraform) - scripts de `eks-up.sh` / `eks-down.sh` ligam e desligam 
> em ~10 min.."

**Timing:** 3:30 marcas

---

### Passo 2: GitHub Actions - Workflow CI/CD (3:30-5:30)

**Fala (Eric):**
> "Toda mudança no código dispara uma pipeline automaticamente. Vamos ver o workflow."

**Ação:**
1. GitHub → Repository Settings → Actions → Workflows
   ```
   Mostrar:
   - Workflow: "Deploy to EKS" (ou similar)
   - Trigger: push para main
   - Passos:
     ✓ Checkout código
     ✓ Login ECR
     ✓ Build Docker
     ✓ Push ECR
     ✓ Deploy Kubernetes (kubectl apply)
   ```

2. **Últimos deploys** (Actions tab)
   ```
   Clicar em um deploy bem-sucedido:
   - Show logs: build, push, kubectl apply
   ```

3. OIDC + GitHub Actions Role
   ```
   Apontar (sem clicar): AWS IAM → GitHubActions-EKS-Admin
   Falar: "Sem armazenar senhas no GitHub. Confiança via OIDC."
   ```

**Fala (Eric):**
> "A pipeline é declarativa - rodamos `eks-up.sh` (botão no README), ele chama Terraform, 
> Terraform cria o cluster, a pipeline detecta e faz deploy automático dos últimos containers no ECR."

**Timing:** 5:30 marcas

---

## ☸️ SEÇÃO 3: Cluster EKS Rodando (5:30 - 8:00)

**Fala (Michel):**
> "Agora vemos o cluster rodando em tempo real."

### Passo 1: Kubectl - Pods e Serviços (5:30-6:30)

**Terminal:**
```powershell
# Mostrar contexto ativo
kubectl config current-context
# Output: arn:aws:eks:sa-east-1:915153720516:cluster/fcg-eks

# Listar pods
kubectl get pods -n fcgames
# Output:
# NAME                            READY   STATUS    RESTARTS   AGE
# users-api-5f4b9c8d9d-abc12      1/1     Running   0          2h
# catalog-api-5f4b9c8d9d-def45    1/1     Running   0          2h   (contém api + worker)
# payments-api-5f4b9c8d9d-ghi78   1/1     Running   0          2h   (contém api + worker)
# redis-5f4b9c8d9d-jkl90          1/1     Running   0          2h
# prometheus-5f4b9c8d9d-mno12     1/1     Running   0          2h
# grafana-5f4b9c8d9d-pqr34        1/1     Running   0          2h
```

**Fala (Michel):**
> "Cada pod roda um container da API e (para Catalog e Payments) um Worker que consome eventos do SQS.
> Redis está aqui para cache. Prometheus e Grafana para observabilidade."

### Passo 2: Ingress / ALB (6:30-7:15)

**Terminal:**
```powershell
# Ver Ingress (expõe ALB externo)
kubectl get ingress -n fcgames
# Output:
# NAME       CLASS    HOSTS   ADDRESS                                    PORTS   AGE
# fcgames    aws-alb  *       k8s-fcgames-alb123-456789.sa-east-1.elb.amazonaws.com   80      2h

# Ver services
kubectl get svc -n fcgames
# OUTPUT: ClusterIP para internos, ALB LoadBalancer expõe

# Testar endpoint (pode ser pelo arquivo http ou postman)
$token = "seu_jwt_aqui"
curl -X GET "http://k8s-fcgames-alb123-456789.sa-east-1.elb.amazonaws.com/jogos" `
  -H "Authorization: Bearer $token"
# Resposta: lista de jogos ✓
```

**Fala (Michel):**
> "Um único ALB (Application Load Balancer) roteia todo tráfego por path:
> - `/usuarios` → Users API
> - `/jogos`, `/compras`, `/biblioteca` → Catalog API
> - `/pagamentos` → Payments API
> - `/grafana` → Grafana (monitoring)"

### Passo 3: Grafana - Métricas Ao Vivo (7:15-8:00)

**Browser:**
```
URL: http://k8s-fcgames-alb.../grafana
Login: admin / (senha no secret)
Mostrar dashboard:
  - CPU / Memory dos pods
  - Request count, latência das APIs
  - DynamoDB read/write capacity
  - SQS messages (eventos na fila)
```

**Fala (Michel):**
> "Prometheus coleta métricas de todos os pods. Grafana visualiza em tempo real.
> Vemos se a busca avançada impacta o CPU, ou se o cache está funcionando."

**Timing:** 8:00 marcas

---

## 🚀 SEÇÃO 4: Live Deploy - Código → Pipeline → Prod (8:00 - 15:00)

**Pré-requisitos:**
- Código clonado localmente e pronto em `fcg-catalog-service`
- Branch `main` 
- GitHub Actions ja está configurado

### Passo 1: Alterar Código (8:00-9:30)

**VS Code:**

**Fala (Daniel):**
> "Vamos fazer uma mudança no código da API de Catalog - algo visível e testável.
> Vou alterar uma mensagem de resposta para provar que a nova versão vai para produção."

**Ação:**
1. Abrir `fcg-catalog-service/app/src/Fiap.FCGames.Catalogo.Api/Controllers/JogosController.cs`
2. Ir para um método (ex: `ListarAsync`)
3. Alterar um log ou comentário:
   ```csharp
   // Antes:
   _logger.LogInformation("Listando todos os jogos");
   
   // Depois:
   _logger.LogInformation("🚀 Listando jogos - v2.1 com Elasticsearch");
   ```

4. **Salvar arquivo** (`Ctrl+S`)

**Terminal VS Code:**
```powershell
cd c:\github\FIAP-POS-TECH\fcg-catalog-service
git add .
git commit -m "feat: busca avançada com elasticsearch - v2.1"
git push origin main
```

**Fala (Daniel):**
> "Push feito. A pipeline detectou a mudança. Vamos acompanhar em tempo real."

**Timing:** 9:30 marcas

---

### Passo 2: Acompanhar Pipeline (9:30-12:00)

**GitHub Actions (Browser Aba 1):**
1. Ir para **Actions** → Ver workflow em execução
   ```
   Show live execution:
   ✓ Checkout
   ✓ Build Docker 
   ✓ Push ECR 
   ✓ Deploy K8s - kubectl apply 
   ✓ ✅ Sucesso 
   ```

**Paralelo - Terminal (Aba 2):**

Enquanto a pipeline roda, monitorar o deployment:
```powershell
# Ver se está fazendo rolling update
kubectl get pods -n fcgames -w
# OUTPUT: vê um novo pod "catalog-api-NEW-HASH" surgindo, 
# e o antigo ficando "Terminating"

# Após completar, verificar a versão que subiu
kubectl logs -n fcgames deployment/catalog-api --tail=20 | grep "v2.1"
# OUTPUT: "🚀 Listando jogos - v2.1 com Elasticsearch"
```

**Fala (Daniel):**
> "Enquanto a pipeline faz build, teste e push, o cluster está ao vivo servindo requisições.
> Não há downtime. Quando a nova imagem sobe, o Kubernetes faz rolling update:
> sobe um novo pod, testa health checks, e só depois desliga o antigo.
> A mudança está em produção em menos de 10 minutos, automaticamente."

**Timing:** 12:00 marcas

---

### Passo 3: Testar Endpoint Novo em Produção (12:00-15:00)

**Terminal / Postman:**

**Fala (Daniel):**
> "Vamos testar o endpoint novo em produção. Logging mostra a versão v2.1."

--(as requisições pode ser pelo arquivo http)
```powershell
# 1. Obter token (Users API)
$userResponse = curl -X POST "http://k8s-fcgames-alb.../usuarios" `
  -H "Content-Type: application/json" `
  -d @{
    email = "teste@fcgames.com"
    senha = "Senha123!"
    nome = "Testador"
  } | ConvertFrom-Json

$token = $userResponse.token

# 2. Listar jogos (já sobe com a nova versão)
curl -X GET "http://k8s-fcgames-alb.../jogos" `
  -H "Authorization: Bearer $token" | ConvertFrom-Json | jq '.[] | {id, nome, preco}'

# Resposta esperada:
# {
#   "id": "xxx-xxx",
#   "nome": "Hades",
#   "preco": 49.90
# },
# ...

# 3. Verificar logs no pod novo (procurar pela mensagem v2.1)
kubectl logs -n fcgames deployment/catalog-api --all-containers=true | grep "v2.1"
# OUTPUT: "🚀 Listando jogos - v2.1 com Elasticsearch"
```

**Fala (Daniel):**
> "✅ Código alterado → push → pipeline → ECS novo → produção em <10 min.
> A mudança já está servindo usuários reais. Sem downtime, teste automático, segurança de OIDC.
> Isso é **CI/CD moderno**."

**Timing:** 15:00 marcas

---

## 🔍 SEÇÃO 5: Busca Avançada + Cache (15:00 - 20:00)

### Passo 1: Apresentar Elasticsearch (15:00-16:30)

**Fala (Gregori):**
> "A inovação nesta fase foi adicionar **busca avançada com Elasticsearch**.
> Antes: busca exata por nome (SELECT * WHERE name LIKE 'xyz').
> Agora: busca fuzzy (encontra typos), por descrição, ordenação por relevância."

**Mostrar Código:**
1. Abrir `fcg-catalog-service/.../Services/ElasticsearchService.cs`
   ```csharp
   public async Task<List<BuscaJogosResponse>> BuscarJogosAsync(
       string termo,
       bool fuzzySearch = true,
       int tamanho = 20,
       CancellationToken cancellationToken = default)
   {
       // MultiMatch query em nome (peso 2.0) + descrição
       // Fuzziness: AUTO (tolera erros)
       // Sort: por score (relevância)
   }
   ```

2. Mostrar **Endpoint novo:**
   ```
   GET /buscaJogos?q=haldes&fuzzy=true
   → Encontra "Hades" mesmo com erro de digitação
   
   GET /buscaJogos?q=rpg&fuzzy=true
   → Encontra todos os jogos com "RPG" no nome ou descrição
   
   GET /buscaJogos?q=hades&size=5
   → Limita a 5 resultados
   ```

### Passo 2: Testar Busca Ao Vivo (16:30-18:00)

**Terminal:**

```powershell
# 1. Criar alguns jogos com descrições variadas
curl -X POST "http://k8s-fcgames-alb.../jogos" `
  -H "Authorization: Bearer $token" `
  -H "Content-Type: application/json" `
  -d @{
    nome = "Hades"
    descricao = "Roguelike acelerado com combate intenso e personagens memoráveis"
    preco = 49.90
  }

curl -X POST "http://k8s-fcgames-alb.../jogos" `
  -H "Authorization: Bearer $token" `
  -H "Content-Type: application/json" `
  -d @{
    nome = "Hollow Knight"
    descricao = "Metroidvania classico com gameplay desafiador"
    preco = 29.90
  }

curl -X POST "http://k8s-fcgames-alb.../jogos" `
  -H "Authorization: Bearer $token" `
  -H "Content-Type: application/json" `
  -d @{
    nome = "Cyberpunk 2077"
    descricao = "RPG de acao em mundo aberto futurista"
    preco = 149.90
  }

# 2. Buscar com FUZZY - encontra typo "haldes" → "Hades"
curl -X GET "http://k8s-fcgames-alb.../buscaJogos?q=haldes&fuzzy=true" `
  -H "Authorization: Bearer $token" | ConvertFrom-Json | jq '.[].nome'
# OUTPUT: "Hades" ✓

# 3. Buscar por descrição
curl -X GET "http://k8s-fcgames-alb.../buscaJogos?q=roguelike" `
  -H "Authorization: Bearer $token" | ConvertFrom-Json | jq '.[].nome'
# OUTPUT: "Hades" ✓

# 4. Buscar por tema
curl -X GET "http://k8s-fcgames-alb.../buscaJogos?q=metroidvania" `
  -H "Authorization: Bearer $token" | ConvertFrom-Json | jq '.[].nome'
# OUTPUT: "Hollow Knight" ✓

# 5. Sem fuzzy (exato)
curl -X GET "http://k8s-fcgames-alb.../buscaJogos?q=haldes&fuzzy=false" `
  -H "Authorization: Bearer $token" | ConvertFrom-Json | jq length
# OUTPUT: 0 (sem match, não é exato)
```

**Fala (Gregori):**
> "Veja a mágica: uma busca por 'haldes' (typo) encontrou 'Hades'. 
> Elasticsearch faz análise de texto, tokenização, fuzzy matching - tudo automático.
> Usuários acham o que procuram, mesmo com erros de digitação."

**Timing:** 18:00 marcas

---

### Passo 3: Impacto do Cache - Redis (18:00-20:00)

**Fala (Gregori):**
> "Agora vamos ver o **cache com Redis** em ação. Busca sem cache é lenta; com cache é instant."

**Código (mostrar):**
1. `BuscaJogosQueryHandler.cs` ou controller:
   ```csharp
   // Pseudocódigo:
   // 1. Verifica cache (Redis)
   // 2. Se miss: chama Elasticsearch
   // 3. Guarda em cache por 5 min
   // 4. Próxima requisição: retorna do cache instantly
   ```

**Demonstração Prática:**

```powershell
# 1. Limpar cache (simular primeira requisição)
# (Assumindo que há um endpoint de admin ou kubectl para invalidar cache)
# kubectl exec -it redis-pod -n fcgames -- redis-cli FLUSHALL

# 2. Primeira requisição (sem cache)
$start = [DateTime]::Now
curl -X GET "http://k8s-fcgames-alb.../buscaJogos?q=rpg" -H "Authorization: Bearer $token" > $null
$elapsed1 = ([DateTime]::Now - $start).TotalMilliseconds
Write-Host "Primeira busca (sem cache): ${elapsed1} ms"

# 3. Segunda requisição (com cache)
$start = [DateTime]::Now
curl -X GET "http://k8s-fcgames-alb.../buscaJogos?q=rpg" -H "Authorization: Bearer $token" > $null
$elapsed2 = ([DateTime]::Now - $start).TotalMilliseconds
Write-Host "Segunda busca (com cache): ${elapsed2} ms"

# Fala esperada:
# "Primeira: 150ms. Segunda (cache): 8ms. Cache deixa a resposta **18x mais rápida**!"
```

**Mostrar no Grafana (paralelo):**
- Dashboard de latência (antes e depois)
- Cache hit rate no Redis

**Fala (Gregori):**
> "Com Redis, 99% das buscas são servidas do cache. Reduz carga no Elasticsearch e no DynamoDB.
> Usuário fica feliz (respostas rápidas), infraestrutura agradecida (menos processamento)."

**Timing:** 20:00 marcas

---

## 💾 SEÇÃO 6: Integração NoSQL na Arquitetura (20:00 - 24:00)

### Passo 1: DynamoDB para Dados Não-Transacionais (20:00-21:30)

**Fala (Claudio):**
> "Entender quando usar NoSQL vs SQL é crucial. No FCGames:
> - **SQL (SQLite)**: Pedidos, Bibliotecas - dados transacionais, ACID
> - **NoSQL (DynamoDB)**: Jogos, Desejos - dados de catalog, leitura pesada"

**Mostrar Arquitetura:**

```
Requisição HTTP GET /jogos
  ↓
Catalog API
  ↓
[Tenta Redis] → HIT? Retorna rápido
  ↓ MISS
[Consulta DynamoDB "Jogos" table]
  ↓
[Serializa e cacheia em Redis]
  ↓
Retorna JSON ao cliente
```

**Mostrar Código:**
1. `CriarJogoCommandHandler.cs`:
   ```csharp
   // Grava em DynamoDB (não-relacional, sem constraint FK)
   var jogo = new Jogo { Id, Nome, Descricao, Preco };
   await _jogoRepository.AdicionarAsync(jogo);
   
   // Fire-and-forget: indexa no Elasticsearch para busca
   _ = _elasticsearchService.IndexarJogoAsync(jogo.Id, jogo.Nome, ...);
   ```

2. `ListarJogosQueryHandler.cs`:
   ```csharp
   // Lê do DynamoDB ou cache
   var jogos = await _jogoRepository.ListarAsync();
   
   // Responde com lista
   return jogos.Select(j => new JogoResponse(...)).ToList();
   ```

### Passo 2: Elasticsearch - Busca Full-Text (21:30-22:30)

**Fala (Claudio):**
> "Elasticsearch é um mecanismo de **busca**, não banco de dados.
> Mantém um índice invertido que permite buscar por qualquer palavra, em qualquer campo, com fuzzy."

**Fluxo:**
```
Criação de Jogo
  ↓
Grava em DynamoDB ✓
  ↓
Publica evento "JogoCriado"
  ↓
Indexa em Elasticsearch (fire-and-forget)
  ↓
Elasticsearch indexa: { id, nome, descricao, preco }

Busca por termo
  ↓
Query Elasticsearch MultiMatch
  ↓
Retorna ranked by score/relevância
```

**Mostrar Dashboard Elasticsearch:**
```
(Se houver Kibana rodando ou via AWS Console):
- Index: "jogos"
- Mapping: id (keyword), nome (text + analyzer), descricao (text), preco (scaled)
- Análise: standard tokenizer + lowercase + stop words
- Docs: X documentos indexados
```

**Fala (Claudio):**
> "Elasticsearch detecta que 'hades' pode ser 'Hades' porque vê um 1 caractere de diferença (fuzzy).
> Tokeniza 'roguelike acelerado' em palavras, permite buscar por qualquer uma.
> É feito para buscas; DynamoDB é feito para dados."

**Timing:** 22:30 marcas

---

### Passo 3: Decisões Arquiteturais (22:30-24:00)

**Fala (Claudio):**
> "Por que essas escolhas?"

**Slide/Diagrama - Por que NoSQL?**
```
✓ Escalabilidade: DynamoDB scale automaticamente
✓ Pay-per-use: paga pelo que usa (bom para variable load)
✓ Sem schema rígido: adiciona campo quando precisa
✗ Sem join: Jogos e Desejos são tabelas separadas
✗ Sem transação cross-table: cada tabela é seu mundo

✓ SQL mantido para: Pedidos (ACID, constraints)
```

**Fala (Claudio):**
> "DynamoDB é ótimo para catálogo que muda pouco e é lido muito.
> Pedidos precisam de ACID (transaction entre Pedido, ItemPedido, Pagamento).
> Cache + Elasticsearch + DynamoDB = **leitura rápida**, dados consistentes."

**Timing:** 24:00 marcas

---

## 🎬 SEÇÃO 7: Encerramento (24:00 - 25:00)

**Fala (Eric):**
> "Em resumo, entregamos:"

```
✅ Microsserviços .NET 10 em EKS (Kubernetes)
✅ Infraestrutura como Código (Terraform)
✅ CI/CD automatizado (GitHub Actions)
✅ Busca avançada com Elasticsearch
✅ Cache com Redis
✅ Integração NoSQL (DynamoDB) + SQL (SQLite)
✅ Observabilidade (Prometheus + Grafana)
✅ Sem downtime, escalável, pronto para produção
```

**Fala (Eric):**
> "Tudo está no repositório:
> - Código em `fcg-*-service/`
> - Infra em `fcg-orchestration/infra/`
> - Manifests K8s em `fcg-orchestration/k8s/`
> - Pipelines em `.github/workflows/`
> 
> Deploy local: `docker compose up`. Deploy AWS: `eks-up.sh`."

**Últimas Palavras:**
> "FCGames está pronto. Tecnologia moderna, código limpo, infraestrutura robusta. Obrigado!"

**Timing:** 25:00 ✓

---

## 📌 Checklist Pré-Apresentação

### Dia Anterior
- [ ] Clonar repositórios localmente
- [ ] Build e test locais (`docker compose up`)
- [ ] Cluster EKS ligado (`eks-up.sh`)
- [ ] AWS console testado (login + navegação)
- [ ] Kubectl context ativo e conectado ao cluster
- [ ] Token JWT pré-gerado para testes
- [ ] Postman / curl scripts prontos
- [ ] VS Code aberto com repositório
- [ ] Gratuito com créditos suficientes (>US$ 20)

### 1 Hora Antes
- [ ] Testar tudo: AWS console, kubectl, endpoints
- [ ] Fazer push fictício para cache código em ECR
- [ ] Limpar logs de pipeline anteriores (ou deixar limpo)
- [ ] Abrir browsers/terminais pré-autenticadas
- [ ] Testes de latência Redis (carregar cache)
- [ ] Verificar Grafana e Prometheus rodando
- [ ] Ensaiar timings

### Materiais Necessários
- 5x Apresentadores (Eric, Michel, Daniel, Gregori, Claudio)
- 3x Browser tabs (AWS console, GitHub Actions, Grafana)
- 1x Terminal rodando kubectl
- 1x VS Code com repositório
- Projetor / Tela compartilhada
- Internet estável
- Backup: screenshots/screen recording em caso de falha de conexão

---

## 🎥 Dicas de Apresentação

1. **Foco em "problema → solução":** Não liste features; conte como a busca fuzzy ajuda o usuário a achar jogos
2. **Velocidade:** Busca ao vivo toma tempo. Pre-compute alguns cenários ou use vídeo editado como backup
3. **Parar para perguntas:** Se ficarem com dúvida, explique. Fluxo é mais importante que timing perfeito
4. **Mostrar valor:** Não é só sobre tecnologia; é sobre experiência (buscas rápidas, sem bugs, scale automático)
5. **Segurança:** Não mostre senhas/tokens reais. Use placeholders ou redactionmarks (`***`)

---

## 📝 Notas do Video

Se gravar em vídeo pré-gravado (recomendado para controle de qualidade):
- Gravar seções separadamente (Abertura, Infra, Deploy, Busca)
- Deixar pausas para "surpresas" (quando pipeline termina)
- Adicionar música leve de fundo em transições
- Cortar silêncios longos (monitorar pipeline por 5 min = entediante)
- Colocar captions com comandos rodados (para quem quer reproduzir)
- Ter plano B: se pipeline falhar, reproduzir com vídeo editado pronto

---

**Total: ~25 minutos de apresentação, alta qualidade técnica e demonstrativa.**
