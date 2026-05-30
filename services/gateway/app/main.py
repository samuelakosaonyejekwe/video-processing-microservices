import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import APP_ENV, CORS_ALLOWED_ORIGINS
from app.middleware.auth_middleware import AuthMiddleware
from app.middleware.rate_limit_middleware import RateLimitMiddleware
from app.routes.auth_routes import router as auth_router
from app.routes.converter_routes import router as converter_router

APP_NAME = os.getenv("APP_NAME", "gateway-service")


@asynccontextmanager
async def lifespan(app: FastAPI):

    print("Starting gateway service...")

    yield

    print("Shutting down gateway service...")


_enable_docs = (
    os.getenv("ENABLE_SWAGGER", "false").lower()
    in (
        "true",
        "1",
        "yes",
    )
    or APP_ENV != "production"
)

app = FastAPI(
    title=APP_NAME,
    version=os.getenv("APP_VERSION", "1.0.0"),
    docs_url="/docs" if _enable_docs else None,
    redoc_url="/redoc" if _enable_docs else None,
    openapi_url="/openapi.json" if _enable_docs else None,
    lifespan=lifespan,
)

Instrumentator().instrument(app).expose(app)

_cors_origins = CORS_ALLOWED_ORIGINS
if _cors_origins == ["*"] and APP_ENV == "production":
    _cors_origins = [
        origin.strip()
        for origin in os.getenv("FRONTEND_URL", "").split(",")
        if origin.strip()
    ] or _cors_origins

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=_cors_origins != ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(RateLimitMiddleware)
app.add_middleware(AuthMiddleware)

app.include_router(auth_router)
app.include_router(converter_router)


@app.get("/health")
@app.get("/health/")
async def health_check():

    return {
        "status": "healthy",
        "service": APP_NAME,
    }


@app.get("/")
async def root():

    return {
        "message": "Gateway Service Running",
    }
