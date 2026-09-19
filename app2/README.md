# System Info API (app2)

Microservicio **ligero** del Microproyecto 2 de Computación en la Nube. Es la segunda aplicación (`app2/`): una API HTTP mínima en **FastAPI** que solo expone información básica de la aplicación y del contenedor donde corre. No carga modelos, no requiere GPU y no usa dependencias pesadas.

## Propósito

Complementar la aplicación `classifier/` (que hace inferencia de imágenes) con un servicio mínimalista del que se pueda verificar fácilmente el estado y la identidad del contenedor (hostname, plataforma, versión de Python) — útil para validar que la imagen desplegada en Kubernetes/AKS es la correcta.

## Endpoints

| Método | Ruta      | Descripción                                                     |
| ------ | --------- | --------------------------------------------------------------- |
| GET    | `/`       | Información básica de la aplicación y lista de endpoints.       |
| GET    | `/health` | Verificación de vida. Responde `{"status": "ok"}`.              |
| GET    | `/info`   | Datos del contenedor: hostname, plataforma, versión de Python y timestamp UTC. |

`/info` responde un JSON como:

```json
{
  "hostname": "f3c9a12d4b01",
  "platform": "Linux-6.8.0-...-x86_64-with-glibc2.39",
  "python_version": "3.13.3",
  "timestamp_utc": "2026-09-18T12:34:56.789012+00:00"
}
```

## Ejecución local

```bash
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

Pruebas con curl:

```bash
curl http://localhost:8000/
curl http://localhost:8000/health
curl http://localhost:8000/info
```

## Construcción de la imagen Docker

```bash
docker build -t app2:latest .
```

## Ejecución en Docker

```bash
docker run -d --name app2 -p 8000:8000 app2:latest
```

Verificación:

```bash
curl http://localhost:8000/health
docker logs -f app2
```

La imagen usa `python:3.13-slim`, corre con un usuario no-root (`app`) y expone el puerto `8000` para FastAPI con Uvicorn.

## Publicación en GHCR

La imagen fue publicada en el **GitHub Container Registry (GHCR)**:

- Imagen: `ghcr.io/karolldahian/microproyecto2-app2:v1`
- Digest verificado: `sha256:486c9c400832562c1dda7798eb301a28e1ac6c6d54e40bbb3f296a70bee2f62d`

La descarga fue validada mediante un **pull anónimo** (sin autenticación), lo que
confirma que el paquete es **públicamente accesible**. Por eso, el despliegue en
Kubernetes/AKS **no requiere `imagePullSecret`**: el clúster puede descargar la
imagen directamente desde GHCR.
