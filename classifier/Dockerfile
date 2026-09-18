# syntax=docker/dockerfile:1
FROM python:3.14.7-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TORCH_HOME=/home/app/.cache/torch

ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cpu

RUN groupadd --system app && useradd --system --gid app --home-dir /home/app app \
    && mkdir -p "$TORCH_HOME" && chown -R app:app /home/app

WORKDIR /app

COPY --chown=app:app requirements.txt requirements-runtime.txt /app/

RUN pip install --no-cache-dir --index-url "$TORCH_INDEX_URL" torch==2.14.0 torchvision==0.29.0 \
    && pip install --no-cache-dir -r /app/requirements-runtime.txt

COPY --chown=app:app app/ /app/app/

USER app

RUN python -c "import torch; assert torch.version.cuda is None, 'build CUDA detectado'; print('torch', torch.__version__)" \
    && python -c "from app.model import get_model; get_model()" \
    && ls -lh "$TORCH_HOME/hub/checkpoints/" \
    && test -s "$TORCH_HOME"/hub/checkpoints/resnet18-*.pth

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]