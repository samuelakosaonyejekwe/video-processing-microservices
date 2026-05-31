import os
from contextlib import asynccontextmanager
import hashlib

import jwt
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import APP_ENV, APP_NAME, APP_PORT, CORS_ALLOWED_ORIGINS
from app.config import (
    JWT_ALGORITHM,
    JWT_AUDIENCE,
    JWT_ISSUER,
    JWT_PRIVATE_KEY,
    JWT_PUBLIC_KEY,
)
from app.database.connection import engine
from app.models.user_entity import Base
from app.middleware.rate_limit_middleware import AuthRateLimitMiddleware
from app.routes.db_health import router as db_health_router
from app.routes.login import router as login_router
from app.routes.logout import router as logout_router
from app.routes.refresh_token import router as refresh_token_router
from app.routes.register import router as register_router
from shared.errors.handlers import register_exception_handlers
from shared.logging.logger import configure_logging
from shared.middleware.correlation_id import CorrelationIdMiddleware
from shared.middleware.metrics_guard import MetricsGuardMiddleware
from shared.runtime.tracing import configure_tracing


@asynccontextmanager
async def lifespan(app: FastAPI):

    configure_logging(APP_NAME)
    configure_tracing(APP_NAME)

    if APP_ENV not in ("test", "production"):
        Base.metadata.create_all(bind=engine)

    print(f"{APP_NAME} starting in {APP_ENV} mode")

    yield

    print(f"{APP_NAME} shutting down")


_enable_docs = (
    os.getenv("ENABLE_SWAGGER", "false").lower() in ("true", "1", "yes")
    or APP_ENV != "production"
)

app = FastAPI(
    title=APP_NAME,
    lifespan=lifespan,
    docs_url="/docs" if _enable_docs else None,
    redoc_url="/redoc" if _enable_docs else None,
    openapi_url="/openapi.json" if _enable_docs else None,
)

Instrumentator().instrument(app).expose(app, endpoint="/metrics")

app.add_middleware(MetricsGuardMiddleware)
app.add_middleware(CorrelationIdMiddleware)
app.add_middleware(AuthRateLimitMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(login_router)
app.include_router(register_router)
app.include_router(refresh_token_router)
app.include_router(logout_router)
app.include_router(db_health_router)
register_exception_handlers(app)


@app.get("/health/jwt")
async def jwt_health():
    fingerprint = (
        hashlib.sha256(JWT_PUBLIC_KEY.encode()).hexdigest()[:16]
        if JWT_PUBLIC_KEY
        else ""
    )
    signing_ok = False
    signing_error = ""
    if JWT_PRIVATE_KEY and JWT_PUBLIC_KEY:
        try:
            token = jwt.encode(
                {"healthcheck": "1"},
                JWT_PRIVATE_KEY,
                algorithm=JWT_ALGORITHM,
            )
            jwt.decode(
                token,
                JWT_PUBLIC_KEY,
                algorithms=[JWT_ALGORITHM],
            )
            signing_ok = True
        except jwt.PyJWTError as error:
            signing_error = str(error)
        except (ValueError, TypeError) as error:
            signing_error = str(error)

    return {
        "algorithm": JWT_ALGORITHM,
        "issuer": JWT_ISSUER,
        "audience": JWT_AUDIENCE,
        "private_key_loaded": bool(JWT_PRIVATE_KEY),
        "public_key_loaded": bool(JWT_PUBLIC_KEY),
        "public_key_fingerprint": fingerprint,
        "signing_ok": signing_ok,
        "signing_error": signing_error or None,
    }


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
        "message": "Auth Service Running",
        "environment": APP_ENV,
        "port": APP_PORT,
    }
