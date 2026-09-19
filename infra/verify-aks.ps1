<#
.SYNOPSIS
    Validación rápida y finita del estado del clúster AKS antes de la sustentación.
.DESCRIPTION
    Comprueba kubectl, que el contexto responda, y verifica/muestra el estado de
    nodos, Pods, Services, HPA y consumo. Valida que existan exactamente 2 nodos
    Ready, que los Deployments classifier y app2 estén disponibles, que el HPA
    classifier exista, y hace GET /health cuando hay EXTERNAL-IP válida.
    No genera carga, no usa watch y devuelve un exit code distinto de cero si una
    prueba crítica falla.
.EXAMPLE
    ./infra/verify-aks.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:hasCriticalFailure = $false

function Mark-CriticalFailure {
    param([string]$Message)
    $script:hasCriticalFailure = $true
    Write-Host "ERROR: $Message" -ForegroundColor Red
}

function Assert-LastExitCode {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: '$Step' falló (código de salida $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
}

# 1) kubectl disponible
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host 'ERROR: no se encontró "kubectl".' -ForegroundColor Red
    exit 1
}

# 2) El contexto Kubernetes responde
& kubectl cluster-info --request-timeout=15s | Out-Null
Assert-LastExitCode 'kubectl cluster-info'

# 3) Verificación / visualización de estado
Write-Host ''
Write-Host '== NODOS =='
& kubectl get nodes
Assert-LastExitCode 'kubectl get nodes'

Write-Host ''
Write-Host '== PODS =='
& kubectl get pods -o wide
Assert-LastExitCode 'kubectl get pods -o wide'

Write-Host ''
Write-Host '== SERVICES =='
& kubectl get services
Assert-LastExitCode 'kubectl get services'

Write-Host ''
Write-Host '== HPA =='
& kubectl get hpa
Assert-LastExitCode 'kubectl get hpa'

Write-Host ''
Write-Host '== TOP NODES =='
& kubectl top nodes
if ($LASTEXITCODE -ne 0) {
    Write-Host 'AVISO: kubectl top nodes no disponible (métricas).' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '== TOP PODS =='
& kubectl top pods
if ($LASTEXITCODE -ne 0) {
    Write-Host 'AVISO: kubectl top pods no disponible (métricas).' -ForegroundColor Yellow
}

# 4) Exactamente 2 nodos y ambos Ready
$nodesJson = & kubectl get nodes -o json
Assert-LastExitCode 'kubectl get nodes -o json'
$nodes = @(($nodesJson | ConvertFrom-Json).items)
if ($nodes.Count -ne 2) {
    Mark-CriticalFailure "Se esperaban exactamente 2 nodos y se encontraron $($nodes.Count)."
} else {
    $allReady = $true
    foreach ($node in $nodes) {
        $ready = $node.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }
        if (-not $ready) {
            $allReady = $false
            Write-Host "ERROR: el nodo $($node.metadata.name) no está Ready." -ForegroundColor Red
        }
    }
    if (-not $allReady) {
        Mark-CriticalFailure 'Hay nodos que no están Ready.'
    } else {
        Write-Host 'OK: existen exactamente 2 nodos y ambos están Ready.' -ForegroundColor Green
    }
}

# 5) Deployments classifier y app2 disponibles
foreach ($name in @('classifier', 'app2')) {
    $depJson = & kubectl get deployment $name -o json
    if ($LASTEXITCODE -ne 0) {
        Mark-CriticalFailure "No se pudo consultar el Deployment '$name'."
        continue
    }
    $dep = $depJson | ConvertFrom-Json
    $available = $dep.status.conditions | Where-Object { $_.type -eq 'Available' -and $_.status -eq 'True' }
    if ($available) {
        Write-Host "OK: Deployment '$name' está disponible." -ForegroundColor Green
    } else {
        Mark-CriticalFailure "El Deployment '$name' no está disponible."
    }
}

# 6) El HPA classifier existe
$hpaRaw = & kubectl get hpa classifier -o name
if ($LASTEXITCODE -ne 0) {
    Mark-CriticalFailure "No se encontró el HPA 'classifier'."
} else {
    Write-Host "OK: existe el HPA 'classifier' ($hpaRaw)." -ForegroundColor Green
}

# 7) EXTERNAL-IP actual y /health (solo si hay IP válida; sin hardcodear IPs)
function Get-ExternalIp {
    param([string]$ServiceName)
    $ip = & kubectl get service $ServiceName -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
    if ($LASTEXITCODE -ne 0) {
        return ''
    }
    return ([string]$ip).Trim()
}

function Test-HealthEndpoint {
    param([string]$ServiceName, [string]$ExternalIp)
    $uri = "http://${ExternalIp}/health"
    Write-Host "GET $uri"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 15
        Write-Host "OK: $ServiceName /health respondió ($($response | ConvertTo-Json -Compress))." -ForegroundColor Green
    }
    catch {
        Mark-CriticalFailure "GET /health de '$ServiceName' falló: $($_.Exception.Message)"
    }
}

foreach ($name in @('classifier', 'app2')) {
    $externalIp = Get-ExternalIp $name
    if ($externalIp) {
        Write-Host "EXTERNAL-IP de '$name': $externalIp"
        Test-HealthEndpoint -ServiceName $name -ExternalIp $externalIp
    } else {
        Write-Host "EXTERNAL-IP de '$name': <pending>" -ForegroundColor Yellow
        Mark-CriticalFailure "El Service '$name' aún no tiene EXTERNAL-IP asignada (<pending>)."
    }
}

if ($script:hasCriticalFailure) {
    Write-Host 'Validación AKS con fallos críticos.' -ForegroundColor Red
    exit 1
}

Write-Host 'OK: validación del clúster completada sin fallos críticos.' -ForegroundColor Green
exit 0