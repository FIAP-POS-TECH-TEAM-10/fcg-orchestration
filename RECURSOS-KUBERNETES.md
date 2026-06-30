# Resumo dos Recursos Kubernetes Criados

## Visão Geral

Total de manifestos criados: **26 arquivos YAML**

### Por Repositório

| Repositório | Arquivos | Recursos |
|------------|----------|----------|
| fcg-orchestration | 5 | Namespace, RabbitMQ (Deployment, Service, ConfigMap, Secret) |
| fcg-users-api | 5 | Deployment, Service, ConfigMap, Secret, PVC |
| fcg-catalog-api | 6 | 2 Deployments (API + Worker), Service, ConfigMap, Secret, PVC |
| fcg-payments-api | 6 | 2 Deployments (API + Worker), Service, ConfigMap, Secret, PVC |
| fcg-notifications-api | 4 | Deployment, Service, ConfigMap, Secret |

---

## fcg-orchestration/k8s/

### namespace.yaml
```yaml
Namespace: fcgames
```

### rabbitmq-secret.yaml
```yaml
Secret: rabbitmq-secret
- username
- password
```

### rabbitmq-configmap.yaml
```yaml
ConfigMap: rabbitmq-config
- host: rabbitmq
- port: 5672
- management-port: 15672
```

### rabbitmq-deployment.yaml
```yaml
Deployment: rabbitmq
- Image: rabbitmq:3-management
- Ports: 5672 (AMQP), 15672 (Management)
- Probes: liveness + readiness
- Resources: 256Mi-512Mi / 250m-500m CPU
```

### rabbitmq-service.yaml
```yaml
Service: rabbitmq (ClusterIP)
- Port 5672 (AMQP)
- Port 15672 (Management)
```

---

## fcg-users-api/k8s/

### secret.yaml
```yaml
Secret: users-api-secret
- jwt-key
- db-connection
- rabbitmq-username
- rabbitmq-password
```

### configmap.yaml
```yaml
ConfigMap: users-api-config
- jwt-issuer
- rabbitmq-host
- aspnetcore-urls
```

### pvc.yaml
```yaml
PersistentVolumeClaim: users-api-pvc
- AccessMode: ReadWriteOnce
- Size: 1Gi
```

### deployment.yaml
```yaml
Deployment: users-api
- Image: fcg-users-api:latest
- Port: 5001
- Volume: /data (users.db)
- Probes: /health endpoint
- Resources: 256Mi-512Mi / 250m-500m CPU
- Env vars: injetadas de ConfigMap e Secret
```

### service.yaml
```yaml
Service: users-api (ClusterIP)
- Port: 80 → 5001
```

---

## fcg-catalog-api/k8s/

### secret.yaml
```yaml
Secret: catalog-api-secret
- jwt-key
- db-connection
- rabbitmq-username
- rabbitmq-password
```

### configmap.yaml
```yaml
ConfigMap: catalog-api-config
- jwt-issuer
- rabbitmq-host
- aspnetcore-urls
```

### pvc.yaml
```yaml
PersistentVolumeClaim: catalog-api-pvc
- AccessMode: ReadWriteMany (compartilhado API + Worker)
- Size: 1Gi
```

### deployment-api.yaml
```yaml
Deployment: catalog-api
- Image: fcg-catalog-api:latest
- Port: 5002
- Volume: /data (catalog.db)
- Probes: /health endpoint
- Resources: 256Mi-512Mi / 250m-500m CPU
```

### deployment-worker.yaml
```yaml
Deployment: catalog-worker
- Image: fcg-catalog-worker:latest
- Volume: /data (catalog.db - compartilhado)
- Resources: 256Mi-512Mi / 250m-500m CPU
- Consome: PaymentProcessedEvent
```

### service.yaml
```yaml
Service: catalog-api (ClusterIP)
- Port: 80 → 5002
```

---

## fcg-payments-api/k8s/

### secret.yaml
```yaml
Secret: payments-api-secret
- jwt-key
- db-connection
- rabbitmq-username
- rabbitmq-password
```

### configmap.yaml
```yaml
ConfigMap: payments-api-config
- jwt-issuer
- rabbitmq-host
- aspnetcore-urls
```

### pvc.yaml
```yaml
PersistentVolumeClaim: payments-api-pvc
- AccessMode: ReadWriteMany (compartilhado API + Worker)
- Size: 1Gi
```

### deployment-api.yaml
```yaml
Deployment: payments-api
- Image: fcg-payments-api:latest
- Port: 5003
- Volume: /data (payments.db)
- Probes: /health endpoint
- Resources: 256Mi-512Mi / 250m-500m CPU
```

### deployment-worker.yaml
```yaml
Deployment: payments-worker
- Image: fcg-payments-worker:latest
- Volume: /data (payments.db - compartilhado)
- Resources: 256Mi-512Mi / 250m-500m CPU
- Consome: OrderPlacedEvent
- Publica: PaymentProcessedEvent
```

### service.yaml
```yaml
Service: payments-api (ClusterIP)
- Port: 80 → 5003
```

---

## fcg-notifications-api/k8s/

### secret.yaml
```yaml
Secret: notifications-worker-secret
- rabbitmq-username
- rabbitmq-password
```

### configmap.yaml
```yaml
ConfigMap: notifications-worker-config
- rabbitmq-host
- aspnetcore-urls
```

### deployment.yaml
```yaml
Deployment: notifications-worker
- Image: fcg-notifications-worker:latest
- Port: 5004
- Probes: /health endpoint
- Resources: 256Mi-512Mi / 250m-500m CPU
- Consome: UserCreatedEvent, PaymentProcessedEvent
```

### service.yaml
```yaml
Service: notifications-worker (ClusterIP)
- Port: 80 → 5004
```

---

## Comunicação entre Serviços

Dentro do cluster Kubernetes, os serviços se comunicam usando DNS interno:

```
rabbitmq:5672              → RabbitMQ AMQP
http://users-api:80        → Users API
http://catalog-api:80      → Catalog API
http://payments-api:80     → Payments API
http://notifications-worker:80 → Notifications Worker
```

---

## Recursos Obrigatórios Implementados

### Deployments (Obrigatório)
- [x] RabbitMQ Deployment
- [x] Users API Deployment
- [x] Catalog API Deployment
- [x] Catalog Worker Deployment
- [x] Payments API Deployment
- [x] Payments Worker Deployment
- [x] Notifications Worker Deployment

**Total: 7 Deployments** (nenhum Pod isolado)

### ConfigMaps (Obrigatório)
- [x] rabbitmq-config
- [x] users-api-config
- [x] catalog-api-config
- [x] payments-api-config
- [x] notifications-worker-config

**Total: 5 ConfigMaps** (configurações não sensíveis)

### Secrets (Obrigatório)
- [x] rabbitmq-secret
- [x] users-api-secret
- [x] catalog-api-secret
- [x] payments-api-secret
- [x] notifications-worker-secret

**Total: 5 Secrets** (dados sensíveis)

---

## Recursos Adicionais

### Services (7)
Para comunicação interna no cluster

### PersistentVolumeClaims (3)
Para persistência de dados SQLite

### Namespace (1)
Isolar todos os recursos do FCGames

---

## Ordem de Deploy

1. **Namespace** (primeiro)
2. **ConfigMaps e Secrets** (antes dos Deployments)
3. **PersistentVolumeClaims** (antes dos Deployments)
4. **RabbitMQ Deployment + Service**
5. **Users API** (Deployment + Service)
6. **Catalog API + Worker** (Deployments + Service)
7. **Payments API + Worker** (Deployments + Service)
8. **Notifications Worker** (Deployment + Service)

O script `deploy.sh` / `deploy.ps1` faz isso automaticamente!
