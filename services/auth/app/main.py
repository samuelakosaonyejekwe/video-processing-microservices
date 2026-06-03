import logging
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
    JWT_PRIVATE_KEY,
    JWT_PUBLIC_KEY,
)
from app.database.connection import engine
from app.models.user_entity import Base
from app.middleware.rate_limit_middleware import AuthRateLimitMiddleware
from app.routes.db_health import router as db_health_router
from app.routes.login import router as login_router
from app.routes.logout import router as logout_router
from app.routes.me import router as me_router
from app.routes.refresh_token import router as refresh_token_router
from app.routes.register import router as register_router
from shared.errors.handlers import register_exception_handlers
from shared.logging.logger import configure_logging
from shared.middleware.correlation_id import CorrelationIdMiddleware
from shared.middleware.metrics_guard import MetricsGuardMiddleware
from shared.middleware.security_headers import SecurityHeadersMiddleware
from shared.runtime.tracing import configure_tracing
from shared.security.cors import ALLOWED_CORS_HEADERS

logger = logging.getLogger(__name__)

# Token revocation is security-critical for the auth service. The shared
# revocation store fails open when Redis is unconfigured, so in production a
# missing REDIS_HOST would silently disable revocation. Fail hard at startup
# instead of shipping a fail-open auth service.
if APP_ENV == "production" and not os.getenv("REDIS_HOST", "").strip():
    raise RuntimeError(
        "REDIS_HOST is required in production for token revocation"
    )


@asynccontextmanager
async def lifespan(app: FastAPI):

    configure_logging(APP_NAME)
    configure_tracing(APP_NAME)

    if APP_ENV not in ("test", "production"):
        Base.metadata.create_all(bind=engine)

    logger.info("%s starting in %s mode", APP_NAME, APP_ENV)

    yield

    logger.info("%s shutting down", APP_NAME)


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
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(CorrelationIdMiddleware)
app.add_middleware(AuthRateLimitMiddleware)

if CORS_ALLOWED_ORIGINS == ["*"]:
    raise RuntimeError(
        "CORS_ALLOWED_ORIGINS cannot be '*' with credentialed requests; "
        "set explicit origins"
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_credentials=CORS_ALLOWED_ORIGINS != ["*"],
    allow_methods=["*"],
    allow_headers=ALLOWED_CORS_HEADERS,
)

app.include_router(login_router)
app.include_router(register_router)
app.include_router(refresh_token_router)
app.include_router(logout_router)
app.include_router(me_router)
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

    # Do not expose issuer/audience or raw signing-error text on an
    # unauthenticated endpoint (recon / information disclosure). The boolean
    # health signals are sufficient for probes.
    return {
        "algorithm": JWT_ALGORITHM,
        "private_key_loaded": bool(JWT_PRIVATE_KEY),
        "public_key_loaded": bool(JWT_PUBLIC_KEY),
        "public_key_fingerprint": fingerprint,
        "signing_ok": signing_ok,
        "signing_configured": bool(signing_error) is False,
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
