FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_LINK_MODE=copy

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir uv==0.9.15

WORKDIR /app

COPY services/chat-api/requirements.lock /app/requirements.lock
RUN uv pip install --system --no-cache --require-hashes --only-binary :all: -r /app/requirements.lock

COPY services/chat-api/src /app/src
COPY db /app/db

EXPOSE 8002

CMD ["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port ${PORT:-8002} --no-access-log"]
