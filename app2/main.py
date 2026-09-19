import platform
import socket
import sys
from datetime import datetime, timezone

from fastapi import FastAPI

app = FastAPI(title="System Info API", version="1.0.0")


@app.get("/")
def root():
    return {
        "app": "System Info API",
        "version": app.version,
        "description": "Mini API ligera que expone información básica de la aplicación y del contenedor en el que corre.",
        "endpoints": ["/", "/health", "/info"],
    }


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/info")
def info():
    return {
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python_version": sys.version.split()[0],
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
    }
