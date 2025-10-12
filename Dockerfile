# syntax=docker/dockerfile:1.7

FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# System deps
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy project
COPY pyproject.toml README.md ./
COPY schemas ./schemas
COPY server.py ./server.py
COPY src ./src

RUN pip install --upgrade pip && pip install -e .

EXPOSE 8080
ENV HOST=0.0.0.0 PORT=8080

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080"]
