# Despliegue de app2 en AKS

Manifiestos de Kubernetes para desplegar en **Azure Kubernetes Service (AKS)** la
segunda aplicación del Microproyecto 2, que corresponde a la **System Info API**
(`app2/`).

- Aplicación: FastAPI + Uvicorn (`app2/`).
- Escucha en el puerto `8000`.
- `GET /health` → `200` y `{"status": "ok"}`.
- `GET /info` → hostname, plataforma, versión de Python y timestamp UTC del contenedor.
- Imagen pública: `ghcr.io/karolldahian/microproyecto2-app2:v1`
  (digest `sha256:486c9c400832562c1dda7798eb301a28e1ac6c6d54e40bbb3f296a70bee2f62d`).
- El pull anónimo desde GHCR ya fue validado; **no se usa `imagePullSecret`**.

## Archivos

| Archivo           | Recurso    | Qué crea                                                          |
| ----------------- | ---------- | ----------------------------------------------------------------- |
| `deployment.yaml` | Deployment | Define el Pod de app2, su imagen, puerto, sondas y contexto de seguridad. |
| `service.yaml`    | Service    | Expone el Pod con una IP pública para acceder desde fuera de AKS. |

Para aplicar todo el directorio:

```bash
kubectl apply -f k8s/app2/
```

## Glosario

- **Deployment**: objeto que declara el estado deseado de la aplicación.
  Kubernetes crea y mantiene los Pods para cumplir ese estado (`replicas: 1`).
- **Service**: punto de acceso estable con una IP propia que enruta tráfico hacia
  los Pods mediante el selector de etiquetas (`app: app2`).
- **Sondas**: consultas que Kubernetes envía al contenedor para decidir si lo
  considera listo o vivo.

## Deployment

`deployment.yaml`:

- `apiVersion: apps/v1`, `kind: Deployment`, nombre `app2`.
- Labels coherentes entre `metadata.labels`, `spec.selector.matchLabels` y las
  labels del template del Pod (`app: app2`).
- `replicas: 1`.
- Imagen pública de GHCR con tag versionado `v1`.
- `imagePullPolicy: IfNotPresent`: reutiliza la copia local de la imagen si ya existe
  en el nodo y solo la descarga si no está presente. Cabe aclarar que el tag `v1` es un
  **tag versionado** (movible: puede apuntar a un contenido nuevo si se republica un
  build), **no es inmutable**. Lo que identifica de forma **inmutable** el contenido
  exacto publicado es el **digest** SHA-256
  (`sha256:486c9c400832562c1dda7798eb301a28e1ac6c6d54e40bbb3f296a70bee2f62d`).
- `containerPort: 8000`, el mismo puerto donde escucha Uvicorn.
- `securityContext` del contenedor (defensa en profundidad; la imagen ya corre como
  usuario no-root `app` cuyo UID/GID `999:999` fue verificado directamente en la
  imagen): `runAsNonRoot: true`, `runAsUser: 999`, `runAsGroup: 999`,
  `allowPrivilegeEscalation: false` y `capabilities.drop: [ALL]`.
- **Sin** `resources` (requests/limits): se definirán después de medir el consumo
  real del contenedor en AKS.

### Sondas

Ambas sondas consultan `GET /health` en el puerto `8000`.

- **readinessProbe** indica si el Pod está **listo para recibir tráfico**. Mientras
  no pase, el Service no le envía peticiones.
  `initialDelaySeconds: 5`, `periodSeconds: 10`, `timeoutSeconds: 3`,
  `failureThreshold: 3`.
- **livenessProbe** indica si el Pod sigue **vivo y no colgado**. Si falla de forma
  repetida, Kubernetes reinicia el contenedor.
  `initialDelaySeconds: 15`, `periodSeconds: 20`, `timeoutSeconds: 3`,
  `failureThreshold: 3`.

La liveness arranca más tarde y consulta con menos frecuencia para evitar reinicios
innecesarios durante el arranque de Uvicorn.

## Service

`service.yaml`:

- `apiVersion: v1`, `kind: Service`, nombre `app2`.
- `type: LoadBalancer`: en AKS aprovisiona una **IP pública** mediante Azure Load
  Balancer, para demostrar los endpoints desde fuera del clúster.
- `selector: app: app2`, idéntico a las labels de los Pods.
- **Relación de puertos `80 -> 8000`**: el Service publica el puerto `80` (externo)
  y reenvía el tráfico al puerto `8000` del contenedor (`targetPort`).

## `imagePullSecret`

La imagen `ghcr.io/karolldahian/microproyecto2-app2:v1` es **públicamente accesible**
en GHCR y la descarga ya fue verificada mediante un **pull anónimo**. Como AKS puede
descargarla sin credenciales, **no se usa `imagePullSecret`**.

## Requests y limits

Todavía **no** se definen `resources` (requests/limits) en el Deployment. Se
agregarán en una fase posterior, una vez medido el consumo real de CPU y memoria del
contenedor en AKS, para fijar valores acertados sin riesgo de evicción prematura.

## Validación ejecutada en AKS

App2 fue desplegada en AKS y verificada:

- Deployment `app2`: Pod `1/1` en estado `Running` con `0` reinicios.
- Service `app2` tipo LoadBalancer funcionando con IP externa asignada.
- Endpoints `GET /`, `GET /health` y `GET /info` respondiendo correctamente.

Comandos de validación (referencia):

```bash
# Validar sintaxis localmente (sin tocar el clúster)
kubectl apply --dry-run=client -f k8s/app2/

# Aplicar los manifiestos
kubectl apply -f k8s/app2/

# Estado del rollout
kubectl rollout status deployment/app2 --timeout=2m

# Pods del despliegue
kubectl get pods -l app=app2 -o wide

# Service y su IP externa (EXTERNAL-IP puede tardar en asignarse)
kubectl get service app2

# Endpoints gestionados por el Service
kubectl get endpointslices -l kubernetes.io/service-name=app2
```

## Notas

- No se incluyen credenciales, tokens, kubeconfig ni secretos.
- El digest de la imagen está documentado para trazabilidad; el manifiesto usa el
  tag `v1` indicado.