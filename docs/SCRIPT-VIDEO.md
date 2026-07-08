# Script de Vídeo - Tech Challenge Fase 2 (20 minutos)

> **FCGames** — Sistema de vendas de jogos digitais com arquitetura de microsserviços

---

## 🎬 Estrutura do Vídeo

| Seção | Tempo | Conteúdo |
|-------|-------|----------|
| 1. Abertura | 0:00-1:00 | Apresentação do projeto |
| 2. Arquitetura | 1:00-4:00 | Visão geral dos microsserviços |
| 3. Docker Compose | 4:00-8:00 | Demonstração ambiente local |
| 4. Kubernetes | 8:00-14:00 | Deploy e recursos K8s |
| 5. Fluxo End-to-End | 14:00-18:00 | Jornada completa do usuário |
| 6. Encerramento | 18:00-20:00 | Requisitos atendidos e conclusão |

---

## 📝 Roteiro Detalhado

### 1. ABERTURA (0:00 - 1:00)

**[TELA: Título "FCGames - Tech Challenge Fase 2"]**

**Narração:**
> "Olá, sou [NOME] e vou apresentar o projeto FCGames, desenvolvido para o Tech Challenge Fase 2 da FIAP. Este é um sistema completo de vendas de jogos digitais implementado com arquitetura de microsserviços, usando .NET 10, mensageria assíncrona com RabbitMQ, e orquestração com Kubernetes."

**[TELA: Mostrar estrutura de pastas do projeto]**

> "O projeto está organizado em 5 repositórios: Users API, Catalog API, Payments API, Notifications e o repositório de orquestração onde ficam os arquivos Docker Compose e Kubernetes."

**⏱️ Checkpoint: 1 minuto**

---

### 2. ARQUITETURA (1:00 - 4:00)

**[TELA: Diagrama de arquitetura - pode ser o README.md ou desenhar ao vivo]**

**Narração:**
> "A arquitetura é composta por 4 microsserviços independentes que se comunicam de forma assíncrona através do RabbitMQ. Vamos entender cada um deles:"

**2.1. Users API (30 segundos)**
> "O **Users API** é responsável pela autenticação. Ele gera o token JWT que será validado pelos outros serviços. Quando um usuário se cadastra, ele publica um evento 'UsuarioCriado' na fila."

**Pontos-chave:**
- Emite JWT
- Banco SQLite próprio
- Publica evento: `UsuarioCriadoEvento`

**2.2. Catalog API + Worker (45 segundos)**
> "O **Catalog API** gerencia o catálogo de jogos e as bibliotecas dos usuários. Ele tem dois componentes: a API que expõe endpoints REST, e um Worker que consome eventos."

> "Quando o Worker recebe o evento de usuário criado, ele cria uma biblioteca vazia para aquele usuário. E quando um pagamento é aprovado, ele adiciona o jogo na biblioteca."

**Pontos-chave:**
- API + Worker (2 processos)
- Compartilham mesmo banco SQLite via volume
- Consome: `UsuarioCriadoEvento`, `PagamentoProcessadoEvento`
- Publica: `PedidoRealizadoEvento`

**2.3. Payments API + Worker (45 segundos)**
> "O **Payments API** processa pagamentos de forma idempotente. Similar ao Catalog, também tem API e Worker. O Worker consome o evento de pedido realizado, simula o processamento do pagamento com uma lógica determinística, e publica o resultado."

**Pontos-chave:**
- API + Worker (2 processos)
- Processamento determinístico (CPF par = aprovado)
- Retry: 3x (5s, 10s, 30s)
- Consome: `PedidoRealizadoEvento`
- Publica: `PagamentoProcessadoEvento`

**2.4. Notifications Worker (30 segundos)**
> "O **Notifications Worker** é o mais simples: um consumer puro que loga notificações. Ele recebe os eventos de usuário criado, pedido realizado, e pagamento processado, simulando envio de e-mails."

**Pontos-chave:**
- Consumer puro (sem API REST)
- Sem banco de dados
- Consome: todos os eventos
- Apenas loga (simula e-mail)

**[TELA: Mostrar fluxograma da mensageria]**

> "A comunicação assíncrona garante que cada serviço funcione de forma independente. Se o Payments estiver fora do ar, a mensagem fica na fila do RabbitMQ e será processada assim que ele voltar."

**⏱️ Checkpoint: 4 minutos**

---

### 3. DOCKER COMPOSE (4:00 - 8:00)

**[TELA: Abrir terminal no diretório fcg-orchestration]**

**Narração:**
> "Vamos começar pela demonstração com Docker Compose, ideal para desenvolvimento local. Primeiro, vou mostrar o arquivo de configuração."

**3.1. Arquivo .env (30 segundos)**

**[TELA: Mostrar .env ou .env.example]**

```bash
cat .env.example
```

> "O projeto usa variáveis de ambiente para configurações sensíveis: o token do NuGet para restaurar o pacote de eventos, a chave JWT que deve ser idêntica em todos os serviços, e as credenciais do RabbitMQ."

**3.2. Subir a stack (1 minuto)**

**[TELA: Terminal]**

```bash
# Mostrar o comando
docker compose up -d --build
```

> "Esse comando vai buildar as imagens Docker e subir toda a stack. O Docker Compose gerencia a ordem de inicialização através de health checks: primeiro o RabbitMQ fica pronto, depois as APIs criam os bancos de dados, e só então os workers sobem."

**[TELA: Mostrar o output do docker compose]**

**3.3. Verificar serviços (1 minuto)**

**[TELA: Terminal]**

```bash
docker compose ps
```

> "Aqui vemos os 7 containers rodando: RabbitMQ, 3 APIs (Users, Catalog, Payments), 2 Workers (Catalog, Payments), e o Notifications."

```bash
# Testar health checks
curl http://localhost:5001/health
curl http://localhost:5002/health
curl http://localhost:5003/health
```

> "Todos os serviços expõem um endpoint /health que confirma que estão operacionais."

**3.4. RabbitMQ Management (1 minuto)**

**[TELA: Browser - http://localhost:15672]**

> "O RabbitMQ Management UI mostra as filas que foram criadas automaticamente pelos serviços. Veja aqui: catalog-usuario-criado, payments-pedido-realizado, e notifications com as 3 filas."

**[TELA: Mostrar a aba Queues]**

> "Neste momento as filas estão vazias porque ainda não fizemos nenhuma operação. Vamos ver isso em ação mais tarde."

**3.5. Logs (30 segundos)**

**[TELA: Terminal]**

```bash
docker compose logs -f notifications-worker
```

> "Os logs mostram que os serviços estão conectados ao RabbitMQ e prontos para processar mensagens. Vou deixar esse terminal aberto para vermos as notificações em tempo real."

**⏱️ Checkpoint: 8 minutos**

---

### 4. KUBERNETES (8:00 - 14:00)

**[TELA: Parar o Docker Compose]**

```bash
docker compose down
```

**Narração:**
> "Agora vamos para o deploy no Kubernetes, que é o foco principal desta fase do Tech Challenge. Vou mostrar a estrutura dos manifestos e depois fazer o deploy."

**4.1. Estrutura dos Manifestos (1:30)**

**[TELA: Explorer - mostrar pastas k8s]**

> "Cada microsserviço tem sua pasta /k8s com os manifestos. O repositório de orquestração tem o namespace e o RabbitMQ, que são a infraestrutura base."

**[TELA: Abrir um deployment.yaml como exemplo]**

> "Cada serviço utiliza os seguintes recursos Kubernetes:"

| Recurso | Quantidade | Descrição |
|---------|------------|-----------|
| **Namespace** | 1 | `fcgames` - isolamento lógico |
| **Deployments** | 7 | Gerenciam os Pods (APIs + Workers + RabbitMQ) |
| **Services** | 7 | ClusterIP para comunicação interna |
| **ConfigMaps** | 5 | Configurações não sensíveis |
| **Secrets** | 5 | Credenciais e dados sensíveis |
| **PVCs** | 3 | Persistência SQLite (1Gi ReadWriteMany) |

**4.2. ConfigMaps vs Secrets (1:30)**

**[TELA: Mostrar um configmap.yaml]**

> "Os **ConfigMaps** armazenam configurações não sensíveis como URLs dos serviços e nomes de hosts. Por exemplo, aqui vemos que o host do RabbitMQ é 'rabbitmq', usando o Service Discovery do Kubernetes."

**[TELA: Mostrar um secret.yaml]**

> "Já os **Secrets** guardam dados sensíveis: chave JWT, strings de conexão com o banco, e credenciais do RabbitMQ. Os valores estão em base64, mas em produção deveríamos usar ferramentas como Sealed Secrets ou External Secrets Operator."

**Pontos importantes:**
- ConfigMaps: `RABBITMQ_HOST`, `JWT_ISSUER`, URLs
- Secrets: `JWT_KEY`, `ConnectionStrings`, `RABBITMQ_USER/PASS`

**4.3. Deploy Automatizado (2 minutos)**

**[TELA: Terminal]**

> "Criei um script PowerShell que automatiza todo o processo de deploy. Vamos executá-lo."

```powershell
.\k8s\deploy.ps1
```

**[TELA: Acompanhar o output do script]**

> "O script faz o seguinte:"
- Cria o namespace `fcgames`
- Aplica os manifestos do RabbitMQ
- Aguarda o RabbitMQ ficar pronto
- Aplica os manifestos de cada microsserviço em sequência
- No final, mostra os pods rodando

**[TELA: Mostrar kubectl get pods]**

```bash
kubectl get pods -n fcgames
```

> "Aqui vemos todos os 7 pods em estado Running. Note que os nomes têm um hash no final - isso é característico de Deployments, que é o recurso recomendado pelo Tech Challenge."

**4.4. Services e Comunicação (1 minuto)**

**[TELA: Terminal]**

```bash
kubectl get services -n fcgames
```

> "Os Services criam um DNS interno no Kubernetes. Por exemplo, 'rabbitmq' resolve para o IP do pod do RabbitMQ. É assim que os serviços se encontram, sem precisar saber IPs fixos."

**[TELA: Mostrar ConfigMap com RABBITMQ_HOST=rabbitmq]**

> "Veja aqui no ConfigMap: o host é simplesmente 'rabbitmq', o nome do Service. O Kubernetes resolve isso automaticamente."

**4.5. PersistentVolumeClaims (1 minuto)**

**[TELA: Terminal]**

```bash
kubectl get pvc -n fcgames
```

> "Os PersistentVolumeClaims garantem que os bancos SQLite sejam persistidos mesmo se os pods forem recriados. Cada serviço tem seu próprio volume de 1GB com modo ReadWriteMany, permitindo que API e Worker compartilhem o mesmo arquivo de banco."

**4.6. Port-Forward para Acessar (1 minuto)**

**[TELA: Terminal - abrir múltiplas abas]**

```bash
# Terminal 1
kubectl port-forward -n fcgames svc/users-api 5001:80

# Terminal 2
kubectl port-forward -n fcgames svc/catalog-api 5002:80

# Terminal 3
kubectl port-forward -n fcgames svc/payments-api 5003:80

# Terminal 4
kubectl port-forward -n fcgames svc/rabbitmq 15672:15672
```

> "Como estamos usando ClusterIP, precisamos do port-forward para acessar os serviços de fora do cluster. Em produção, usaríamos um Ingress ou LoadBalancer."

**⏱️ Checkpoint: 14 minutos**

---

### 5. FLUXO END-TO-END (14:00 - 18:00)

**[TELA: Browser com Swagger do Users API - localhost:5001/swagger]**

**Narração:**
> "Agora vamos executar um fluxo completo: criar um usuário, fazer login, cadastrar um jogo como admin, e realizar uma compra. Vou usar o Swagger para facilitar a visualização."

**5.1. Cadastrar Usuário (1 minuto)**

**[TELA: POST /usuarios]**

```json
{
  "nome": "João Silva",
  "email": "joao@email.com",
  "senha": "Senha@123",
  "cpf": "12345678900"
}
```

> "Ao criar o usuário, o Users API retorna 201 Created e publica um evento. Vamos ver o que aconteceu nos logs."

**[TELA: Terminal com logs do notifications-worker]**

```bash
kubectl logs -n fcgames -l app=notifications-worker -f
```

> "Aqui está: 'Email de boas-vindas enviado para joao@email.com'. O Notifications recebeu o evento instantaneamente."

**[TELA: RabbitMQ Management - mostrar mensagem processada]**

> "No RabbitMQ, vemos que a mensagem foi entregue e reconhecida."

**5.2. Login (30 segundos)**

**[TELA: POST /usuarios/login]**

```json
{
  "email": "joao@email.com",
  "senha": "Senha@123"
}
```

> "O login retorna o token JWT. Vou copiar esse token para usar nas próximas requisições."

**[TELA: Copiar o token]**

**5.3. Cadastrar Jogo como Admin (1 minuto)**

**[TELA: Browser com Swagger do Catalog API - localhost:5002/swagger]**

> "Para cadastrar um jogo, preciso estar autenticado como Admin. Vou usar o usuário seed que já está no banco."

**[TELA: POST /usuarios/login com admin@fcgames.com]**

> "Fazendo login como admin e obtendo o token de administrador."

**[TELA: Authorize no Swagger - colar token]**

**[TELA: POST /jogos]**

```json
{
  "titulo": "The Witcher 3",
  "descricao": "RPG de mundo aberto",
  "preco": 89.90,
  "categorias": ["RPG", "Ação"]
}
```

> "Jogo cadastrado com sucesso. Agora vou voltar com o usuário comum para fazer a compra."

**5.4. Realizar Compra (1:30)**

**[TELA: Authorize com o token do João]**

**[TELA: GET /jogos]**

> "Primeiro vejo o catálogo de jogos disponíveis."

**[TELA: POST /compras]**

```json
{
  "jogoId": 1,
  "usuarioId": 1,
  "preco": 89.90
}
```

> "A compra retorna 202 Accepted, indicando que foi aceita para processamento assíncrono. Note o campo 'orderId' que vamos usar para acompanhar o status."

**5.5. Acompanhar Processamento (1:30)**

**[TELA: Mostrar logs em tempo real]**

```bash
# Terminal 1 - Catalog Worker
kubectl logs -n fcgames -l app=catalog-worker -f

# Terminal 2 - Payments Worker
kubectl logs -n fcgames -l app=payments-worker -f

# Terminal 3 - Notifications Worker
kubectl logs -n fcgames -l app=notifications-worker -f
```

> "Veja a sequência de eventos:"
1. **Catalog Worker** publica PedidoRealizadoEvento
2. **Payments Worker** recebe o evento, simula o processamento
3. CPF do João termina em 0 (par), então o pagamento é **APROVADO**
4. **Payments Worker** publica PagamentoProcessadoEvento
5. **Catalog Worker** recebe e adiciona o jogo na biblioteca
6. **Notifications** loga os 3 e-mails: pedido realizado, pagamento processado, jogo adicionado

**5.6. Verificar Resultado (30 segundos)**

**[TELA: GET /compras/{orderId}]**

```json
{
  "orderId": "abc-123",
  "status": "Aprovado",
  "jogoId": 1,
  "titulo": "The Witcher 3",
  "valor": 89.90
}
```

**[TELA: GET /biblioteca/{userId}]**

```json
{
  "usuarioId": 1,
  "jogos": [
    {
      "jogoId": 1,
      "titulo": "The Witcher 3",
      "adicionadoEm": "2026-07-08T14:30:00Z"
    }
  ]
}
```

> "Perfeito! O jogo apareceu na biblioteca do João. Todo o fluxo assíncrono funcionou corretamente."

**⏱️ Checkpoint: 18 minutos**

---

### 6. ENCERRAMENTO (18:00 - 20:00)

**[TELA: Slides ou README com checklist]**

**Narração:**
> "Vamos recapitular o que foi implementado neste projeto e como atendemos os requisitos do Tech Challenge Fase 2."

**6.1. Requisitos Atendidos (1:30)**

✅ **Arquitetura de Microsserviços**
- 4 microsserviços independentes
- Comunicação assíncrona via RabbitMQ
- Cada serviço com seu próprio banco de dados

✅ **Kubernetes**
- 7 Deployments (não StatefulSets)
- 7 Services com ClusterIP
- 5 ConfigMaps para configurações não sensíveis
- 5 Secrets para dados sensíveis
- 3 PersistentVolumeClaims para persistência
- Namespace dedicado: `fcgames`

✅ **Documentação**
- README principal com instruções Docker e Kubernetes
- API Reference completa
- Scripts de automação (deploy.ps1, port-forward.ps1)
- ADRs (Architecture Decision Records)

✅ **Mensageria**
- RabbitMQ com MassTransit
- Retry automático (3x)
- Idempotência por chave de negócio
- Dead Letter Queue

✅ **Segurança**
- JWT Bearer Token
- Secrets do Kubernetes
- Validação de roles (Standard, Admin)

✅ **Observabilidade**
- Health checks em todos os serviços
- CorrelationId em todos os logs e eventos
- Logs estruturados

**6.2. Tecnologias (30 segundos)**

| Camada | Tecnologia |
|--------|------------|
| Backend | .NET 10, C# 13 |
| Arquitetura | CQRS, MediatR, FluentValidation |
| Mensageria | RabbitMQ 3 + MassTransit |
| Banco de Dados | SQLite + Entity Framework Core |
| Orquestração | Kubernetes + Docker Compose |
| Autenticação | JWT Bearer |
| Pacote Compartilhado | NuGet privado (GitHub Packages) |

**6.3. Repositórios (10 segundos)**

> "Todo o código está organizado em 5 repositórios no GitHub:"
- fcg-users-api
- fcg-catalog-api
- fcg-payments-api
- fcg-notifications-api
- fcg-orchestration (infraestrutura)

**6.4. Agradecimento (10 segundos)**

**[TELA: Logo FIAP ou tela final]**

> "Obrigado pela atenção! Este projeto demonstra uma arquitetura moderna, escalável e preparada para ambientes cloud-native. Estou à disposição para dúvidas."

**[FIM - 20:00]**

---

## 🎯 Dicas para Gravação

### Preparação Antes de Gravar

1. **Ambiente Limpo**
   ```bash
   # Parar tudo
   docker compose down -v
   kubectl delete namespace fcgames
   
   # Limpar terminal history
   clear
   ```

2. **Testar o Fluxo Completo**
   - Rodar Docker Compose e testar API
   - Rodar Kubernetes e testar API
   - Anotar os IDs/tokens gerados

3. **Ter Arquivos Abertos**
   - README.md principal
   - docker-compose.yml
   - Um deployment.yaml de exemplo
   - Um configmap.yaml e secret.yaml
   - fcgames.http (requisições prontas)

4. **Terminals Organizados**
   - Terminal 1: Comandos principais (fcg-orchestration)
   - Terminal 2: Logs Docker Compose
   - Terminal 3-5: Port-forward Kubernetes
   - Terminal 6-8: Logs Kubernetes

### Durante a Gravação

1. **Fale Devagar e Claro**
   - Pause entre seções
   - Explique o QUE está fazendo ANTES de fazer
   - Não fique em silêncio enquanto aguarda comandos

2. **Mostre os Resultados**
   - Nunca assuma que funcionou - MOSTRE
   - Logs, RabbitMQ UI, Swagger responses
   - kubectl get pods, describe, logs

3. **Gestão de Tempo**
   - Use cronômetro visível
   - Se estourar em uma seção, corte outra
   - Prioridade: Kubernetes > Docker Compose

4. **Troubleshooting ao Vivo**
   - Se algo falhar, MOSTRE como debugar
   - kubectl describe pod
   - kubectl logs
   - kubectl get events
   - Isso demonstra conhecimento real

### Checklist Pré-Gravação

- [ ] Docker Desktop rodando
- [ ] Kubernetes habilitado
- [ ] .env configurado com tokens válidos
- [ ] Imagens buildadas (docker build)
- [ ] Nenhum container/pod rodando
- [ ] Browser com abas prontas (Swagger, RabbitMQ)
- [ ] VS Code com arquivos abertos
- [ ] Postman/Insomnia com requests prontas (alternativa ao Swagger)
- [ ] Cronômetro iniciado

### Alternativas Caso Algo Falhe

**Plano B - Kubernetes não funciona:**
- Grave só Docker Compose
- Mostre os manifestos YAML
- Explique o que SERIA feito no K8s
- Mostre prints de uma execução anterior

**Plano C - Tempo apertado:**
- Pule a seção Docker Compose
- Foque 100% no Kubernetes
- Use fcgames.http ao invés de Swagger (mais rápido)

---

## 📊 Métricas do Projeto

Para mencionar na apresentação:

| Métrica | Valor |
|---------|-------|
| Microsserviços | 4 |
| Deployments | 7 |
| Services | 7 |
| ConfigMaps | 5 |
| Secrets | 5 |
| PVCs | 3 |
| Filas RabbitMQ | 7 |
| Eventos | 3 tipos |
| Endpoints REST | ~20 |
| Linhas de Código | ~8.000+ |
| Arquivos YAML | 26 |

---

## 🎬 Script Resumido (Cola)

**1. ABERTURA (1min)**
"Projeto FCGames, microsserviços .NET 10 + Kubernetes"

**2. ARQUITETURA (3min)**
- Users: JWT + publica UsuarioCriado
- Catalog: API+Worker, biblioteca
- Payments: API+Worker, processamento determinístico
- Notifications: consumer puro, loga e-mails

**3. DOCKER COMPOSE (4min)**
```bash
docker compose up -d --build
docker compose ps
curl health checks
RabbitMQ UI
```

**4. KUBERNETES (6min)**
- Mostrar estrutura k8s/
- ConfigMaps vs Secrets
- `.\k8s\deploy.ps1`
- `kubectl get pods/svc/pvc`
- Port-forward

**5. FLUXO E2E (4min)**
- POST /usuarios
- POST /usuarios/login
- Login admin + POST /jogos
- POST /compras
- Logs workers
- GET /biblioteca

**6. ENCERRAMENTO (2min)**
- Checklist requisitos
- Tecnologias
- Agradecimento

---

**BOA SORTE! 🚀**
