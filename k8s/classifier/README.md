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
| `deployment.yaml` | Deployment | Define el Pod del clasificador, su imagen, puerto y sondas.     |
| `service.yaml`    | Service    | Expone el Pod con una IP pública para acceder desde fuera de AKS. |

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
- **Sin** `resources` (requests/limits): se definirán después de medir el consumo real
  del contenedor.
- **Sin** privilegios, secretos ni `imagePullSecret`.

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

## Validación propuesta (no ejecutar desde aquí)

Los siguientes comandos son una guía para validar el despliegue. **No deben
ejecutarse como parte de la creación de los manifiestos.**

```bash
# Aplicar los manifiestos
kubectl apply -f k8s/classifier/

# Estado del Deployment y del rollout
kubectl rollout status deployment/classifier

# Pods (nombre, estado y nodo)
kubectl get pods -l app=classifier -o wide

# Detalle del Pod (eventos, sondas, imagen)
kubectl describe pod -l app=classifier

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
- Los `requests`/`limits` de CPU y memoria se agregarán en una fase posterior, tras
  medir el consumo real del contenedor.
