import os
from typing import Any

import jwt
from jwt.exceptions import PyJWTError


def decode_access_token(token: str) -> dict[str, Any] | None:
    public_key = os.getenv("JWT_PUBLIC_KEY", "").strip()
    secret = os.getenv("JWT_SECRET", "").strip()
    algorithm = os.getenv("JWT_ALGORITHM", "RS256").strip()

    if algorithm.startswith("RS") and not public_key:
        return None
    if not algorithm.startswith("RS") and not secret:
        return None

    decode_key = public_key if algorithm.startswith("RS") else secret
    options = {}
    decode_kwargs: dict[str, Any] = {"algorithms": [algorithm]}
    if algorithm.startswith("RS"):
        decode_kwargs["issuer"] = os.getenv("JWT_ISSUER")
        decode_kwargs["audience"] = os.getenv("JWT_AUDIENCE")
    else:
        options["verify_aud"] = False

    try:
        return jwt.decode(token, decode_key, options=options, **decode_kwargs)
    except PyJWTError:
        return None


def access_token_from_cookie_header(cookie_header: str | None) -> str | None:
    if not cookie_header:
        return None

    for part in cookie_header.split(";"):
        name, _, value = part.strip().partition("=")
        if name == "access_token" and value:
            return value
    return None
