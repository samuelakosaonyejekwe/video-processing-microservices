import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import APP_ENV, APP_NAME, CORS_ALLOWED_ORIGINS
from app.queue.consumer import start_consumer
from app.routes.convert import router as convert_router
from app.routes.health import router as health_router
from shared.runtime.queue_consumer import queue_consumer_enabled

_enable_docs = (
    os.getenv("ENABLE_SWAGGER", "false").lower()
    in (
        "true",
        "1",
        "yes",
    )
    or APP_ENV != "production"
)


@asynccontextmanager
async def lifespan(app: FastAPI):

    if APP_ENV != "test" and queue_consumer_enabled():
        start_consumer()

    yield


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

app.include_router(convert_router)
app.include_router(health_router)


@app.get("/")
async def root():

    return {
        "message": "Converter Service Running",
    }


@app.get("/health")
async def health_check():

    return {
        "status": "healthy",
        "service": APP_NAME,
    }


@app.get("/ready")
async def readiness_check():

    return {
        "status": "ready",
        "service": APP_NAME,
    }


@app.get("/live")
async def liveness_check():

    return {
        "status": "alive",
        "service": APP_NAME,
    }
