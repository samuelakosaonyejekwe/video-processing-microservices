from fastapi import Request
from fastapi.responses import JSONResponse

from starlette.middleware.base import BaseHTTPMiddleware

import jwt
from jwt.exceptions import ExpiredSignatureError, PyJWTError

from shared.security.token_revocation import is_token_revoked


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
            "/metrics",
        ]

        if request.url.path in public_routes:
            return await call_next(request)

        authorization = request.headers.get("Authorization")

        if not authorization:
            return JSONResponse(
                status_code=401,
                content={"detail": "Authorization header missing"},
            )

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
                audience=(
                    jwt_config.JWT_AUDIENCE if algorithm.startswith("RS") else None
                ),
            )

            token_type = payload.get("type")

            if token_type and token_type != "access":
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
