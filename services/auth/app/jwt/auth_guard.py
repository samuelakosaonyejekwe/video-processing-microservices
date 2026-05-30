from fastapi import HTTPException
from fastapi import Depends
from fastapi import status

from fastapi.security import HTTPBearer
from fastapi.security import HTTPAuthorizationCredentials

from jose import jwt
from jose import JWTError
from jose import ExpiredSignatureError

from app.config import JWT_PUBLIC_KEY, JWT_ISSUER, JWT_AUDIENCE, JWT_ALGORITHM

# =========================================================
# SECURITY SCHEME
# =========================================================

security = HTTPBearer()

# =========================================================
# TOKEN REVOCATION CHECK
# =========================================================


async def is_token_revoked(jti: str) -> bool:

    # Replace later with:
    #
    # - Redis lookup
    # - MongoDB lookup
    # - PostgreSQL token table
    # - distributed cache
    #
    # for logout invalidation
    # and token revocation lifecycle

    return False


# =========================================================
# TOKEN VERIFICATION
# =========================================================


async def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):

    token = credentials.credentials

    try:

        payload = jwt.decode(
            token,
            JWT_PUBLIC_KEY,
            algorithms=[JWT_ALGORITHM],
            issuer=JWT_ISSUER,
            audience=JWT_AUDIENCE,
        )

        if payload.get("type") != "access":

            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type"
            )

        if await is_token_revoked(payload["jti"]):

            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Token revoked"
            )

        return payload

    except ExpiredSignatureError as exc:

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired"
        ) from exc

    except JWTError as exc:

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
        ) from exc

    except Exception as exc:

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication failed"
        ) from exc


# =========================================================
# ROLE-BASED ACCESS CONTROL
# =========================================================


def require_roles(*roles):

    def role_checker(user):

        if user.get("role") not in roles:

            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions"
            )

        return user

    return role_checker


# =========================================================
# BACKWARD-COMPATIBILITY GUARD
# =========================================================


async def auth_guard(credentials: HTTPAuthorizationCredentials = Depends(security)):

    return await verify_token(credentials)
