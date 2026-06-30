# Script de validação dos manifestos Kubernetes
# Pode ser executado sem cluster Kubernetes ativo

Write-Host "Validando Manifestos Kubernetes do FCGames..." -ForegroundColor Green
Write-Host ""

$hasErrors = $false
$manifestCount = 0

function Test-K8sManifest {
    param(
        [string]$Path,
        [string]$Name
    )
    
    Write-Host "Validando: $Name" -NoNewline
    
    if (Test-Path $Path) {
        $result = kubectl apply -f $Path --dry-run=client 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host " [OK]" -ForegroundColor Green
            return $true
        } else {
            Write-Host " [ERRO]" -ForegroundColor Red
            Write-Host "  Erro: $result" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host " [ERRO] (arquivo não encontrado)" -ForegroundColor Red
        return $false
    }
}

Write-Host "📦 fcg-orchestration/k8s/" -ForegroundColor Cyan
$orchestrationPath = "k8s"
$manifestCount += 1; if (!(Test-K8sManifest "$orchestrationPath/namespace.yaml" "namespace.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$orchestrationPath/rabbitmq-secret.yaml" "rabbitmq-secret.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$orchestrationPath/rabbitmq-configmap.yaml" "rabbitmq-configmap.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$orchestrationPath/rabbitmq-deployment.yaml" "rabbitmq-deployment.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$orchestrationPath/rabbitmq-service.yaml" "rabbitmq-service.yaml")) { $hasErrors = $true }

Write-Host ""
Write-Host "fcg-users-api/k8s/" -ForegroundColor Cyan
$usersPath = "../fcg-users-api/k8s"
$manifestCount += 1; if (!(Test-K8sManifest "$usersPath/secret.yaml" "secret.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$usersPath/configmap.yaml" "configmap.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$usersPath/pvc.yaml" "pvc.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$usersPath/deployment.yaml" "deployment.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$usersPath/service.yaml" "service.yaml")) { $hasErrors = $true }

Write-Host ""
Write-Host "fcg-catalog-api/k8s/" -ForegroundColor Cyan
$catalogPath = "../fcg-catalog-api/k8s"
$manifestCount += 1; if (!(Test-K8sManifest "$catalogPath/secret.yaml" "secret.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$catalogPath/configmap.yaml" "configmap.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$catalogPath/pvc.yaml" "pvc.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$catalogPath/deployment-api.yaml" "deployment-api.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$catalogPath/deployment-worker.yaml" "deployment-worker.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$catalogPath/service.yaml" "service.yaml")) { $hasErrors = $true }

Write-Host ""
Write-Host "fcg-payments-api/k8s/" -ForegroundColor Cyan
$paymentsPath = "../fcg-payments-api/k8s"
$manifestCount += 1; if (!(Test-K8sManifest "$paymentsPath/secret.yaml" "secret.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$paymentsPath/configmap.yaml" "configmap.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$paymentsPath/pvc.yaml" "pvc.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$paymentsPath/deployment-api.yaml" "deployment-api.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$paymentsPath/deployment-worker.yaml" "deployment-worker.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$paymentsPath/service.yaml" "service.yaml")) { $hasErrors = $true }

Write-Host ""
Write-Host "fcg-notifications-api/k8s/" -ForegroundColor Cyan
$notificationsPath = "../fcg-notifications-api/k8s"
$manifestCount += 1; if (!(Test-K8sManifest "$notificationsPath/secret.yaml" "secret.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$notificationsPath/configmap.yaml" "configmap.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$notificationsPath/deployment.yaml" "deployment.yaml")) { $hasErrors = $true }
$manifestCount += 1; if (!(Test-K8sManifest "$notificationsPath/service.yaml" "service.yaml")) { $hasErrors = $true }

Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "Resumo da Validação" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor White
Write-Host "Total de manifestos: $manifestCount" -ForegroundColor White

if ($hasErrors) {
    Write-Host "Status: FALHOU" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alguns manifestos têm erros de sintaxe." -ForegroundColor Yellow
    Write-Host "Revise os erros acima e corrija antes de aplicar no cluster." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "Status: SUCESSO" -ForegroundColor Green
    Write-Host ""
    Write-Host "Todos os manifestos estão sintaticamente corretos!" -ForegroundColor Green
    Write-Host "Você pode prosseguir com o deploy no cluster Kubernetes." -ForegroundColor Green
    Write-Host ""
    Write-Host "Próximos passos:" -ForegroundColor Cyan
    Write-Host "  1. Buildar as imagens Docker" -ForegroundColor White
    Write-Host "  2. Executar: .\k8s\deploy.ps1" -ForegroundColor White
    exit 0
}
