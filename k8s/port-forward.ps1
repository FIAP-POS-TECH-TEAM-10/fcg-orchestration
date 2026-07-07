# Port-forward automático para todos os serviços FCGames
# Execute este script para acessar os serviços do Kubernetes localmente

Write-Host "Configurando port-forward para FCGames..." -ForegroundColor Green
Write-Host "Pressione Ctrl+C para encerrar TODOS os port-forwards" -ForegroundColor Yellow
Write-Host ""

$namespace = "fcgames"

# Verificar se namespace existe
$namespaceExists = kubectl get namespace $namespace 2>$null
if (-not $namespaceExists) {
    Write-Host "[ERRO] Namespace '$namespace' não encontrado!" -ForegroundColor Red
    Write-Host "Execute primeiro: .\deploy.ps1" -ForegroundColor Yellow
    exit 1
}

# Verificar se há pods rodando
$pods = kubectl get pods -n $namespace --no-headers 2>$null
if (-not $pods) {
    Write-Host "[ERRO] Nenhum pod encontrado no namespace '$namespace'!" -ForegroundColor Red
    Write-Host "Execute primeiro: .\deploy.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "Services disponíveis:" -ForegroundColor Cyan
kubectl get services -n $namespace
Write-Host ""

# Função para iniciar port-forward em background
function Start-PortForward {
    param(
        [string]$Service,
        [string]$Port,
        [string]$Description
    )
    
    Write-Host "[OK] $Description" -ForegroundColor Green
    Write-Host "     -> http://localhost:$($Port.Split(':')[0])" -ForegroundColor White
    
    Start-Job -ScriptBlock {
        param($ns, $svc, $port)
        kubectl port-forward -n $ns svc/$svc $port
    } -ArgumentList $namespace, $Service, $Port | Out-Null
}

# Iniciar todos os port-forwards
Start-PortForward "users-api" "5001:80" "Users API"
Start-PortForward "catalog-api" "5002:80" "Catalog API"
Start-PortForward "payments-api" "5003:80" "Payments API"
Start-PortForward "notifications-worker" "5004:80" "Notifications Worker"
Start-PortForward "rabbitmq" "5672:5672" "RabbitMQ AMQP"
Start-PortForward "rabbitmq" "15672:15672" "RabbitMQ Management UI"

Write-Host ""
Write-Host "Port-forwards ativos:" -ForegroundColor Cyan
Write-Host "  Users API:            http://localhost:5001/swagger" -ForegroundColor White
Write-Host "  Catalog API:          http://localhost:5002/swagger" -ForegroundColor White
Write-Host "  Payments API:         http://localhost:5003/swagger" -ForegroundColor White
Write-Host "  Notifications:        http://localhost:5004/health" -ForegroundColor White
Write-Host "  RabbitMQ AMQP:        amqp://localhost:5672" -ForegroundColor White
Write-Host "  RabbitMQ Management:  http://localhost:15672" -ForegroundColor White
Write-Host "                        (User: admin / Pass: FCGames@2024)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "[ATIVO] Port-forwards em execução. Pressione Ctrl+C para encerrar." -ForegroundColor Green
Write-Host ""

# Aguardar Ctrl+C
try {
    while ($true) {
        Start-Sleep -Seconds 5
        
        # Verificar se algum job morreu
        $failedJobs = Get-Job | Where-Object { $_.State -eq 'Failed' }
        if ($failedJobs) {
            Write-Host "[AVISO] Alguns port-forwards falharam. Verifique se as portas estão disponíveis." -ForegroundColor Yellow
            $failedJobs | Remove-Job
        }
    }
}
finally {
    Write-Host "`n`nEncerrando port-forwards..." -ForegroundColor Yellow
    Get-Job | Stop-Job
    Get-Job | Remove-Job
    Write-Host "[OK] Port-forwards encerrados." -ForegroundColor Green
}
