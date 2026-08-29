# Build completo de todas as imagens Docker do FCGames
# Execute este script a partir do diretório fcg-orchestration

Write-Host "Buildando todas as imagens Docker do FCGames..." -ForegroundColor Green
Write-Host ""

# Verificar se .env existe
if (-not (Test-Path .env)) {
    Write-Host "[ERRO] Arquivo .env não encontrado!" -ForegroundColor Red
    Write-Host "Copie o .env.example e preencha o NUGET_AUTH_TOKEN:" -ForegroundColor Yellow
    Write-Host "  cp .env.example .env" -ForegroundColor White
    exit 1
}

# Ler NUGET_AUTH_TOKEN do .env
$envContent = Get-Content .env
$nugetToken = ($envContent | Where-Object { $_ -match "^NUGET_AUTH_TOKEN=" }) -replace "NUGET_AUTH_TOKEN=", ""

if ([string]::IsNullOrWhiteSpace($nugetToken)) {
    Write-Host "[ERRO] NUGET_AUTH_TOKEN não encontrado no .env!" -ForegroundColor Red
    Write-Host "Preencha o arquivo .env com seu token do GitHub (scope: read:packages)" -ForegroundColor Yellow
    exit 1
}

Write-Host "Token NuGet configurado: $($nugetToken.Substring(0, 7))..." -ForegroundColor Cyan
Write-Host ""

$totalImages = 6
$currentImage = 0
$startTime = Get-Date

# Copiar para a Users API
Copy-Item .\nuget.config -Destination ..\fcg-users-service\

# Copiar para a Catalog API/Worker
Copy-Item .\nuget.config -Destination ..\fcg-catalog-service\

# Copiar para a Payments API/Worker
Copy-Item .\nuget.config -Destination ..\fcg-payments-service\

# Copiar para a Notifications Worker
Copy-Item .\nuget.config -Destination ..\fcg-notifications-service\

function Build-Image {
    param(
        [string]$Path,
        [string]$ImageName,
        [string]$Dockerfile = "Dockerfile",
        [string]$Description
    )
    
    $script:currentImage++
    Write-Host "[$script:currentImage/$totalImages] Buildando $Description..." -ForegroundColor Cyan
    Write-Host "  Pasta: $Path" -ForegroundColor Gray
    Write-Host "  Imagem: $ImageName" -ForegroundColor Gray
    
    Push-Location $Path
    
    if ($Dockerfile -eq "Dockerfile") {
        docker build --build-arg NUGET_AUTH_TOKEN=$nugetToken -t $ImageName .
    } else {
        docker build --build-arg NUGET_AUTH_TOKEN=$nugetToken -t $ImageName -f $Dockerfile .
    }
    
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Host "`n[ERRO] Falha ao buildar $Description!" -ForegroundColor Red
        exit 1
    }
    
    Pop-Location
    Write-Host "  [OK] $ImageName buildada com sucesso!" -ForegroundColor Green
    Write-Host ""
}

# 1. Users API
Build-Image `
    -Path "..\fcg-users-service" `
    -ImageName "fcg-users-api:latest" `
    -Description "Users API"

# 2. Catalog API
Build-Image `
    -Path "..\fcg-catalog-service" `
    -ImageName "fcg-catalog-api:latest" `
    -Dockerfile "Dockerfile" `
    -Description "Catalog API"

# 3. Catalog Worker
Build-Image `
    -Path "..\fcg-catalog-service" `
    -ImageName "fcg-catalog-worker:latest" `
    -Dockerfile "Dockerfile.worker" `
    -Description "Catalog Worker"

# 4. Payments API
Build-Image `
    -Path "..\fcg-payments-service" `
    -ImageName "fcg-payments-api:latest" `
    -Dockerfile "Dockerfile" `
    -Description "Payments API"

# 5. Payments Worker
Build-Image `
    -Path "..\fcg-payments-service" `
    -ImageName "fcg-payments-worker:latest" `
    -Dockerfile "Dockerfile.worker" `
    -Description "Payments Worker"

# 6. Notifications Worker
Build-Image `
    -Path "..\fcg-notifications-service" `
    -ImageName "fcg-notifications-worker:latest" `
    -Description "Notifications Worker"

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "========================================" -ForegroundColor Green
Write-Host "[OK] Todas as imagens foram buildadas com sucesso!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Tempo total: $([math]::Round($duration.TotalMinutes, 2)) minutos" -ForegroundColor Yellow
Write-Host ""
Write-Host "Imagens criadas:" -ForegroundColor Cyan
docker images | Select-String "fcg-" | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
Write-Host ""
Write-Host "Próximo passo: Deploy no Kubernetes" -ForegroundColor Yellow
Write-Host "  .\k8s\deploy.ps1" -ForegroundColor White

Write-Host "========================================" -ForegroundColor Green
Write-Host "[TASK] Subir as imagens de obsevabilidade" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Subindo stack de observabilidade..." -ForegroundColor Green
docker-compose -f ..\fcg-observabilidade-service/docker-compose.observability.yml up -d
