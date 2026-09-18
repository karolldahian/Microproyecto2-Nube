# Microproyecto 2 — Computación en la Nube

Microproyecto académico de la asignatura **Computación en la Nube**. El objetivo es desplegar aplicaciones contenerizadas sobre un clúster **Azure Kubernetes Service (AKS)**.

## Objetivo académico

Aplicar conceptos de contenerización y orquestación de contenedores, aprovisionando y administrando un clúster de Kubernetes en Azure, desplegando en él aplicaciones en contenedores y verificando su funcionamiento desde la nube y desde un entorno local.

## Arquitectura inicial

```
Azure (Suscripción Azure for Students)
│
└── Resource Group: rg-microproyecto2-nube
    │
    └── AKS: aks-microproyecto2
        │
        └── Node pool: agentpool
            │
            ├── Nodo 1 (Linux, Standard_DS2_v2)
            └── Nodo 2 (Linux, Standard_DS2_v2)

Workloads administrados por Kubernetes (se programan en los nodos del clúster)
│
├── Aplicación "classifier"
└── Aplicación "app2"
```

El clúster ya se encuentra creado en la región **Chile Central** (Kubernetes v1.35.7) y sus 2 nodos fueron verificados en estado `Ready`. Los detalles de la infraestructura confirmada están documentados en [infra/README.md](infra/README.md).

## Estructura del repositorio

```
├── infra/         Documentación de la infraestructura en Azure
├── classifier/    Aplicación "classifier" (por implementar)
├── app2/          Aplicación "app2" (por implementar)
├── k8s/           Manifiestos de Kubernetes (por crear)
├── docs/          Documentación del proyecto (por crear)
├── README.md
└── .gitignore
```

## Nota

Este repositorio no incluye ni debe incluir credenciales, tokens, kubeconfig ni secretos de ningún tipo.