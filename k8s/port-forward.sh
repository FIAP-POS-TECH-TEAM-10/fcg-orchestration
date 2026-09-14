#!/bin/bash
# Port-forward automático para todos os serviços FCGames
# Execute este script para acessar os serviços do Kubernetes localmente

echo "Configurando port-forward para FCGames..."
echo "Pressione Ctrl+C para encerrar TODOS os port-forwards"
echo ""

NAMESPACE="fcgames"

# Verificar se namespace existe
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "[ERRO] Namespace '$NAMESPACE' não encontrado!"
    echo "Execute primeiro: ./deploy.sh"
    exit 1
fi

# Verificar se há pods rodando
if ! kubectl get pods -n $NAMESPACE --no-headers &> /dev/null; then
    echo "[ERRO] Nenhum pod encontrado no namespace '$NAMESPACE'!"
    echo "Execute primeiro: ./deploy.sh"
    exit 1
fi

echo "Services disponíveis:"
kubectl get services -n $NAMESPACE
echo ""

# Array para armazenar PIDs dos port-forwards
declare -a PIDS

# Função para cleanup ao encerrar
cleanup() {
    echo ""
    echo ""
    echo "Encerrando port-forwards..."
    for pid in "${PIDS[@]}"; do
        kill $pid 2>/dev/null
    done
    echo "[OK] Port-forwards encerrados."
    exit 0
}

# Registrar trap para Ctrl+C
trap cleanup SIGINT SIGTERM

# Iniciar port-forwards em background
echo "[OK] Users API"
echo "     -> http://localhost:5001"
kubectl port-forward -n $NAMESPACE svc/users-api 5001:80 &> /dev/null &
PIDS+=($!)

echo "[OK] Catalog API"
echo "     -> http://localhost:5002"
kubectl port-forward -n $NAMESPACE svc/catalog-api 5002:80 &> /dev/null &
PIDS+=($!)

echo "[OK] Payments API"
echo "     -> http://localhost:5003"
kubectl port-forward -n $NAMESPACE svc/payments-api 5003:80 &> /dev/null &
PIDS+=($!)

echo "[OK] Notifications Worker"
echo "     -> http://localhost:5004"
kubectl port-forward -n $NAMESPACE svc/notifications-worker 5004:80 &> /dev/null &
PIDS+=($!)

echo "[OK] RabbitMQ AMQP"
echo "     -> amqp://localhost:5672"
kubectl port-forward -n $NAMESPACE svc/rabbitmq 5672:5672 &> /dev/null &
PIDS+=($!)

echo "[OK] RabbitMQ Management UI"
echo "     -> http://localhost:15672"
kubectl port-forward -n $NAMESPACE svc/rabbitmq 15672:15672 &> /dev/null &
PIDS+=($!)

echo "[OK] DynamoDB Local (tabela Jogos)"
echo "     -> http://localhost:8000"
kubectl port-forward -n $NAMESPACE svc/dynamodb-local 8000:8000 &> /dev/null &
PIDS+=($!)

echo ""
echo "Port-forwards ativos:"
echo "  Users API:            http://localhost:5001/swagger"
echo "  Catalog API:          http://localhost:5002/swagger"
echo "  Payments API:         http://localhost:5003/swagger"
echo "  Notifications:        http://localhost:5004/health"
echo "  RabbitMQ AMQP:        amqp://localhost:5672"
echo "  RabbitMQ Management:  http://localhost:15672"
echo "                        (User: admin / Pass: FCGames@2024)"
echo "  DynamoDB Local:       http://localhost:8000 (aws dynamodb scan --endpoint-url http://localhost:8000)"
echo ""
echo "[ATIVO] Port-forwards em execução. Pressione Ctrl+C para encerrar."
echo ""

# Aguardar indefinidamente
wait
