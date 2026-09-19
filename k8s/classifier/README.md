# Despliegue del clasificador en AKS

Manifiestos de Kubernetes para desplegar en **Azure Kubernetes Service (AKS)** el
servicio `classifier`, que corresponde a la **API de clasificación de imágenes del
requisito académico** del Microproyecto 2 de Computación en la Nube.

- Aplicación: FastAPI + Uvicorn (`classifier/`).
- Escucha en el puerto `8000`.
- `GET /health` → `200` y `{"status": "ok"}`.
- `POST /predict` → imagen vía `multipart/form-data` en el campo `file`.
- Imagen pública: `ghcr.io/karolldahian/microproyecto2-classifier:v1`
  (digest `sha256:e3eaeda6aeb4936c757a508ceaf96b7728dc09b348ef75132c5f642cfb8b2c25`).
- El pull anónimo desde GHCR ya fue validado; **no se usa `imagePullSecret`**.

## Archivos

| Archivo           | Recurso    | Qué crea                                                        |
| ----------------- | ---------- | --------------------------------------------------------------- |
| `deployment.yaml` | Deployment | Define el Pod del clasificador, su imagen, puerto, sondas y límites de recursos. |
| `service.yaml`    | Service    | Expone el Pod con una IP pública para acceder desde fuera de AKS. |
| `hpa.yaml`        | HPA        | Escala automáticamente el Deployment según la utilización de CPU. |

Para aplicar todo el directorio:

```bash
kubectl apply -f k8s/classifier/
```

## Glosario

- **Deployment**: objeto que declara el estado deseado de la aplicación. Kubernetes
  crea y mantiene los Pods para cumplir ese estado.
- **Pod**: unidad mínima de ejecución; aquí contiene un único contenedor con la API.
- **Réplica**: copia del Pod. El manifiesto define `replicas: 1`, es decir, un solo
  Pod en ejecución.
- **Service**: punto de acceso estable con una IP propia que enruta tráfico hacia los
  Pods. Evita depender de la IP cambiante de un Pod.
- **Selector**: etiqueta (`app: classifier`) que usan el Deployment y el Service para
  encontrar sus Pods. El `selector` del Deployment debe coincidir con las labels del
  `template` del Pod; el del Service debe coincidir con las labels de los Pods.
- **readinessProbe**: indica si el Pod está **listo para recibir tráfico**. Mientras
  no pase, el Service no le envía peticiones.
- **livenessProbe**: indica si el Pod sigue **vivo y no colgado**. Si falla de forma
  repetida, Kubernetes reinicia el contenedor.

## Deployment

`deployment.yaml`:

- `apiVersion: apps/v1`, `kind: Deployment`, nombre `classifier`.
- Labels coherentes entre `metadata.labels`, `spec.selector.matchLabels` y las labels
  del `spec.template.metadata.labels` (`app: classifier`).
- `replicas: 1`.
- Imagen pública de GHCR con tag versionado `v1`.
- `imagePullPolicy: IfNotPresent`: al ser un tag de versión inmutable, se reutiliza la
  copia ya presente en el nodo y solo se descarga si no existe. `Always` se reserva
  para tags mutables como `latest`.
- `containerPort: 8000`, el mismo puerto donde escucha Uvicorn.
- **`resources`** (requests/limits) definidos a partir del consumo real medido en AKS:

  ```yaml
  resources:
    requests:
      cpu: 100m
      memory: 384Mi
    limits:
      cpu: 500m
      memory: 768Mi
  ```
- **Sin** privilegios, secretos ni `imagePullSecret`.

### Requests vs limits

- **request** (CPU `100m`, memoria `384Mi`): la cantidad mínima que el contenedor
  necesita; es lo que el *scheduler* reserva en el nodo. Además, es la referencia que
  usa el HPA para calcular la utilización de CPU. Valores cercanos al consumo en
  reposo observado (≈334 Mi de RAM) para no sobre-reservar capacidad del nodo.
- **limit** (CPU `500m`, memoria `768Mi`): el máximo que el contenedor puede llegar a
  consumir. Para CPU, si el contenedor supera el límite, **su uso de CPU es limitado
  (*throttled*)**, no se detiene: se reduce el tiempo de CPU que el kernel le permite,
  lo que puede ralentizar la respuesta. Para memoria, el límite sí es duro: si el
  contenedor supera el `memory limit`, el kernel puede matarlo con un **OOMKill**
  (terminación por falta de memoria), y Kubernetes reinicia el contenedor.

### Sondas

Ambas sondas consultan `GET /health` en el puerto `8000` y sirven para verificar la
**disponibilidad y salud de la API HTTP**, no para validar que el modelo haya
realizado una inferencia correcta.

El modelo ResNet18 usa **carga diferida** (`_model = None` y `get_model()` en
`classifier/app/model.py`): no se carga al arrancar FastAPI, sino en la primera
llamada a `predict()`. Por eso, el estado de `/health` **no** depende de que el modelo
esté cargado en memoria, y las sondas no deben interpretarse como validación de la
inferencia.

- `readinessProbe`: `initialDelaySeconds: 10`, `periodSeconds: 10`,
  `timeoutSeconds: 3`, `failureThreshold: 3`. Valores conservadores que dan margen al
  arranque de Uvicorn antes de empezar a considerar el Pod listo.
- `livenessProbe`: `initialDelaySeconds: 30`, `periodSeconds: 20`,
  `timeoutSeconds: 3`, `failureThreshold: 3`. Más espaciada y con mayor retardo que la
  readiness para evitar reinicios innecesarios durante el arranque.

## Service

`service.yaml`:

- `apiVersion: v1`, `kind: Service`, nombre `classifier`.
- `selector: app: classifier`, idéntico a las labels de los Pods.
- `port: 80` (puerto publicado por el Service) y `targetPort: 8000` (puerto del
  contenedor).

### Por qué `type: LoadBalancer`

Se eligió `LoadBalancer` porque el objetivo es **demostrar `/health` y `/predict`
desde fuera del clúster AKS**. En AKS, este tipo aprovisiona una IP pública mediante
Azure Load Balancer y enruta el tráfico al Service, sin depender de `kubectl
port-forward`.

Alternativas descartadas:

- `ClusterIP`: solo accesible dentro del clúster; no permite la demostración externa.
- `NodePort`: requeriría usar la IP pública de un nodo y reglas del NSG, con un puerto
  alto; menos claro y más frágil que una IP pública estable del Service.

## HorizontalPodAutoscaler (HPA)

`hpa.yaml`:

- `apiVersion: autoscaling/v2`, `kind: HorizontalPodAutoscaler`, nombre `classifier`.
- `scaleTargetRef`: apunta al **Deployment `classifier`** (`apps/v1`). El HPA actúa
  sobre el Deployment y ajusta el número de réplicas; cuando el HPA está activo, es él
  quien controla `spec.replicas` (el `replicas: 1` del Deployment queda como valor
  inicial gestionado por el HPA).
- `minReplicas: 1`: **nunca** reduce el Deployment por debajo de 1 Pod.
- `maxReplicas: 3`: **nunca** escala por encima de 3 Pods.
- Métrica: CPU con `target.type: Utilization` y `averageUtilization: 60`.

### Cómo decide escalar

El HPA mide la **utilización de CPU promedio de los Pods respecto al CPU request** de
cada Pod (100m). Con `averageUtilization: 60`, el objetivo es que cada Pod use en
promedio el **60 % de su request** (≈60m de CPU). Si la carga hace que esa utilización
supere el objetivo, el HPA aumenta las réplicas (hasta `maxReplicas`); cuando la carga
desciende y la utilización vuelve a estar por debajo del objetivo, el HPA reduce las
réplicas tras un período de estabilización, pero **nunca por debajo de `minReplicas`**.

Por eso el HPA depende del `request` de CPU definido en el Deployment: si no existiera
el request, no habría base sobre la cual calcular el porcentaje de utilización.

## Validación experimental del HPA en AKS

El HPA fue desplegado junto con el Deployment y sometido a una **prueba de carga
sostenida de 60 segundos** (`/predict` con imágenes):

- En reposo, el Pod consumía ≈**2m de CPU** y ≈**334 Mi de RAM**.
- Durante la carga se observó un pico de ≈**67m de CPU** (≈67 % del request de 100m),
  por encima del objetivo del 60 %.
- El HPA registró el evento **`SuccessfulRescale`** por utilización de CPU por encima
  del objetivo.
- Escaló automáticamente de **1 → 2 Pods**, y los dos Pods quedaron temporalmente
  distribuidos entre los dos nodos del AKS.
- Al terminar la carga, la CPU volvió a ≈2 %; apareció **`ScaleDownStabilized`** (período
  de estabilización para no oscilar) y el HPA redujo automáticamente de **2 → 1 Pod**.

En esa prueba se completaron **2183 inferencias en los 60 segundos**. Este número es el
**resultado observado de esta prueba concreta** (para el clúster, la carga y la imagen
usados): **no** debe presentarse como un benchmark máximo ni como una afirmación de la
capacidad del clasificador.

## Validación propuesta (no ejecutar desde aquí)

Los siguientes comandos son una guía para validar el despliegue. **No deben
ejecutarse como parte de la creación de los manifiestos.**

```bash
# Aplicar los manifiestos
kubectl apply -f k8s/classifier/

# Estado del Deployment y del rollout
kubectl rollout status deployment/classifier

# Deployment (deseado y listo; el número de réplicas lo corrige el HPA)
kubectl get deployment classifier

# Pods (nombre, estado y nodo)
kubectl get pods -l app=classifier -o wide

# Detalle del Pod (eventos, sondas, imagen, recursos)
kubectl describe pod -l app=classifier

# HPA: objetivo, réplicas actuales y utilización de CPU
kubectl get hpa classifier

# Consumo real de CPU y memoria por Pod / por nodo
kubectl top pods -l app=classifier
kubectl top nodes

# Logs del contenedor
kubectl logs -l app=classifier

# Service y su IP externa (EXTERNAL-IP puede tardar en asignarse)
kubectl get svc classifier

# Endpoints: confirma que el Service apunta a la IP del Pod en el puerto 8000
kubectl get endpoints classifier

# Pruebas desde fuera del clúster (sustituir <EXTERNAL-IP>)
curl http://<EXTERNAL-IP>/health
curl -X POST -F "file=@imagen.jpg" http://<EXTERNAL-IP>/predict

# Eliminar los recursos (limpieza)
kubectl delete -f k8s/classifier/
```

## Notas

- No se incluyen credenciales, tokens, kubeconfig ni secretos.
- El digest de la imagen está documentado para trazabilidad; el manifiesto usa el tag
  `v1` indicado.
- Los `requests`/`limits` y el HPA quedan definidos a partir del consumo real medido
  en AKS (requests ≈ consumo en reposo; limit de CPU con margen para picos; HPA con
  objetivo del 60 % sobre el CPU request).
