# FCGames - Kubernetes Orchestration

Este repositório contém os manifestos Kubernetes para orquestração da infraestrutura compartilhada do FCGames.

## Conteúdo

- **Namespace**: Define o namespace `fcgames` para isolar todos os recursos
- **RabbitMQ**: Message broker para comunicação assíncrona entre microsserviços

## Deploy no Kubernetes

### Pré-requisitos

- Kubernetes cluster local (Kind, Minikube, k3d ou Docker Desktop Kubernetes)
- kubectl configurado
- Imagens Docker buildadas de todos os microsserviços

### Buildando as Imagens Docker

Antes de fazer o deploy, você precisa buildar as imagens Docker de cada microsserviço:

```bash
# Users API
cd ../fcg-users-api
docker build -t fcg-users-api:latest .

# Catalog API e Worker
cd ../fcg-catalog-api
docker build -t fcg-catalog-api:latest -f Dockerfile .
docker build -t fcg-catalog-worker:latest -f Dockerfile.worker .

# Payments API e Worker
cd ../fcg-payments-api
docker build -t fcg-payments-api:latest -f Dockerfile .
docker build -t fcg-payments-worker:latest -f Dockerfile.worker .

# Notifications Worker
cd ../fcg-notifications-api
docker build -t fcg-notifications-worker:latest .
```

### Ordem de Deploy

1. **Criar Namespace e RabbitMQ (Infraestrutura)**

```bash
cd fcg-orchestration
kubectl apply -f k8s/
```

2. **Aguardar RabbitMQ ficar pronto**

```bash
kubectl wait --for=condition=ready pod -l app=rabbitmq -n fcgames --timeout=300s
```

3. **Deploy dos Microsserviços**

```bash
# Users API
cd ../fcg-users-api
kubectl apply -f k8s/

# Catalog API + Worker
cd ../fcg-catalog-api
kubectl apply -f k8s/

# Payments API + Worker
cd ../fcg-payments-api
kubectl apply -f k8s/

# Notifications Worker
cd ../fcg-notifications-api
kubectl apply -f k8s/
```

## Verificação

### Ver todos os Pods

```bash
kubectl get pods -n fcgames
```

### Ver todos os Services

```bash
kubectl get services -n fcgames
```

### Ver ConfigMaps e Secrets

```bash
kubectl get configmaps -n fcgames
kubectl get secrets -n fcgames
```

### Logs de um Pod específico

```bash
# Exemplo: ver logs do RabbitMQ
kubectl logs -n fcgames -l app=rabbitmq

# Exemplo: ver logs do Users API
kubectl logs -n fcgames -l app=users-api
```

## Acesso aos Serviços

Para acessar os serviços localmente, use port-forward:

```bash
# RabbitMQ Management UI
kubectl port-forward -n fcgames svc/rabbitmq 15672:15672

# Users API
kubectl port-forward -n fcgames svc/users-api 5001:80

# Catalog API
kubectl port-forward -n fcgames svc/catalog-api 5002:80

# Payments API
kubectl port-forward -n fcgames svc/payments-api 5003:80

# Notifications Worker
kubectl port-forward -n fcgames svc/notifications-worker 5004:80
```

## Limpeza

Para remover todos os recursos:

```bash
kubectl delete namespace fcgames
```

## Notas

- **Secrets**: As credenciais padrão estão configuradas nos arquivos. Em produção, use valores seguros e considere usar ferramentas como Sealed Secrets ou External Secrets Operator.
- **ConfigMaps**: Configurações não sensíveis como URLs de serviços e nomes de hosts.
- **PersistentVolumeClaims**: Usado para persistir os bancos de dados SQLite. Em produção, considere usar bancos de dados externos.

## Comunicação entre Serviços

Os serviços se comunicam internamente usando os nomes de Service do Kubernetes:
- `http://rabbitmq:5672` - RabbitMQ AMQP
- `http://users-api:80` - Users API
- `http://catalog-api:80` - Catalog API
- `http://payments-api:80` - Payments API
- `http://notifications-worker:80` - Notifications Worker
