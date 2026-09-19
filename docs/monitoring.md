# Monitoreo y supervisión del clúster AKS

Documento de evidencia del monitoreo/supervisión realizado sobre el clúster
**Azure Kubernetes Service (AKS)** del Microproyecto 2 de Computación en la Nube.
Todas las mediciones corresponden a observaciones **reales** obtenidas con las
herramientas indicadas, sobre el clúster desplegado en Azure. No se reportan
valores simulados ni extrapolaciones.

## 1. Objetivo del monitoreo

Verificar, sobre los recursos reales del clúster, que:

- Los nodos del AKS están sanos y disponibles (`Ready`).
- Se observa el consumo de recursos de las aplicaciones `app2` y `classifier` y,
  en el caso del `classifier`, su relación con sus requests y limits.
- El `HorizontalPodAutoscaler` (HPA) del `classifier` reacciona a la carga real
  de CPU escalando réplicas y las reduce cuando la carga termina.
- Queda registrado el consumo en reposo (línea base) y el comportamiento
  observado bajo una prueba de carga concreta.

## 2. Herramientas utilizadas

| Herramienta                          | Uso en la supervisión                                       |
| ------------------------------------ | ----------------------------------------------------------- |
| `kubectl top nodes`                  | Consumo real de CPU y memoria por nodo.                     |
| `kubectl top pods`                   | Consumo real de CPU y memoria por Pod.                      |
| `kubectl get nodes -o wide`          | Estado, versión de Kubernetes y sistema operativo de nodos. |
| `kubectl get pods -o wide`           | Estado de los Pods y nodo en el que se programan.           |
| `kubectl get hpa` / `describe hpa`   | Métrica objetivo, réplicas y eventos del autoscaling.       |
| `kubectl get services`               | Tipo y exposición de los Services.                          |
| `kubectl get events`                 | Eventos del clúster (por ejemplo, del HPA).                 |
| Azure Portal Metrics                 | Métricas visuales e históricas del clúster expuestas por AKS.   |

**Azure Portal Metrics** se validó en la vista **Azure Portal -> AKS ->
Monitoring -> Metrics**; la evidencia queda documentada en la subsección
[*Validación con Azure Portal Metrics*](#validación-con-azure-portal-metrics).

### Validación con Azure Portal Metrics

Además de `kubectl`, la supervisión se validó visual e históricamente en Azure
Portal. Ambas fuentes son **complementarias**:

- **`kubectl top nodes` / `kubectl top pods`:** observación **puntual** del
  consumo **actual** de CPU y memoria de los nodos y los workloads.
- **Azure Portal Metrics:** métricas **visuales e históricas** del clúster
  **expuestas por AKS** (Metric Namespace `Container service (managed
  clusters)`). **No sustituyen a Container Insights.**

Parámetros comunes de la validación:

- **Recurso:** `aks-microproyecto2`.
- **Ruta:** Azure Portal -> AKS (`aks-microproyecto2`) -> Monitoring -> Metrics.
- **Metric Namespace:** `Container service (managed clusters)`.

**API Server CPU Usage Percentage**

- Aggregation: **Avg**.
- La gráfica mostró datos de la métrica.
- En el momento de la captura, la leyenda mostraba aproximadamente **5.4055 %**.
- Esta métrica corresponde al **API Server (plano de control del clúster)** y
  **no** al CPU de los Pods ni de los nodos trabajadores; su valor no debe
  interpretarse como consumo de las aplicaciones.

**CPU Usage Percentage de NODES (PREVIEW)**

- Aggregation: **Avg**.
- Se aplicó **Apply splitting -> Name of the node**, y Azure mostró
  individualmente los dos nodos:
  - `aks-agentpool-11068937-vmss000000` ≈ **5.8920 %**.
  - `aks-agentpool-11068937-vmss000001` ≈ **5.7108 %**.
- Estos valores son **coherentes** con la medición anterior de `kubectl top
  nodes` (≈ 6 % de CPU por nodo), aunque **no** deben leerse como mediciones
  exactamente simultáneas: Azure Metrics y `kubectl top` pueden usar **ventanas
  o frecuencias de muestreo diferentes**.
- La gráfica contenía valores históricos y picos, pero **no se atribuyen** al
  `classifier`, al HPA ni a ningún evento concreto: no hay evidencia suficiente
  para establecer causalidad sobre el historial.

**Memoria del clúster**

- Métrica: **Total amount of available memory in a managed cluster**.
- Aggregation: **Avg**.
- En el momento observado, la gráfica mostró aproximadamente **10.6 GB**.
- Esta métrica se presentó **agregada a nivel del clúster**; en nuestra
  validación Azure Portal no permitió aplicar splitting por nombre de nodo para
  esta métrica. Por lo tanto, **10.6 GB no debe interpretarse como la memoria de
  un nodo individual**.
- Para la memoria **individual por nodo**, la evidencia sigue siendo `kubectl
  top nodes` (2208 Mi ≈ 43 % y 1682 Mi ≈ 33 % del estado estable).

Estas cifras son **observaciones puntuales** de una captura: no representan un
benchmark ni un valor garantizado de las métricas.

## 3. Línea base del clúster

Clúster **`aks-microproyecto2`**, de **2 nodos** administrados. Ambos nodos en
estado `Ready`.

| Atributo             | Valor                        |
| -------------------- | ---------------------------- |
| Kubernetes           | v1.35.7                      |
| Sistema operativo    | Ubuntu 24.04.4 LTS           |
| Runtime de contenedor| containerd 2.3.3-2           |
| Nodos                | 2, ambos `Ready`             |
| EXTERNAL-IP (nodos)  | No disponible (sin IP externa directa) |

Los nodos del clúster **no tienen `EXTERNAL-IP`**: su acceso público se realiza a
través de los Services de tipo `LoadBalancer`, no mediante las IP de los nodos.

### Estado estable final (`kubectl top nodes`)

| Nodo (VMSS)                        | CPU           | Memoria            |
| ---------------------------------- | ------------- | ------------------ |
| `aks-agentpool-11068937-vmss000000`| 114m (≈ 6 %)  | 2208 Mi (≈ 43 %)   |
| `aks-agentpool-11068937-vmss000001`| 115m (≈ 6 %)  | 1682 Mi (≈ 33 %)   |

### Estado estable final (`kubectl top pods`)

| Pod        | CPU | Memoria |
| ---------- | --- | ------- |
| `app2`     | 2m  | 34 Mi   |
| `classifier` | 2m  | 334 Mi  |

Ambos nodos quedan con holgura de CPU y memoria en reposo, y ninguna aplicación
se aproxima a sus limits en el estado estable.

## 4. Prueba de app2

Para verificar el comportamiento de `app2` bajo solicitudes HTTP, se realizaron
**100 solicitudes secuenciales a `/info`** usando su IP pública (Service de tipo
`LoadBalancer`). No se documentan aquí las IP públicas concretas porque son
**valores asignados dinámicamente y pueden cambiar**.

- Antes de la prueba: ≈ **2m de CPU** y ≈ **34 Mi de RAM**.
- Después de la prueba: ≈ **2m de CPU** y ≈ **34 Mi de RAM**.

Entre el consumo observado antes y después no hubo diferencias apreciables. Esta
prueba fue **demasiado corta y ligera** (100 solicitudes de una API de tipo
System Info) para que el muestreo de `kubectl top` capturara un pico de consumo.
Por eso los valores reportados reflejan reposo, **no** el consumo bajo carga.

Es importante no inferir de esto que `app2` no consume CPU adicional bajo carga:
el resultado simplemente indica que la carga aplicada fue breve y liviana, y que
el muestreo no registró el detalle de esos instantes. No se afirma que `app2`
carezca de consumo adicional bajo solicitudes.

## 5. Prueba de carga del classifier

Para validar el consumo real del clasificador, primero se estableció su **línea
base** (reposo): ≈ **2m de CPU** y ≈ **334 Mi de RAM**.

Luego se ejecutó una **prueba sostenida de 60 segundos** contra el endpoint
`POST /predict` con imágenes, durante la cual:

- Se completaron **2183 inferencias** en esos 60 segundos.
- Durante la carga se observó ≈ **67m de CPU** en una medición de `kubectl top`.
- Durante el proceso de escalamiento, la nueva réplica mostró ≈ **112m de CPU**
  y ≈ **267 Mi de RAM** en una medición puntual.

**Interpretación del alcance de este dato:**

- El valor de **2183 inferencias / 60 s** es únicamente el **resultado observado
  bajo esa prueba concreta** (con la imagen usada, la carga aplicada y el estado
  del clúster en ese momento).
- **No** debe presentarse como throughput máximo, benchmark formal ni capacidad
  garantizada del clasificador.
- Las mediciones de ~67m y ~112m son **muestras puntuales** de `kubectl top`;
  no representan una serie temporal completa del consumo.

## 6. Validación del HPA

El HPA del `classifier` (`autoscaling/v2`) está configurado así:

| Parámetro              | Valor     |
| ---------------------- | --------- |
| `minReplicas`          | 1         |
| `maxReplicas`          | 3         |
| Métrica                | CPU       |
| Objetivo (target)      | 60 %      |
| CPU request del Pod    | 100m      |
| Réplicas (estado final)| 1         |
| Utilización final      | 2 % / 60 %|

**Comportamiento observado durante la prueba de carga:**

1. La utilización de CPU superó el objetivo del 60 %, por lo que el HPA registró
   el evento **`SuccessfulRescale`** (escala exitosa por métrica de CPU).
2. El HPA escaló el Deployment de **1 → 2 Pods**.
3. Temporalmente hubo **un Pod en cada nodo** del clúster (distribuido entre los
   dos nodos).
4. Al terminar la carga, la utilización de CPU volvió aproximadamente al **2 %**,
   por debajo del objetivo.
5. El HPA mostró el evento **`ScaleDownStabilized`**, correspondiente al período
   de estabilización que evita reducir réplicas de forma oscilante.
6. Posteriormente, el HPA redujo automáticamente el Deployment de **2 → 1 Pod**.

**Cómo se calcula el porcentaje del HPA:** el HPA calcula la utilización
**respecto al *CPU request* de cada Pod** (100m), no respecto a la CPU total del
nodo. Por ejemplo, el objetivo del 60 % equivale a ≈ **60m de CPU** por Pod; si
un Pod usara ese 60 % de su request, se considera que alcanzó el objetivo. Por
lo tanto, el HPA depende de que el Deployment defina el request de CPU.

## 7. Requests y limits

El Deployment del `classifier` define los siguientes recursos:

| Tipo     | CPU   | Memoria |
| -------- | ----- | ------- |
| `requests` | 100m | 384 Mi  |
| `limits`   | 500m | 768 Mi  |

**Función de cada uno:**

- **`requests.cpu` (100m):** la CPU que el contenedor solicita. Kubernetes la
  usa para decidir si un nodo tiene capacidad suficiente para programar el Pod,
  y además es la referencia que usa el HPA para calcular la utilización de CPU.
- **`requests.memory` (384Mi):** la memoria que el contenedor solicita;
  Kubernetes la utiliza, junto con el CPU request, para decidir si un nodo tiene
  capacidad suficiente para programar el Pod.
- **`limits.cpu` (500m):** el máximo de CPU que el contenedor puede consumir. Si
  se alcanza, el uso de CPU puede verse ***throttled*** (limitado en tiempo de
  CPU por el kernel), lo que puede ralentizar la respuesta.
- **`limits.memory` (768Mi):** el máximo de memoria. A diferencia de la CPU, la
  memoria es un límite duro: si el contenedor supera el memory limit, el kernel
  puede terminar el contenedor con un **OOMKill** (terminación por falta de
  memoria).

> **Precisión sobre el alcance del documento:** en nuestras pruebas **no se
> provocó ni se midió** throttling ni OOMKill. Solo se documenta que *alcanzar*
> el CPU limit *puede* producir throttling y que *superar* el memory limit
> *puede* provocar OOMKill, como característica del comportamiento de Kubernetes,
> no como resultado observado.

## 8. Limitación de Container Insights

Durante la **creación del AKS** se intentó habilitar **Container Logs /
Container Insights** para la supervisión administrada del clúster. En ese
proceso:

- Azure intentó crear recursos de monitoreo en regiones **no permitidas por la
  política de la suscripción**.
- La validación **falló por esa restricción regional**.
- Por esa razón, **Container Logs / Insights quedó deshabilitado**.

Este resultado **no se presenta como un fallo del AKS ni de la configuración del
clúster**: fue una limitación de la política de la suscripción en cuanto a
regiones de los recursos de monitoreo.

La supervisión efectiva del proyecto se realiza entonces con:

- `kubectl top nodes` y `kubectl top pods` (consumo real).
- Estado de Pods y nodos (`kubectl get nodes/pods -o wide`).
- Eventos del HPA y del clúster (`kubectl get events`).
- Azure Portal Metrics (validado; ver subsección "Validación con Azure Portal
  Metrics").

Todas estas herramientas son suficientes para documentar la evidencia de
monitoreo presentada en este documento.

## 9. Comandos reproducibles

Los siguientes comandos permiten reproducir las verificaciones. **No modifican
recursos**: son de solo lectura y pueden ejecutarse con el kubeconfig apropiado.

```bash
# Estado, versión de Kubernetes, sistema operativo, runtime y roles de los nodos
kubectl get nodes -o wide

# Consumo real de CPU y memoria por nodo
kubectl top nodes

# Consumo real de CPU y memoria por Pod (en el namespace actual)
kubectl top pods

# Estado del HPA: réplicas actuales, objetivo y utilización de la métrica
kubectl get hpa

# Detalle del HPA del classifier: métrica, eventos (SuccessfulRescale,
# ScaleDownStabilized) y decisiones de escalado
kubectl describe hpa classifier

# Pods del classifier con su nodo asignado
kubectl get pods -l app=classifier -o wide

# Services: tipo (LoadBalancer), CLUSTER-IP y EXTERNAL-IP asignada
kubectl get services

# Eventos recientes del clúster (incluye los eventos del HPA)
kubectl get events
```

**Nota sobre las IP:** los nodos no tienen `EXTERNAL-IP`, y las IP públicas de
los Services (`app2` y `classifier`, ambos de tipo `LoadBalancer`) son asignadas
dinámicamente por Azure y **pueden cambiar**. Por eso no se documentan como
valores permanentes y deben verificarse en el momento de la demostración con
`kubectl get services`.

### Ejemplo de prueba de carga (referencia metodológica)

Para reproducir la prueba de carga del `classifier` se usó el endpoint
`POST /predict` con envío de imágenes vía `multipart/form-data`, en una **carga
sostenida de 60 segundos**, emitiendo solicitudes de forma concurrente o
continua. El conteo de inferencias completadas (2183) corresponde al resultado
de **esa ejecución concreta**, no a un valor máximo garantizado.

```bash
# Verificación manual de un solo archivo
curl -X POST -F "file=@imagen.jpg" http://<EXTERNAL-IP-classifier>/predict

# Línea base del consumo (antes y después de la carga)
kubectl top pods -l app=classifier
```

## 10. Conclusiones técnicas

- El clúster **`aks-microproyecto2`** (Kubernetes v1.35.7, Ubuntu 24.04.4 LTS,
  containerd 2.3.3-2) quedó verificado con **2 nodos `Ready`** y una línea base
  estable: el nodo `000000` con ≈ 114m/6 % de CPU y 2208 Mi/43 % de memoria, y
  el nodo `000001` con ≈ 115m/6 % de CPU y 1682 Mi/33 % de memoria. Ninguna
  aplicación se aproxima a sus limits en reposo.
- `app2` y `classifier` presentan un consumo en reposo bajo: ≈ **2m/34 Mi** y
  ≈ **2m/334 Mi** respectivamente. El peso de memoria del `classifier`
  corresponde al modelo cargado en memoria (carga diferida en la primera
  inferencia).
- La prueba de `app2` (100 solicitudes a `/info`) no produjo un pico capturado
  por `kubectl top`: la carga fue corta y ligera. **No se concluye que `app2`
  carezca de consumo adicional bajo carga**; solo se documenta lo observado.
- Bajo la prueba sostenida de 60 s, el `classifier` completó **2183 inferencias**
  con muestras puntuales de ≈67m de CPU y, durante el escalado, una réplica
  adicional con ≈112m/267Mi. Este resultado **no es un benchmark ni un
  throughput máximo**; corresponde a esa prueba concreta.
- El **HPA respondió conforme a su configuración**: con request de 100m y
  objetivo de 60 %, superada la utilización, registró **`SuccessfulRescale`** y
  escaló de **1 → 2 Pods** (un Pod por nodo). Al terminar la carga, la CPU volvió
  a ≈2 %, se observó **`ScaleDownStabilized`** y el HPA redujo a **1 Pod**. El
  porcentaje se calcula sobre el **CPU request** del Pod, no sobre la CPU total
  del nodo.
- Los **requests/limits** del `classifier` (100m/384Mi y 500m/768Mi) quedaron
  definidos a partir del consumo real medido. Documentamos que alcanzar el CPU
  limit **puede** producir throttling y que superar el memory limit **puede**
  provocar OOMKill, pero **ninguno de estos comportamientos fue provocado ni
  medido** en nuestras pruebas.
- La validación visual en **Azure Portal Metrics** mostró ≈ **5.4055 %** de CPU
  en el API Server (plano de control, no aplicaciones), ≈ **5.8920 %** y
  ≈ **5.7108 %** en los dos nodos (coherentes con `kubectl top nodes`) y
  ≈ **10.6 GB** de memoria disponible a nivel de clúster. Son observaciones
  puntuales: no son benchmarks y los picos del historial no se atribuyen a
  ningún evento sin evidencia.
- **Container Insights quedó deshabilitado** por una restricción regional de la
  política de la suscripción (no por fallo del AKS), y Azure Portal Metrics
  **no lo sustituye**. La evidencia de monitoreo presentada se obtuvo con
  `kubectl top`, estado de Pods/nodos, eventos del HPA y la validación visual
  de Azure Portal Metrics documentada en este archivo.
- El proyecto no depende de IPs públicas fijas: las verificaciones se realizan
  sobre objetos de Kubernetes y las IP externas se consultan en el momento de la
  demostración. No se incluyen credenciales, tokens, IDs de suscripción ni
  secretos en este documento.