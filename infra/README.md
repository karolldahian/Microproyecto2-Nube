# Infraestructura en Azure

Documentación de la infraestructura del clúster **AKS** utilizado en el Microproyecto 2 de Computación en la Nube.

Este documento describe la configuración **real y verificada** del clúster
`aks-microproyecto2`, creado mediante **Azure Portal**, e incluye una guía
reproducible de **creación, destrucción y reconstrucción** para poder recrearlo
antes de la sustentación.

El clúster original fue creado mediante **Azure Portal** (no con Terraform ni con
`az aks create`), y así debe conservarse en la documentación.

---

## Configuración confirmada del clúster

Configuración observada y verificada del clúster original:

| Componente                | Valor                                                       |
| ------------------------- | ----------------------------------------------------------- |
| Suscripción               | Azure for Students                                          |
| Resource Group principal  | `rg-microproyecto2-nube`                                    |
| Servicio                  | Azure Kubernetes Service (AKS)                              |
| Clúster AKS               | `aks-microproyecto2`                                        |
| Región                    | Chile Central (`chilecentral`)                              |
| Versión de Kubernetes     | v1.35.7 (**versión observada**, ver nota de versiones)      |
| DNS prefix                | `aks-microproyecto2-dns`                                    |
| Origen de creación        | Azure Portal                                                |
| SKU del plano de control  | Base                                                        |
| Tier del plano de control | Free                                                        |
| Identidad del clúster     | SystemAssigned (identidad administrada asignada por sistema)|
| RBAC de Kubernetes        | Habilitado (configuración original del Portal)              |

### Resource group administrado por AKS (node resource group)

Al crear el clúster, Azure generó automáticamente un resource group de nodos:

```
MC_rg-microproyecto2-nube_aks-microproyecto2_chilecentral
```

Este resource group es **administrado y generado por AKS**: contiene la infraestructura
de los nodos y servicios administrados (VMSS, balanceadores, etc.). **No debe
tratarse como el resource group principal creado manualmente** y no se administra
directamente: su gestión la realiza el servicio AKS.

### Node pool

| Parámetro            | Valor                |
| -------------------- | -------------------- |
| Nombre               | `agentpool`          |
| Modo                 | System               |
| Sistema operativo    | Linux                |
| Conteo de nodos      | 2                    |
| VM size              | `Standard_DS2_v2`    |
| Availability zones   | 1, 2, 3              |
| `enableAutoScaling`  | `false`              |

> `enableAutoScaling: false` significa que el node pool **no tiene autoscaling de
> nodos**: el conteo de nodos es fijo (2). Esto **no** debe confundirse con el HPA
> del `classifier`, que sí escala **Pods** (ver sección de monitoreo).

### Red

| Parámetro            | Valor              |
| -------------------- | ------------------ |
| `networkPlugin`      | azure              |
| `networkPluginMode`  | overlay            |
| `networkPolicy`      | none               |
| `loadBalancerSku`    | Standard           |
| `outboundType`       | loadBalancer       |

### Acceso y seguridad

| Parámetro              | Valor    |
| ---------------------- | -------- |
| `privateCluster`       | `false`  |
| `disableLocalAccounts` | `false`  |

> **`disableLocalAccounts: false` significa que las cuentas locales están
> permitidas** (los admin accounts del clúster, como el admin creado por el RBAC
> local de AKS, están habilitadas). No invertir esta interpretación.

- **OIDC issuer:** habilitado (habilitado en la configuración del Portal).
- **Workload Identity:** habilitado.
- **RBAC de Kubernetes:** habilitado según la configuración original del Portal.
- **Identidad administrada:** asignada por el sistema (SystemAssigned).

### Monitoreo

- **Container Logs / Container Insights quedó deshabilitado** debido a una
  **restricción regional de la política de la suscripción**: Azure intentó crear
  recursos de monitoreo en regiones no permitidas y la validación falló por esa
  limitación.
- **No debe presentarse como un fallo del AKS ni de la configuración del
  clúster.**
- El proyecto usa como evidencia documentada en
  [docs/monitoring.md](../docs/monitoring.md): `kubectl top nodes`, `kubectl top
  pods`, eventos/HPA y **Azure Portal Metrics**.
- **Azure Portal Metrics no sustituye a Container Insights.**

### Cuota (contexto de la suscripción)

- `Standard_DS2_v2` consume **2 vCPU por nodo**.
- 2 nodos = **4 vCPU**.
- La cuota DSv2 disponible observada durante la implementación fue **4 vCPU**.
- Esta cuota **no es universal ni permanente**: corresponde a la suscripción
  durante la implementación y debe re-verificarse antes de recrear el clúster.

---

## 1. Prerrequisitos

Antes de recrear el clúster se necesita:

| Prerrequisito         | Detalle                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| Azure CLI             | Instalado y disponible (para las verificaciones desde terminal local).  |
| `kubectl`             | Instalado y disponible (cliente de Kubernetes).                         |
| Sesión autenticada    | `az login` completado (o Cloud Shell ya autenticado).                   |
| Suscripción correcta  | Asegurarse de que la CLI opera sobre la suscripción correcta.           |
| Proveedores registrados | `Microsoft.Compute` y `Microsoft.ContainerService` (verificados durante la implementación; ver nota). |
| Acceso al repositorio GitHub | Para disponer de los manifiestos de `k8s/classifier/` y `k8s/app2/`. |

> **Nota sobre proveedores:** los proveedores **verificados explícitamente**
> durante la implementación fueron **`Microsoft.Compute`** y
> **`Microsoft.ContainerService`**. Si Azure registra otros proveedores
> automáticamente para alguna función, **no** se presentan aquí como requisito
> confirmado por falta de evidencia.

---

## 2. Verificación previa

Antes de crear el clúster conviene comprobar tres cosas distintas:

| Comprobación                                   | Qué valida                                                                 |
| ---------------------------------------------- | -------------------------------------------------------------------------- |
| **Región permitida**                          | Que la suscripción permita crear recursos en la región elegida (Chile Central). |
| **Cuota suficiente**                          | Que la suscripción tenga cuota de vCPU disponible para 2 × `Standard_DS2_v2` (4 vCPU). |
| **Disponibilidad/compatibilidad del SKU**     | Que `Standard_DS2_v2` esté disponible en la región y sea compatible con AKS. |

**Disponibilidad del SKU, cuota y compatibilidad con AKS son comprobaciones
diferentes:**

- Un SKU puede estar disponible en catálogo en una región y, aun así, la
  suscripción puede no tener cuota suficiente para solicitar el número de vCPU
  deseado.
- Un SKU puede estar disponible en la región y no ser compatible con el tipo de
  nodo que AKS requiere.
- La cuota observada (4 vCPU DSv2) corresponde a la suscripción durante la
  implementación; debe re-verificarse antes de cada recreación.

### Nota sobre la versión de Kubernetes

- **v1.35.7 es la versión observada** del clúster original.
- **No se afirma que v1.35.7 estará necesariamente disponible** al recrear el
  clúster.
- Antes de recrear, **verificar las versiones soportadas actualmente en Chile
  Central** (p. ej. en el Portal, en el selector de versión de Kubernetes) y usar
  **una versión soportada adecuada** si v1.35.7 ya no estuviera disponible.

---

## 3. Creación mediante Azure Portal

El clúster se crea con los parámetros exactos que reproducen el clúster original.
Estos son los valores que deben seleccionarse (no se inventan opciones no dadas).

### Pestaña Básicos

| Campo                      | Valor                                   |
| -------------------------- | --------------------------------------- |
| Suscripción                | La suscripción del proyecto.            |
| Resource group             | `rg-microproyecto2-nube` (el principal) |
| Nombre del clúster         | `aks-microproyecto2`                    |
| Región                     | Chile Central                           |
| Versión de Kubernetes      | v1.35.7 (si está disponible; en caso contrario, una versión soportada — ver nota). |
| DNS prefix                 | `aks-microproyecto2-dns`                |
| Node resource group        | `MC_rg-microproyecto2-nube_aks-microproyecto2_chilecentral` (generado por Azure) |

### Pestaña Node pool

| Campo                  | Valor                |
| ---------------------- | -------------------- |
| Nombre del node pool   | `agentpool`          |
| Modo                   | System               |
| Sistema operativo      | Linux                |
| Tamaño del nodo        | `Standard_DS2_v2`    |
| Conteo de nodos        | 2                    |
| Availability zones     | 1, 2, 3              |
| Escalado automático del nodo | Deshabilitado (`enableAutoScaling: false`) |

### Pestaña Red

| Campo                        | Valor              |
| ---------------------------- | ------------------ |
| Network plugin               | azure              |
| Network plugin mode          | overlay            |
| Network policy               | none               |
| Load balancer SKU            | Standard           |
| Outbound flow (outboundType) | loadBalancer       |

### Pestaña Acceso / Seguridad

| Campo                    | Valor       |
| ------------------------ | ----------- |
| Clúster privado         | No (`privateCluster: false`) |
| Cuentas locales         | Habilitadas (`disableLocalAccounts: false`) |
| OIDC issuer             | Habilitado  |
| Workload Identity       | Habilitado  |
| RBAC de Kubernetes      | Habilitado  |
| Identidad administrada  | Asignada por el sistema (SystemAssigned) |

### Pestaña Monitoreo

- Al momento de la creación original se intentó habilitar **Container Logs /
  Container Insights**, pero quedó **deshabilitado** por la restricción regional
  de la política de la suscripción. No es un fallo del AKS.

---

## 4. Verificación desde Cloud Shell

Con el clúster creado, desde **Azure Cloud Shell** se recuperan las credenciales
y se verifica que los 2 nodos estén `Ready`:

```bash
az aks get-credentials --resource-group rg-microproyecto2-nube --name aks-microproyecto2

kubectl get nodes
```

Deben observarse **2 nodos en estado `Ready`** (del node pool `agentpool`).

---

## 5. Verificación desde terminal local

Desde una terminal local con Azure CLI y `kubectl`, se usa el indicador
`--overwrite-existing` para que las credenciales existentes del clúster se
actualicen:

```powershell
az aks get-credentials `
  --resource-group rg-microproyecto2-nube `
  --name aks-microproyecto2 `
  --overwrite-existing

kubectl get nodes
```

Deben observarse **los mismos 2 nodos en estado `Ready`**.

---

## 6. Despliegue de workloads

Desde la **raíz del repositorio**, se aplican los manifiestos versionados en el
repositorio. No se modifican los manifiestos existentes:

```bash
kubectl apply -f k8s/classifier/
kubectl apply -f k8s/app2/
```

### Imágenes (GHCR públicas)

Los workloads usan imágenes públicas publicadas en GHCR:

| Aplicación | Imagen                                                          |
| ---------- | --------------------------------------------------------------- |
| classifier | `ghcr.io/karolldahian/microproyecto2-classifier:v1`             |
| app2       | `ghcr.io/karolldahian/microproyecto2-app2:v1`                   |

Ambos paquetes se configuraron como **públicos**:

- **No se necesita `imagePullSecret`** mientras las imágenes permanezcan públicas.
- El pull anónimo desde GHCR ya fue validado durante la implementación.
- **No se incluyen** PAT, tokens ni credenciales en este documento ni en los
  manifiestos.

---

## 7. Espera / verificación del despliegue

Una vez aplicados los manifiestos, se espera y verifica el rollout de cada
Deployment:

```bash
kubectl rollout status deployment/classifier --timeout=180s
kubectl rollout status deployment/app2 --timeout=180s
```

Después, estado general de Pods, Services y HPA:

```bash
kubectl get pods -o wide
kubectl get services
kubectl get hpa
```

Notas esperadas:

- 1 Pod `Running` para `classifier` y 1 Pod `Running` para `app2` (el HPA del
  `classifier` podrá ajustar su número de réplicas entre 1 y 3 según la carga).
- Los Services `classifier` y `app2` son de tipo `LoadBalancer`: la
  `EXTERNAL-IP` puede tardar unos minutos en asignarse.

---

## 8. Validación funcional

Las IP públicas de los Services se obtienen **dinámicamente en el momento** con
`kubectl`; **no se fijan aquí IPs públicas históricas**, porque Azure las asigna
dinámicamente y **pueden ser diferentes después de recrear el clúster**.

```bash
kubectl get services
```

Con la `EXTERNAL-IP` de cada Service:

- **classifier**
  - `GET /health` → debe responder `200` con `{"status": "ok"}`.
  - `POST /predict` → requiere una **imagen válida** enviada vía
    `multipart/form-data` en el campo `file` (no es un endpoint de prueba vacío;
    necesita una imagen real para clasificar).

```bash
curl http://<EXTERNAL-IP-classifier>/health
curl -X POST -F "file=@imagen.jpg" http://<EXTERNAL-IP-classifier>/predict
```

- **app2**
  - `GET /health` → debe responder `200` con `{"status": "ok"}`.
  - `GET /` → responde correctamente.
  - `GET /info` → hostname, plataforma, versión de Python y timestamp UTC.

```bash
curl http://<EXTERNAL-IP-app2>/health
curl http://<EXTERNAL-IP-app2>/
curl http://<EXTERNAL-IP-app2>/info
```

> Sustituir `<EXTERNAL-IP-classifier>` y `<EXTERNAL-IP-app2>` por los valores que
> devuelve `kubectl get services` en el momento de la validación.

Recordatorio sobre las IPs:

- Los nodos **no tienen** `EXTERNAL-IP`: su acceso se realiza a través de los
  Services `LoadBalancer`.
- Después de recrear el AKS, las `EXTERNAL-IP` de los Services **pueden ser
  diferentes** a las anteriores. Verificarlas siempre en el momento de la
  demostración.

---

## 9. Monitoreo

La supervisión se realiza con las herramientas que ya usa el proyecto, tal como
se documenta en [docs/monitoring.md](../docs/monitoring.md):

```bash
kubectl top nodes
kubectl top pods
kubectl get hpa
kubectl describe hpa classifier
```

Verificaciones esperadas:

- **`kubectl top nodes`**: consumo real de CPU y memoria de los 2 nodos.
- **`kubectl top pods`**: consumo real por Pod (`app2` ≈ 2m / 34 Mi y
  `classifier` ≈ 2m / 334 Mi en reposo, en el clúster original).
- **`kubectl get hpa`** y **`kubectl describe hpa classifier`**: réplicas
  actuales, objetivo (60 % de CPU sobre el request de 100m) y eventos del HPA.

### Diferencia entre autoscaling de nodos y HPA

| Concepto                  | Configuración                      | Qué escala            |
| ------------------------- | ---------------------------------- | --------------------- |
| Node pool `agentpool`     | `enableAutoScaling: false`         | **No** escala nodos (fijo en 2). |
| HPA `classifier`          | `minReplicas: 1`, `maxReplicas: 3` | Escala **Pods** según CPU (1‑3). |

- El node pool sin autoscaling **no** es lo mismo que el HPA: el primero
  correspondería a escalar máquinas del clúster; el HPA del `classifier` escala
  **réplicas del Pod** según la utilización de CPU respecto al request de 100m.
- No confundir ambos conceptos.

### Limitación de Container Insights

- **Container Logs / Container Insights quedó deshabilitado** por la restricción
  regional de la política de la suscripción (no por fallo del AKS).
- **Azure Portal Metrics no sustituye a Container Insights.**
- La evidencia documentada se obtiene con `kubectl top`, estado de Pods/nodos,
  eventos del HPA y la validación visual de Azure Portal Metrics en
  `docs/monitoring.md`.

---

## 10. Destrucción del AKS

> **ADVERTENCIA:** este comando elimina el clúster AKS. **Ejecutarlo únicamente
> cuando la reconstrucción previa a la sustentación esté planificada y el
> clúster sea recreable.** El comando NO se ejecuta como parte de este
> documento: se documenta para uso deliberado.

```powershell
az aks delete `
  --resource-group rg-microproyecto2-nube `
  --name aks-microproyecto2
```

**Notas sobre la destrucción:**

- **Azure solicitará confirmación** si no se utiliza `--yes`. El comando
  principal incluye **sin `--yes`** a propósito, para **reducir el riesgo de
  eliminación accidental** (se requiere confirmación manual).
- El comando apunta al **recurso AKS** (`--name aks-microproyecto2`) dentro del
  resource group `rg-microproyecto2-nube`; **NO** elimina el resource group
  principal completo.

**Qué se elimina:**

- `az aks delete --resource-group rg-microproyecto2-nube --name aks-microproyecto2`
  elimina el **recurso/clúster AKS** (`aks-microproyecto2`).
- Los recursos de infraestructura asociados al clúster (plano de control, nodos,
  balanceadores y demás) son administrados por AKS en el **node resource group**
  `MC_rg-microproyecto2-nube_aks-microproyecto2_chilecentral`, generado y
  gestionado por el servicio.
- Tras la eliminación, se debe **verificar en Azure Portal qué recursos
  asociados permanecen** antes de considerar terminada la limpieza: la
  eliminación automática de ese resource group administrado no se presenta aquí
  como garantizada.

**Qué NO se elimina:**

- El **resource group principal** `rg-microproyecto2-nube` (si se usa la
  eliminación específica del AKS, este resource group se conserva).
- **Git / GitHub**: el repositorio y su historial no se ven afectados.
- **Docker / GHCR**: las imágenes
  `ghcr.io/karolldahian/microproyecto2-classifier:v1` y
  `ghcr.io/karolldahian/microproyecto2-app2:v1` permanecen publicadas.
- **Los manifiestos locales/versionados** en `k8s/classifier/` y `k8s/app2/` y
  toda la documentación del repositorio.

---

## 11. Reconstrucción

Procedimiento reproducible para recrear el clúster después de la destrucción:

1. **Verificar prerrequisitos** (sección 1) y **verificación previa** (sección 2):
   región permitida, cuota para 2 × `Standard_DS2_v2` (4 vCPU) y versión de
   Kubernetes soportada en Chile Central.
2. **Crear el clúster** mediante Azure Portal con los parámetros de la
   **sección 3**.
3. **Recuperar credenciales** desde Cloud Shell o terminal local (secciones 4 y 5):
   `az aks get-credentials ...` y `az aks get-credentials ... --overwrite-existing`.
4. **Verificar 2 nodos `Ready`**: `kubectl get nodes`.
5. **Aplicar manifiestos** desde la raíz del repositorio (sección 6):
   `kubectl apply -f k8s/classifier/` y `kubectl apply -f k8s/app2/`.
6. **Esperar el rollout** (sección 7):
   `kubectl rollout status deployment/classifier --timeout=180s` y
   `kubectl rollout status deployment/app2 --timeout=180s`.
7. **Esperar la `EXTERNAL-IP`** de los Services LoadBalancer (puede tardar varios
   minutos): `kubectl get services`.
8. **Validar las aplicaciones** (sección 8) con las nuevas IPs: `/health`,
   `/`, `/info` y `/predict` (con imagen válida).
9. **Validar el HPA y el monitoreo** (sección 9): `kubectl get hpa`,
   `kubectl describe hpa classifier`, `kubectl top nodes` y `kubectl top pods`.

---

## 12. Checklist previo a la sustentación

| Ítem | Verificación |
| ---- | ------------ |
| Suscripción correcta | La CLI/Portal operan sobre la suscripción del proyecto. |
| Región | Chile Central. |
| Versión de Kubernetes | Usar la **versión soportada** en Chile Central (v1.35.7 fue la versión observada del clúster original; re-verificar su disponibilidad). |
| Clúster | `aks-microproyecto2` creado mediante **Azure Portal** (hecho conservado en la documentación). |
| Resource group | `rg-microproyecto2-nube`; el node resource group `MC_...` es administrado por AKS. |
| Node pool | `agentpool`, 2 nodos `Standard_DS2_v2`, `enableAutoScaling: false` (sin autoscaling de nodos). |
| Nodos | `kubectl get nodes` → 2 nodos `Ready`. |
| Credenciales | `az aks get-credentials ... --overwrite-existing` funcionando. |
| Manifiestos aplicados | `classifier` (Deployment, Service, HPA) y `app2` (Deployment, Service) desde `k8s/`. |
| Rollout | `kubectl rollout status deployment/classifier` y `deployment/app2` completos. |
| Services | `kubectl get services` → `EXTERNAL-IP` asignada a `classifier` y `app2`. |
| Validación funcional | `/health` (ambos), `/` e `/info` (app2), `/predict` (classifier con imagen válida). |
| HPA | `kubectl get hpa` → `classifier` con `min=1`, `max=3`, objetivo 60 % CPU; **es autoscaling de Pods, no de nodos**. |
| Monitoreo | `kubectl top nodes`, `kubectl top pods`, eventos/HPA y Azure Portal Metrics (ver `docs/monitoring.md`). |
| Seguridad | `disableLocalAccounts: false` (cuentas locales permitidas), identidad SystemAssigned, RBAC habilitado, OIDC/Workload Identity habilitados. |
| Imágenes | GHCR públicas (`...:v1`); sin `imagePullSecret` mientras permanezcan públicas; sin credenciales en el repositorio. |
| Container Insights | Deshabilitado por restricción regional de la suscripción (no es fallo del AKS); Azure Portal Metrics no lo sustituye. |
| IPs públicas | Verificadas en el momento con `kubectl get services` (son dinámicas y pueden cambiar tras recrear el clúster). |

---

## Notas finales

- El clúster original fue creado mediante **Azure Portal**; la guía de la
  sección 3 conserva ese hecho.
- La **versión de Kubernetes v1.35.7 es la observada** en el clúster original;
  no se presenta como garantía de disponibilidad en futuras recreaciones.
- El node pool `agentpool` tiene `enableAutoScaling: false` (sin autoscaling de
  nodos); el **HPA del `classifier`** escala **Pods** entre 1 y 3. Son dos
  conceptos distintos.
- `disableLocalAccounts: false` = **cuentas locales permitidas**.
- Container Insights quedó deshabilitado por **restricción regional de la
  política de la suscripción**, no por fallo del AKS; **Azure Portal Metrics no
  sustituye a Container Insights**.
- Los recursos de monitoreo y las IP públicas **no son valores permanentes**:
  deben verificarse en el momento de la demostración.
- **No se versionan** kubeconfig, tokens, credenciales, identificadores de
  suscripción/tenant ni secretos en este repositorio.