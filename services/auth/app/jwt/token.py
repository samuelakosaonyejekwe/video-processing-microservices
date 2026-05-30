import uuid
import hashlib

from datetime import datetime
from datetime import timedelta
from datetime import timezone

from typing import Optional
from typing import Dict
from typing import Any

from jose import jwt
from jose import JWTError
from jose import ExpiredSignatureError

from app.config import (
    JWT_PRIVATE_KEY,
    JWT_PUBLIC_KEY,
    JWT_ACTIVE_KID,
    JWT_ISSUER,
    JWT_AUDIENCE,
    JWT_ALGORITHM,
    JWT_ACCESS_TOKEN_EXPIRES_MINUTES,
    JWT_REFRESH_TOKEN_EXPIRES_DAYS,
)

# =========================================================
# TOKEN ID GENERATION
# =========================================================


def generate_refresh_token_id() -> str:

    return str(uuid.uuid4())


# =========================================================
# TOKEN HASHING
# =========================================================


def hash_refresh_token(token: str) -> str:

    return hashlib.sha256(token.encode()).hexdigest()


# =========================================================
# ACCESS TOKEN CREATION
# =========================================================


def create_access_token(user_id: str, role: str) -> str:

    now = datetime.now(timezone.utc)

    expire = now + timedelta(minutes=JWT_ACCESS_TOKEN_EXPIRES_MINUTES)

    payload = {
        "sub": str(user_id),
        "type": "access",
        "role": role,
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
        "iat": now,
        "exp": expire,
        "jti": str(uuid.uuid4()),
    }

    encoded_jwt = jwt.encode(
        payload,
        JWT_PRIVATE_KEY,
        algorithm=JWT_ALGORITHM,
        headers={"kid": JWT_ACTIVE_KID},
    )

    return encoded_jwt


# =========================================================
# REFRESH TOKEN CREATION
# =========================================================


def create_refresh_token(user_id: str, role: str) -> str:

    now = datetime.now(timezone.utc)

    expire = now + timedelta(days=JWT_REFRESH_TOKEN_EXPIRES_DAYS)

    refresh_payload = {
        "sub": str(user_id),
        "type": "refresh",
        "role": role,
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
        "iat": now,
        "exp": expire,
        "jti": generate_refresh_token_id(),
    }

    refresh_token = jwt.encode(
        refresh_payload,
        JWT_PRIVATE_KEY,
        algorithm=JWT_ALGORITHM,
        headers={"kid": JWT_ACTIVE_KID},
    )

    return refresh_token


# =========================================================
# ACCESS TOKEN VERIFICATION
# =========================================================


def verify_access_token(token: str) -> Optional[Dict[str, Any]]:

    try:

        payload = jwt.decode(
            token,
            JWT_PUBLIC_KEY,
            algorithms=[JWT_ALGORITHM],
            issuer=JWT_ISSUER,
            audience=JWT_AUDIENCE,
        )

        if payload.get("type") != "access":

            return None

        return payload

    except ExpiredSignatureError:

        return None

    except JWTError:

        return None


# =========================================================
# REFRESH TOKEN VERIFICATION
# =========================================================


def verify_refresh_token(token: str) -> Optional[Dict[str, Any]]:

    try:

        payload = jwt.decode(
            token,
            JWT_PUBLIC_KEY,
            algorithms=[JWT_ALGORITHM],
            issuer=JWT_ISSUER,
            audience=JWT_AUDIENCE,
        )

        if payload.get("type") != "refresh":

            return None

        return payload

    except ExpiredSignatureError:

        return None

    except JWTError:

        return None
