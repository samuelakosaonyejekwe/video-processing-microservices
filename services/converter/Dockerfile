FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV APP_HOME=/app
ENV CONVERTER_SERVICE_PORT=8002
ENV CONVERTER_GUNICORN_WORKERS=2
ENV APP_MODULE=app.main:app
ENV APP_PORT=8002
ENV INTERNAL_TLS_PORT=8443

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --create-home appuser

COPY services/converter/requirements.txt ./requirements.txt

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY shared ./shared
COPY services/converter/ .
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh && \
    mkdir -p /tmp/uploads /tmp/output /tmp/video-converter && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 8002 8443

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8002/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/usr/local/bin/docker-entrypoint.sh"]
