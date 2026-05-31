import time

from fastapi import APIRouter, Depends, HTTPException, status

from app.jwt.auth_guard import verify_token
from app.jwt.revocation import refresh_token_ttl_seconds
from shared.security.token_revocation import (
    invalidate_refresh_token,
    revoke_token,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/logout")
async def logout(payload: dict = Depends(verify_token)):

    try:

        user_id = payload.get("sub")

        jti = payload.get("jti")

        token_type = payload.get("type")

        expires_at = payload.get("exp")

        if not user_id:

            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload"
            )

        if token_type != "access":

            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type"
            )

        if jti and expires_at:
            ttl_seconds = max(int(expires_at) - int(time.time()), 1)
            revoke_token(jti, ttl_seconds)

        invalidate_refresh_token(str(user_id))

        return {
            "success": True,
            "message": "Logout successful",
            "user_id": user_id,
            "revoked_token_id": jti,
        }

    except HTTPException:

        raise

    except Exception as exc:

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Logout failed"
        ) from exc
