# classifier

Servicio de **clasificación de imágenes** del Microproyecto 2 de Computación en la Nube (Computación en la Nube). Expone una API HTTP mínima de inferencia usando un modelo preentrenado **ResNet18** de torchvision (ImageNet). Solo inferencia en CPU; no se entrena nada.

## Endpoints

| Método | Ruta       | Descripción                                                 |
| ------ | ---------- | ----------------------------------------------------------- |
| GET    | `/health`  | Verificación de vida. Responde `{"status": "ok"}`.          |
| POST   | `/predict` | Recibe una imagen (multipart, campo `file`) y devuelve clase y confianza. |

`/predict` responde un JSON como:

```json
{
  "class": "tabby, tabby cat",
  "confidence": 0.8765
}
```

Si el archivo no es una imagen válida, responde `400` con `{"detail": "Invalid image file"}`.

## Estructura

```
app/
├── main.py      API FastAPI: /health y /predict
└── model.py     Carga única del modelo ResNet18 y función predict()
tests/
└── test_predict.py   Pruebas de health, predicción e imagen inválida
requirements.txt
README.md
```

## Instalación y ejecución local

Para desarrollo y pruebas (incluye `pytest` y `httpx2`):

```bash
python -m venv .venv
.venv\Scripts\activate         # Windows
pip install -r requirements-dev.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

`requirements.txt` contiene el conjunto runtime (incluye `torch` y `torchvision`, instalados por Docker desde el índice CPU de PyTorch); `requirements-dev.txt` agrega solo las dependencias de desarrollo/pruebas.

La primera ejecución descarga los pesos oficiales de ImageNet (~45 MB) desde download.pytorch.org y los guarda en la caché local (`~/.cache/torch`).

Pruebas:

```bash
python -m pytest tests/
```

Ejemplos con curl:

```bash
curl http://localhost:8000/health
curl -X POST -F "file=@imagen.jpg" http://localhost:8000/predict
```

## Notas

- Los pesos del modelo se descargan una sola vez y el modelo se carga en memoria una única vez, reutilizándose en todas las predicciones.
- El preprocesamiento usado es el oficial de torchvision para estos pesos (`ResNet18_Weights.IMAGENET1K_V1.transforms()`).
- Este servicio no incluye todavía Dockerfile ni manifiestos de Kubernetes; se agregarán en una fase posterior.