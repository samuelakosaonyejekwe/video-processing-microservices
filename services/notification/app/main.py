import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import APP_ENV, APP_NAME, APP_PORT, CORS_ALLOWED_ORIGINS
from app.config import WEBSOCKET_NOTIFICATIONS_ENABLED
from app.queue.consumer import start_consumer, stop_consumer
from app.websocket.events import start_websocket_background
from app.websocket.redis_fanout import is_fanout_subscriber_ready
from shared.errors.handlers import register_exception_handlers
from shared.logging.logger import configure_logging
from shared.middleware.correlation_id import CorrelationIdMiddleware
from shared.middleware.metrics_guard import MetricsGuardMiddleware
from shared.runtime.queue_consumer import queue_consumer_enabled
from shared.runtime.tracing import configure_tracing

_enable_docs = (
    os.getenv("ENABLE_SWAGGER", "false").lower()
    in (
        "true",
        "1",
        "yes",
    )
    or APP_ENV != "production"
)


def _smtp_configured() -> bool:
    return bool(os.getenv("SMTP_HOST", "").strip())


@asynccontextmanager
async def lifespan(app: FastAPI):

    configure_logging(APP_NAME)
    configure_tracing(APP_NAME)

    if APP_ENV != "test":
        if queue_consumer_enabled():
            start_consumer()
        start_websocket_background()

    yield

    stop_consumer()


app = FastAPI(
    title=APP_NAME,
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if _enable_docs else None,
    redoc_url="/redoc" if _enable_docs else None,
    openapi_url="/openapi.json" if _enable_docs else None,
)

Instrumentator().instrument(app).expose(app)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(CorrelationIdMiddleware)
app.add_middleware(MetricsGuardMiddleware)


register_exception_handlers(app)


@app.get("/health")
async def health_check():

    return {
        "status": "healthy",
        "service": APP_NAME,
        "environment": APP_ENV,
    }


@app.get("/health/ready")
async def readiness_check():
    if not _smtp_configured():
        return JSONResponse(
            status_code=503,
            content={
                "status": "not_ready",
                "service": APP_NAME,
                "smtp": "unconfigured",
            },
        )

    if (
        WEBSOCKET_NOTIFICATIONS_ENABLED
        and os.getenv("REDIS_HOST", "").strip()
        and not is_fanout_subscriber_ready()
    ):
        return JSONResponse(
            status_code=503,
            content={
                "status": "not_ready",
                "service": APP_NAME,
                "websocket_fanout": "subscriber_not_connected",
            },
        )

    return {"status": "ready", "service": APP_NAME, "smtp": "ok"}


@app.get("/")
async def root():

    return {
        "message": "Notification Service Running",
        "service": APP_NAME,
        "environment": APP_ENV,
        "port": APP_PORT,
    }
