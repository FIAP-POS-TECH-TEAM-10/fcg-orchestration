#!/bin/bash
# Deploy completo do FCGames no Kubernetes
# Execute este script a partir do diretório fcg-orchestration

echo "Iniciando deploy do FCGames no Kubernetes..."

# 1. Criar namespace e infraestrutura
echo ""
echo "Criando namespace e RabbitMQ..."
kubectl apply -f k8s/

echo ""
echo "Aguardando RabbitMQ ficar pronto..."
kubectl wait --for=condition=ready pod -l app=rabbitmq -n fcgames --timeout=300s

if [ $? -ne 0 ]; then
    echo "[ERRO] Falha ao aguardar RabbitMQ"
    exit 1
fi

# 2. Deploy Users API
echo ""
echo "Deploy do Users API..."
cd ../fcg-users-api
kubectl apply -f k8s/
cd ../fcg-orchestration

# 3. Deploy Catalog API + Worker
echo ""
echo "Deploy do Catalog API + Worker..."
cd ../fcg-catalog-api
kubectl apply -f k8s/
cd ../fcg-orchestration

# 4. Deploy Payments API + Worker
echo ""
echo "Deploy do Payments API + Worker..."
cd ../fcg-payments-api
kubectl apply -f k8s/
cd ../fcg-orchestration

# 5. Deploy Notifications Worker
echo ""
echo "Deploy do Notifications Worker..."
cd ../fcg-notifications-api
kubectl apply -f k8s/
cd ../fcg-orchestration

# 6. Verificar status
echo ""
echo "Aguardando todos os pods ficarem prontos..."
sleep 10

echo ""
echo "Status dos Pods:"
kubectl get pods -n fcgames

echo ""
echo "Services disponíveis:"
kubectl get services -n fcgames

echo ""
echo "[OK] Deploy concluído com sucesso!"
echo ""
echo "Para acessar os serviços localmente, use port-forward:"
echo "  kubectl port-forward -n fcgames svc/users-api 5001:80"
echo "  kubectl port-forward -n fcgames svc/catalog-api 5002:80"
echo "  kubectl port-forward -n fcgames svc/payments-api 5003:80"
echo "  kubectl port-forward -n fcgames svc/rabbitmq 15672:15672"
