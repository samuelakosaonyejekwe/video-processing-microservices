import os
import time

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from app.config import APP_ENV
from app.jwt.revocation import refresh_token_ttl_seconds
from app.jwt.token import (
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
)
from shared.security.token_revocation import (
    claim_refresh_token_use,
    get_stored_refresh_jti,
    is_token_revoked,
    revoke_token,
    store_refresh_token,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


class RefreshRequest(BaseModel):

    refresh_token: str


@router.post("/refresh")
async def refresh_token(body: RefreshRequest):

    payload = verify_refresh_token(body.refresh_token)

    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token"
        )

    user_id = payload.get("sub")
    role = payload.get("role", "user")
    refresh_jti = payload.get("jti")
    expires_at = payload.get("exp")

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token"
        )

    if refresh_jti and is_token_revoked(refresh_jti):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has been revoked",
        )

    refresh_binding_required = APP_ENV == "production" and bool(
        os.getenv("REDIS_HOST", "").strip()
    )
    stored_jti = get_stored_refresh_jti(str(user_id))
    if refresh_binding_required:
        if not stored_jti or not refresh_jti or stored_jti != refresh_jti:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token has been revoked",
            )
    elif stored_jti and refresh_jti and stored_jti != refresh_jti:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has been revoked",
        )

    if refresh_jti and expires_at:
        # Integer TTL: Redis SETEX rejects floats (time.time() is a float), and
        # the resulting error would silently skip revocation.
        ttl_seconds = max(int(expires_at) - int(time.time()), 1)
        # Single-use rotation: the first request to present this jti wins; a
        # concurrent replay of the same refresh token is rejected.
        if not claim_refresh_token_use(refresh_jti, ttl_seconds):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token has already been used",
            )
        revoke_token(refresh_jti, ttl_seconds)

    new_access_token = create_access_token(
        user_id=user_id,
        role=role,
    )

    new_refresh_token = create_refresh_token(
        user_id=user_id,
        role=role,
    )

    new_payload = verify_refresh_token(new_refresh_token)
    if new_payload and new_payload.get("jti"):
        store_refresh_token(
            str(user_id),
            new_payload["jti"],
            refresh_token_ttl_seconds(),
        )

    return {
        "access_token": new_access_token,
        "refresh_token": new_refresh_token,
        "token_type": "bearer",
    }
