FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV APP_HOME=/app
ENV NOTIFICATION_SERVICE_PORT=8003
ENV NOTIFICATION_GUNICORN_WORKERS=2

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --create-home appuser

COPY services/notification/requirements.txt ./requirements.txt

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY shared ./shared
COPY services/notification/ .

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8003

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD curl -f http://localhost:8003/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD gunicorn app.main:app -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8003 --workers 2
