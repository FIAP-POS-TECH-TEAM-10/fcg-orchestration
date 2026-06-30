# Deploy completo do FCGames no Kubernetes
# Execute este script a partir do diretório fcg-orchestration

Write-Host "Iniciando deploy do FCGames no Kubernetes..." -ForegroundColor Green

# 1. Criar namespace e infraestrutura
Write-Host "`nCriando namespace e RabbitMQ..." -ForegroundColor Cyan
kubectl apply -f k8s/

Write-Host "`nAguardando RabbitMQ ficar pronto..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=rabbitmq -n fcgames --timeout=300s

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERRO] Falha ao aguardar RabbitMQ" -ForegroundColor Red
    exit 1
}

# 2. Deploy Users API
Write-Host "`nDeploy do Users API..." -ForegroundColor Cyan
Push-Location ..\fcg-users-api
kubectl apply -f k8s/
Pop-Location

# 3. Deploy Catalog API + Worker
Write-Host "`nDeploy do Catalog API + Worker..." -ForegroundColor Cyan
Push-Location ..\fcg-catalog-api
kubectl apply -f k8s/
Pop-Location

# 4. Deploy Payments API + Worker
Write-Host "`nDeploy do Payments API + Worker..." -ForegroundColor Cyan
Push-Location ..\fcg-payments-api
kubectl apply -f k8s/
Pop-Location

# 5. Deploy Notifications Worker
Write-Host "`nDeploy do Notifications Worker..." -ForegroundColor Cyan
Push-Location ..\fcg-notifications-api
kubectl apply -f k8s/
Pop-Location

# 6. Verificar status
Write-Host "`nAguardando todos os pods ficarem prontos..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host "`nStatus dos Pods:" -ForegroundColor Cyan
kubectl get pods -n fcgames

Write-Host "`nServices disponíveis:" -ForegroundColor Cyan
kubectl get services -n fcgames

Write-Host "`n[OK] Deploy concluído com sucesso!" -ForegroundColor Green
Write-Host "`nPara acessar os serviços localmente, use port-forward:" -ForegroundColor Yellow
Write-Host "  kubectl port-forward -n fcgames svc/users-api 5001:80" -ForegroundColor White
Write-Host "  kubectl port-forward -n fcgames svc/catalog-api 5002:80" -ForegroundColor White
Write-Host "  kubectl port-forward -n fcgames svc/payments-api 5003:80" -ForegroundColor White
Write-Host "  kubectl port-forward -n fcgames svc/rabbitmq 15672:15672" -ForegroundColor White
