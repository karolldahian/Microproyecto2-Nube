<#
.SYNOPSIS
    Despliega los manifiestos de k8s/classifier y k8s/app2 en AKS.
.DESCRIPTION
    Asume que connect-aks.ps1 ya fue ejecutado. Comprueba que kubectl esté
    disponible, que el contexto Kubernetes responda antes de aplicar, localiza
    la raíz del repositorio a partir de $PSScriptRoot, aplica los manifiestos
    versionados y espera de forma finita el rollout de ambos Deployments.
    No modifica manifiestos, no usa watch y muestra el estado final.
.EXAMPLE
    ./infra/deploy-apps.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

# 2) El contexto Kubernetes responde antes de aplicar manifiestos
& kubectl cluster-info --request-timeout=15s | Out-Null
Assert-LastExitCode 'kubectl cluster-info'

# 3) Raíz del repositorio a partir de $PSScriptRoot, sin depender del directorio actual
$repoRoot = $PSScriptRoot
for ($i = 0; $i -lt 6; $i++) {
    if ((Test-Path (Join-Path $repoRoot 'k8s\classifier')) -and (Test-Path (Join-Path $repoRoot 'k8s\app2'))) {
        break
    }
    $parent = Split-Path -Parent $repoRoot
    if (-not $parent) { break }
    $repoRoot = $parent
}
$classifierDir = Join-Path $repoRoot 'k8s\classifier'
$app2Dir = Join-Path $repoRoot 'k8s\app2'
if (-not (Test-Path $classifierDir) -or -not (Test-Path $app2Dir)) {
    Write-Host 'ERROR: no se localizó la raíz del repositorio desde el script.' -ForegroundColor Red
    exit 1
}
Write-Host "Raíz del repositorio: $repoRoot"

# 4) Aplicar los manifiestos versionados (sin modificar su contenido)
Write-Host 'Aplicando k8s/classifier ...'
& kubectl apply -f $classifierDir
Assert-LastExitCode 'kubectl apply -f k8s/classifier'

Write-Host 'Aplicando k8s/app2 ...'
& kubectl apply -f $app2Dir
Assert-LastExitCode 'kubectl apply -f k8s/app2'

# 5) Esperar de forma FINITA el rollout de ambos Deployments
Write-Host 'Esperando rollout de deployment/classifier (máx. 180s)...'
& kubectl rollout status deployment/classifier --timeout=180s
Assert-LastExitCode 'kubectl rollout status deployment/classifier'

Write-Host 'Esperando rollout de deployment/app2 (máx. 180s)...'
& kubectl rollout status deployment/app2 --timeout=180s
Assert-LastExitCode 'kubectl rollout status deployment/app2'

# 6) Estado final
Write-Host ''
& kubectl get pods -o wide
Assert-LastExitCode 'kubectl get pods -o wide'
& kubectl get services
Assert-LastExitCode 'kubectl get services'
& kubectl get hpa
Assert-LastExitCode 'kubectl get hpa'

Write-Host 'OK: despliegue completado.' -ForegroundColor Green
exit 0