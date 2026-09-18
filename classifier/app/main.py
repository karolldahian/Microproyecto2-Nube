import io

from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image

from app.model import predict

app = FastAPI(title="Classifier API", version="1.0.0")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/predict")
async def predict_endpoint(file: UploadFile = File(...)):
    data = await file.read()
    try:
        image = Image.open(io.BytesIO(data))
        image.load()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid image file")
    if image.mode != "RGB":
        image = image.convert("RGB")
    return predict(image)