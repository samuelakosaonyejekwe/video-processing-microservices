import os
from contextlib import asynccontextmanager
import hashlib

import jwt
from jwt.exceptions import ExpiredSignatureError, PyJWTError
from fastapi import Request

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import APP_ENV, CORS_ALLOWED_ORIGINS
from app.config import JWT_ALGORITHM, JWT_AUDIENCE, JWT_ISSUER, JWT_PUBLIC_KEY, JWT_SECRET
from app.middleware.auth_middleware import AuthMiddleware
from app.middleware.rate_limit_middleware import RateLimitMiddleware
from app.routes.auth_routes import router as auth_router
from app.routes.converter_routes import router as converter_router
from app.queue.producer import get_gateway_producer

APP_NAME = os.getenv("APP_NAME") or "gateway-service"


@asynccontextmanager
async def lifespan(app: FastAPI):

    print("Starting gateway service...")

    yield

    print("Shutting down gateway service...")
    try:
        get_gateway_producer().close()
    except Exception:
        pass


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
    except PyJWTError as exc:
        return {
            "valid": False,
            "detail": f"Invalid token: {exc.__class__.__name__}",
            "algorithm": algorithm,
            "key_length": len(decode_key or ""),
        }


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
