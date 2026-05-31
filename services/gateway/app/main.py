import hashlib
import logging
import os
from contextlib import asynccontextmanager

import jwt
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from jwt.exceptions import ExpiredSignatureError, PyJWTError
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import (
    APP_ENV,
    CORS_ALLOWED_ORIGINS,
    JWT_ALGORITHM,
    JWT_AUDIENCE,
    JWT_ISSUER,
    JWT_PUBLIC_KEY,
)
from app.database.job_repository import mongo_available
from app.database.mongo_client import close_mongo_client
from app.middleware.auth_middleware import AuthMiddleware
from app.middleware.rate_limit_middleware import RateLimitMiddleware
from app.queue.consumer import start_consumer, stop_consumer
from app.queue.producer import get_gateway_producer
from app.routes.auth_routes import router as auth_router
from app.routes.converter_routes import router as converter_router
from app.routes.jobs_routes import router as jobs_router
from shared.errors.handlers import register_exception_handlers
from shared.logging.logger import configure_logging
from shared.middleware.correlation_id import CorrelationIdMiddleware
from shared.middleware.metrics_guard import MetricsGuardMiddleware
from shared.runtime.queue_consumer import queue_consumer_enabled
from shared.runtime.tracing import configure_tracing

APP_NAME = os.getenv("APP_NAME") or "gateway-service"
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging(APP_NAME)
    configure_tracing(APP_NAME)
    logger.info("Starting gateway service in %s mode", APP_ENV)

    if APP_ENV != "test" and queue_consumer_enabled():
        start_consumer()

    yield

    logger.info("Shutting down gateway service...")
    stop_consumer()
    try:
        get_gateway_producer().close()
    except Exception as error:
        logger.warning("Gateway producer close failed: %s", error)
    close_mongo_client()


_enable_docs = (
    os.getenv("ENABLE_SWAGGER", "false").lower() in ("true", "1", "yes")
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
app.add_middleware(CorrelationIdMiddleware)
app.add_middleware(MetricsGuardMiddleware)

app.include_router(auth_router)
app.include_router(converter_router)
app.include_router(jobs_router)
register_exception_handlers(app)


if APP_ENV != "production":

    @app.post("/health/verify-token")
    async def verify_token(request: Request):
        authorization = request.headers.get("Authorization")
        if not authorization:
            return {"valid": False, "detail": "Authorization header missing"}

        parts = authorization.split()
        if len(parts) != 2 or parts[0].lower() != "bearer":
            return {"valid": False, "detail": "Invalid authorization header"}

        token = parts[1]

        try:
            import app.config as jwt_config

            algorithm = jwt_config.JWT_ALGORITHM
            decode_key = (
                jwt_config.JWT_PUBLIC_KEY
                if algorithm.startswith("RS")
                else jwt_config.JWT_SECRET
            )
            payload = jwt.decode(
                token,
                decode_key,
                algorithms=[algorithm],
                issuer=jwt_config.JWT_ISSUER if algorithm.startswith("RS") else None,
                audience=jwt_config.JWT_AUDIENCE if algorithm.startswith("RS") else None,
            )
            if payload.get("type") and payload.get("type") != "access":
                return {"valid": False, "detail": "Invalid token type"}
            return {"valid": True, "sub": payload.get("sub")}
        except ExpiredSignatureError:
            return {"valid": False, "detail": "Token expired"}
        except PyJWTError:
            return {"valid": False, "detail": "Invalid token"}

    @app.get("/health/jwt")
    async def jwt_health():
        fingerprint = (
            hashlib.sha256(JWT_PUBLIC_KEY.encode()).hexdigest()[:16]
            if JWT_PUBLIC_KEY
            else ""
        )
        return {
            "algorithm": JWT_ALGORITHM,
            "issuer": JWT_ISSUER,
            "audience": JWT_AUDIENCE,
            "public_key_loaded": bool(JWT_PUBLIC_KEY),
            "public_key_fingerprint": fingerprint,
        }


@app.get("/health/ready")
async def readiness_check():
    if not mongo_available():
        return JSONResponse(
            status_code=503,
            content={
                "status": "not_ready",
                "service": APP_NAME,
                "mongodb": "unavailable",
            },
        )

    return {"status": "ready", "service": APP_NAME, "mongodb": "ok"}


@app.get("/health")
@app.get("/health/")
async def health_check():
    return {"status": "healthy", "service": APP_NAME}


@app.get("/")
async def root():
    return {"message": "Gateway Service Running"}
