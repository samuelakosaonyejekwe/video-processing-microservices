import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database.connection import SessionLocal
from app.jwt.auth_guard import verify_token
from app.models.user_entity import UserEntity

router = APIRouter(prefix="/auth", tags=["Authentication"])
logger = logging.getLogger(__name__)


@router.get("/me")
def me(payload: dict = Depends(verify_token)):
    """Resolve the authenticated user's profile from the source of truth.

    Email is intentionally NOT carried in the JWT (PII), so callers that need
    it (e.g. notification dispatch) fetch it here using the access token.
    """
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload"
        )

    try:
        lookup_id = int(user_id)
    except (TypeError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload"
        ) from error

    db: Session = SessionLocal()
    try:
        user = db.query(UserEntity).filter(UserEntity.id == lookup_id).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
            )
        return {
            "user_id": str(user.id),
            "username": user.username,
            "email": user.email,
            "role": user.role,
        }
    except HTTPException:
        raise
    except SQLAlchemyError as error:
        logger.exception("Database error resolving user profile")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service temporarily unavailable",
        ) from error
    finally:
        db.close()
