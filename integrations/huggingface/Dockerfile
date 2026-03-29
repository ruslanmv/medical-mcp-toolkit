# ============================================================
# Medical AI Hospital Portal — HuggingFace Spaces (Docker SDK)
# Backend: LangGraph + HuggingFace Inference (replaces WatsonX)
# Frontend: Next.js 14 React Portal
# ============================================================

# ---------- Stage 1: Build Next.js frontend ----------
FROM node:20-alpine AS frontend-builder

WORKDIR /build

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --ignore-scripts

COPY frontend/ ./

ENV NEXT_PUBLIC_API_BASE=""
ENV NEXT_PUBLIC_APP_NAME="Medical AI Hospital Portal"
ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# ---------- Stage 2: Runtime ----------
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    nginx \
    supervisor \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 appuser

COPY --from=frontend-builder /build/.next/standalone /app/frontend
COPY --from=frontend-builder /build/.next/static /app/frontend/.next/static
COPY --from=frontend-builder /build/public /app/frontend/public

COPY gateway/requirements.txt /app/gateway/
RUN pip install --no-cache-dir -r /app/gateway/requirements.txt

COPY gateway/ /app/gateway/

COPY nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN mkdir -p /app/data && chown -R appuser:appuser /app /tmp
RUN chown -R appuser:appuser /var/log/nginx /var/lib/nginx /run

EXPOSE 7860

USER appuser

ENV HF_TOKEN=""
ENV DATABASE_PATH="/app/data/medical.db"

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
