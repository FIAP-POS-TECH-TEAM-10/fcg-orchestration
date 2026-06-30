#!/bin/bash
# Script de validação dos manifestos Kubernetes
# Pode ser executado sem cluster Kubernetes ativo

echo "Validando Manifestos Kubernetes do FCGames..."
echo ""

hasErrors=false
manifestCount=0

validate_manifest() {
    local path=$1
    local name=$2
    
    echo -n "Validando: $name"
    
    if [ -f "$path" ]; then
        if kubectl apply -f "$path" --dry-run=client > /dev/null 2>&1; then
            echo " [OK]"
            return 0
        else
            echo " [ERRO]"
            kubectl apply -f "$path" --dry-run=client 2>&1 | sed 's/^/  /'
            return 1
        fi
    else
        echo " [ERRO] (arquivo não encontrado)"
        return 1
    fi
}

echo "fcg-orchestration/k8s/"
orchestrationPath="k8s"
((manifestCount++)); validate_manifest "$orchestrationPath/namespace.yaml" "namespace.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$orchestrationPath/rabbitmq-secret.yaml" "rabbitmq-secret.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$orchestrationPath/rabbitmq-configmap.yaml" "rabbitmq-configmap.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$orchestrationPath/rabbitmq-deployment.yaml" "rabbitmq-deployment.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$orchestrationPath/rabbitmq-service.yaml" "rabbitmq-service.yaml" || hasErrors=true

echo ""
echo "fcg-users-api/k8s/"
usersPath="../fcg-users-api/k8s"
((manifestCount++)); validate_manifest "$usersPath/secret.yaml" "secret.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$usersPath/configmap.yaml" "configmap.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$usersPath/pvc.yaml" "pvc.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$usersPath/deployment.yaml" "deployment.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$usersPath/service.yaml" "service.yaml" || hasErrors=true

echo ""
echo "fcg-catalog-api/k8s/"
catalogPath="../fcg-catalog-api/k8s"
((manifestCount++)); validate_manifest "$catalogPath/secret.yaml" "secret.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$catalogPath/configmap.yaml" "configmap.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$catalogPath/pvc.yaml" "pvc.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$catalogPath/deployment-api.yaml" "deployment-api.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$catalogPath/deployment-worker.yaml" "deployment-worker.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$catalogPath/service.yaml" "service.yaml" || hasErrors=true

echo ""
echo "fcg-payments-api/k8s/"
paymentsPath="../fcg-payments-api/k8s"
((manifestCount++)); validate_manifest "$paymentsPath/secret.yaml" "secret.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$paymentsPath/configmap.yaml" "configmap.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$paymentsPath/pvc.yaml" "pvc.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$paymentsPath/deployment-api.yaml" "deployment-api.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$paymentsPath/deployment-worker.yaml" "deployment-worker.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$paymentsPath/service.yaml" "service.yaml" || hasErrors=true

echo ""
echo "fcg-notifications-api/k8s/"
notificationsPath="../fcg-notifications-api/k8s"
((manifestCount++)); validate_manifest "$notificationsPath/secret.yaml" "secret.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$notificationsPath/configmap.yaml" "configmap.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$notificationsPath/deployment.yaml" "deployment.yaml" || hasErrors=true
((manifestCount++)); validate_manifest "$notificationsPath/service.yaml" "service.yaml" || hasErrors=true

echo ""
echo "========================================"
echo "Resumo da Validação"
echo "========================================"
echo "Total de manifestos: $manifestCount"

if [ "$hasErrors" = true ]; then
    echo "Status: FALHOU"
    echo ""
    echo "Alguns manifestos têm erros de sintaxe."
    echo "Revise os erros acima e corrija antes de aplicar no cluster."
    exit 1
else
    echo "Status: SUCESSO"
    echo ""
    echo "Todos os manifestos estão sintaticamente corretos!"
    echo "Você pode prosseguir com o deploy no cluster Kubernetes."
    echo ""
    echo "Próximos passos:"
    echo "  1. Buildar as imagens Docker"
    echo "  2. Executar: ./k8s/deploy.sh"
    exit 0
fi
