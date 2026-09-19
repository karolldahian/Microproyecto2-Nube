<#
.SYNOPSIS
    Conecta kubectl al clúster AKS aks-microproyecto2 (Resource Group rg-microproyecto2-nube).
.DESCRIPTION
    Verifica prerequisitos (az, kubectl y sesión de Azure CLI válida), recupera
    las credenciales del clúster con 'az aks get-credentials' y comprueba que
    kubectl responde consultando los nodos. No realiza login automático, no
    almacena credenciales en el repositorio y no crea ni elimina recursos.
.EXAMPLE
    ./infra/connect-aks.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resourceGroup = 'rg-microproyecto2-nube'
$clusterName = 'aks-microproyecto2'

function Assert-LastExitCode {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: '$Step' falló (código de salida $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
}

# 1) Azure CLI disponible
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host 'ERROR: no se encontró "az" (Azure CLI). Instálala y añádela al PATH.' -ForegroundColor Red
    exit 1
}

# 2) kubectl disponible
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host 'ERROR: no se encontró "kubectl".' -ForegroundColor Red
    exit 1
}

# 3) Sesión válida de Azure CLI. NO se realiza login automático.
& az account show | Out-Null
Assert-LastExitCode 'az account show'

Write-Host "Recuperando credenciales del clúster '$clusterName'..."
& az aks get-credentials `
    --resource-group $resourceGroup `
    --name $clusterName `
    --overwrite-existing
Assert-LastExitCode 'az aks get-credentials'

Write-Host 'Verificando nodos del clúster...'
& kubectl get nodes
Assert-LastExitCode 'kubectl get nodes'

Write-Host 'OK: kubectl conectado al clúster.' -ForegroundColor Green
exit 0