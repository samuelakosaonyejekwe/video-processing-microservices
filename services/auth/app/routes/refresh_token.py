from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from app.jwt.token import (
    create_access_token,
    create_refresh_token,
    verify_refresh_token
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


class RefreshRequest(BaseModel):

    refresh_token: str


@router.post("/refresh")
async def refresh_token(body: RefreshRequest):

    payload = verify_refresh_token(body.refresh_token)

    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )

    user_id = payload.get("sub")
    role = payload.get("role", "user")

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )

    new_access_token = create_access_token(
        user_id=user_id,
        role=role
    )

    new_refresh_token = create_refresh_token(
        user_id=user_id,
        role=role
    )

    return {
        "access_token": new_access_token,
        "refresh_token": new_refresh_token,
        "token_type": "bearer"
    }
