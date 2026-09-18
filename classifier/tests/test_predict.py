import io

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_predict_valid_image():
    image = Image.fromarray(
        np.random.randint(0, 256, (224, 224, 3), dtype=np.uint8)
    ).convert("RGB")
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG")

    response = client.post(
        "/predict",
        files={"file": ("image.jpg", buffer.getvalue(), "image/jpeg")},
    )

    assert response.status_code == 200
    body = response.json()
    assert "class" in body
    assert "confidence" in body
    assert 0.0 <= body["confidence"] <= 1.0


def test_predict_invalid_file():
    response = client.post(
        "/predict",
        files={"file": ("not_an_image.txt", b"this is not an image", "text/plain")},
    )

    assert response.status_code == 400