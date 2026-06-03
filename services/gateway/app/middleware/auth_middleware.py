import os

from fastapi import Request
from fastapi.responses import JSONResponse

from starlette.middleware.base import BaseHTTPMiddleware

import jwt
from jwt.exceptions import ExpiredSignatureError, PyJWTError

from shared.security.token_revocation import is_token_revoked


def _strict_cookie_auth_enabled() -> bool:
    return os.getenv("STRICT_COOKIE_AUTH", "false").lower() in ("true", "1", "yes")


class AuthMiddleware(BaseHTTPMiddleware):

    async def dispatch(self, request: Request, call_next):

        public_routes = [
            "/",
            "/docs",
            "/openapi.json",
            "/redoc",
            "/health",
            "/health/",
            "/health/ready",
            "/health/jwt",
            "/health/verify-token",
            "/auth/login",
            "/auth/register",
            "/auth/refresh",
            "/auth/session",
            "/metrics",
        ]

        if request.url.path in public_routes:
            return await call_next(request)

        token = request.cookies.get("access_token")
        authorization = request.headers.get("Authorization")

        if authorization and _strict_cookie_auth_enabled():
            return JSONResponse(
                status_code=401,
                content={"detail": "Bearer tokens are disabled; use cookie session"},
            )

        if authorization:
            try:
                parts = authorization.split()

                if len(parts) != 2 or parts[0].lower() != "bearer":
                    raise ValueError("Invalid authorization header")

                token = parts[1]

            except ValueError:
                return JSONResponse(
                    status_code=401,
                    content={"detail": "Invalid authorization header"},
                )

        if not token:
            return JSONResponse(
                status_code=401,
                content={"detail": "Authorization header missing"},
            )

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
                issuer=jwt_config.JWT_ISSUER,
                audience=jwt_config.JWT_AUDIENCE,
            )

            if payload.get("type") != "access":
                return JSONResponse(
                    status_code=401,
                    content={"detail": "Invalid token type"},
                )

            jti = payload.get("jti")
            if jti and is_token_revoked(jti):
                return JSONResponse(
                    status_code=401,
                    content={"detail": "Token revoked"},
                )

            request.state.user = payload

        except ExpiredSignatureError:
            return JSONResponse(
                status_code=401,
                content={"detail": "Token expired"},
            )

        except PyJWTError:
            return JSONResponse(
                status_code=401,
                content={"detail": "Invalid token"},
            )

        return await call_next(request)
