from datetime import datetime
from datetime import timezone

from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import status

from app.jwt.auth_guard import verify_token

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)

# =========================================================
# LOGOUT ROUTE
# =========================================================


@router.post(
    "/logout"
)
async def logout(

    payload: dict = Depends(
        verify_token
    )
):

    try:

        user_id = payload.get(
            "sub"
        )

        jti = payload.get(
            "jti"
        )

        token_type = payload.get(
            "type"
        )

        if not user_id:

            raise HTTPException(

                status_code=status.HTTP_401_UNAUTHORIZED,

                detail="Invalid token payload"
            )

        if token_type != "access":

            raise HTTPException(

                status_code=status.HTTP_401_UNAUTHORIZED,

                detail="Invalid token type"
            )

        # =================================================
        # FUTURE TOKEN REVOCATION STORAGE
        # =================================================
        #
        # Store revoked token here later using:
        #
        # - Redis
        # - PostgreSQL
        # - MongoDB
        # - distributed cache
        #
        # Example:
        #
        # revoked_token_service.revoke(
        #     jti=jti,
        #     user_id=user_id
        # )
        #
        # =================================================

        return {

            "success": True,

            "message": "Logout successful",

            "user_id": user_id,

            "revoked_token_id": jti,

            "timestamp": datetime.now(
                timezone.utc
            ).isoformat()
        }

    except HTTPException:

        raise

    except Exception as exc:

        raise HTTPException(

            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,

            detail="Logout failed"

        ) from exc