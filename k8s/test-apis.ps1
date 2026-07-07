# Script para testar todas as APIs após port-forward
# Execute após iniciar: .\port-forward.ps1

Write-Host "Testando APIs do FCGames..." -ForegroundColor Green
Write-Host ""

$tests = @(
    @{
        Name = "Users API Health"
        Url = "http://localhost:5001/health"
        Expected = 200
    },
    @{
        Name = "Users API Swagger"
        Url = "http://localhost:5001/swagger/index.html"
        Expected = 200
    },
    @{
        Name = "Catalog API Health"
        Url = "http://localhost:5002/health"
        Expected = 200
    },
    @{
        Name = "Catalog API Swagger"
        Url = "http://localhost:5002/swagger/index.html"
        Expected = 200
    },
    @{
        Name = "Payments API Health"
        Url = "http://localhost:5003/health"
        Expected = 200
    },
    @{
        Name = "Payments API Swagger"
        Url = "http://localhost:5003/swagger/index.html"
        Expected = 200
    },
    @{
        Name = "Notifications Worker Health"
        Url = "http://localhost:5004/health"
        Expected = 200
    },
    @{
        Name = "RabbitMQ Management"
        Url = "http://localhost:15672"
        Expected = 200
    }
)

$passed = 0
$failed = 0

foreach ($test in $tests) {
    Write-Host "Testando: $($test.Name)... " -NoNewline
    
    try {
        $response = Invoke-WebRequest -Uri $test.Url -Method Get -TimeoutSec 5 -UseBasicParsing
        
        if ($response.StatusCode -eq $test.Expected) {
            Write-Host "[OK]" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[FALHOU] Status: $($response.StatusCode)" -ForegroundColor Red
            $failed++
        }
    }
    catch {
        Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
    
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "Resumo:" -ForegroundColor Cyan
Write-Host "  Passou: $passed" -ForegroundColor Green
Write-Host "  Falhou: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

if ($failed -eq 0) {
    Write-Host "`n[OK] Todas as APIs estão funcionando!" -ForegroundColor Green
} else {
    Write-Host "`n[AVISO] Algumas APIs falharam. Verifique os logs." -ForegroundColor Yellow
    Write-Host "Execute: .\logs.ps1 -Follow" -ForegroundColor White
}
