import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import APP_ENV, APP_NAME, APP_PORT, CORS_ALLOWED_ORIGINS
from app.queue.consumer import start_consumer
from app.websocket.events import start_websocket_background

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

    if APP_ENV != "test":
        start_consumer()
        start_websocket_background()

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


@app.get("/health")
async def health_check():

    return {
        "status": "healthy",
        "service": APP_NAME,
        "environment": APP_ENV,
    }


@app.get("/")
async def root():

    return {
        "message": "Notification Service Running",
        "service": APP_NAME,
        "environment": APP_ENV,
        "port": APP_PORT,
    }
