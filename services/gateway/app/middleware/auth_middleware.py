from fastapi import Request
from fastapi.responses import JSONResponse

from starlette.middleware.base import BaseHTTPMiddleware

import jwt
from jwt.exceptions import ExpiredSignatureError, PyJWTError

from app.config import (
    JWT_PUBLIC_KEY,
    JWT_SECRET,
    JWT_ISSUER,
    JWT_AUDIENCE,
    JWT_ALGORITHM,
)


class AuthMiddleware(BaseHTTPMiddleware):

    async def dispatch(self, request: Request, call_next):

        public_routes = [
            "/",
            "/docs",
            "/openapi.json",
            "/redoc",
            "/health",
            "/health/",
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
            decode_key = (
                JWT_PUBLIC_KEY
                if JWT_ALGORITHM.startswith("RS")
                else JWT_SECRET
            )

            payload = jwt.decode(
                token,
                decode_key,
                algorithms=[JWT_ALGORITHM],
                issuer=JWT_ISSUER if JWT_ALGORITHM.startswith("RS") else None,
                audience=JWT_AUDIENCE if JWT_ALGORITHM.startswith("RS") else None,
            )

            token_type = payload.get("type")

            if token_type and token_type != "access":
                return JSONResponse(
                    status_code=401,
                    content={"detail": "Invalid token type"},
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
