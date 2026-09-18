# Infraestructura en Azure

Documentación de la infraestructura del clúster **AKS** utilizado en el Microproyecto 2 de Computación en la Nube.

## Estado confirmado

| Componente            | Valor                                  |
| --------------------- | -------------------------------------- |
| Suscripción           | Azure for Students                     |
| Resource Group        | `rg-microproyecto2-nube`               |
| Servicio              | Azure Kubernetes Service (AKS)         |
| Clúster AKS           | `aks-microproyecto2`                   |
| Región                | Chile Central                          |
| Versión de Kubernetes | v1.35.7                                |
| Node pool             | `agentpool`                            |
| Nodos                 | 2 nodos Linux `Standard_DS2_v2`        |

## Verificación

Los 2 nodos del node pool `agentpool` fueron verificados en estado **Ready** desde:

- Azure Cloud Shell
- Azure CLI / kubectl local

## Notas

- La suscripción es de tipo **Azure for Students**.
- No se versiona en el repositorio ningún kubeconfig, token, credencial o identificador de suscripción/tenant.