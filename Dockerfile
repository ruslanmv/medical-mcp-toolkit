# syntax=docker/dockerfile:1.7

# Use Python 3.11 to satisfy requires-python >=3.11,<3.12
FROM python:3.11-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# System deps (minimal)
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl ca-certificates build-essential \
 && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -ms /bin/bash appuser

# Copy project files
COPY pyproject.toml README.md ./
COPY schemas ./schemas
COPY server.py ./server.py
COPY src ./src

# Install project (editable not required in a container; do regular install)
RUN pip install --upgrade pip && pip install .

# Runtime env
ENV HOST=0.0.0.0 \
    PORT=8080 \
    UVICORN_LOG_LEVEL=info

EXPOSE 8080

# Drop privileges
USER appuser

# Run FastAPI HTTP server on :8080
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers"]
