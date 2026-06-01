import time

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.jwt.auth_guard import verify_token
from app.jwt.token import verify_refresh_token
from shared.security.token_revocation import (
    invalidate_refresh_token,
    revoke_token,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


class LogoutRequest(BaseModel):
    refresh_token: str | None = None


@router.post("/logout")
async def logout(
    body: LogoutRequest = LogoutRequest(),
    payload: dict = Depends(verify_token),
):

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

        if body.refresh_token:
            refresh_payload = verify_refresh_token(body.refresh_token)
            if refresh_payload:
                refresh_jti = refresh_payload.get("jti")
                refresh_exp = refresh_payload.get("exp")
                refresh_user_id = refresh_payload.get("sub")
                if refresh_user_id and str(refresh_user_id) != str(user_id):
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Refresh token does not match access token",
                    )
                if refresh_jti and refresh_exp:
                    refresh_ttl = max(int(refresh_exp) - int(time.time()), 1)
                    revoke_token(refresh_jti, refresh_ttl)

        invalidate_refresh_token(str(user_id))

        return {
            "success": True,
            "message": "Logout successful",
        }

    except HTTPException:

        raise

    except Exception as exc:

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Logout failed"
        ) from exc
