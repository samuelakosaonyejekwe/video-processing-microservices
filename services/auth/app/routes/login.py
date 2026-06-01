import logging
import os

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import JSONResponse
from jwt.exceptions import PyJWTError
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.config import (
    JWT_ACCESS_TOKEN_EXPIRES_MINUTES,
    JWT_PRIVATE_KEY,
    JWT_PUBLIC_KEY,
)
from app.database.connection import SessionLocal
from app.jwt.revocation import refresh_token_ttl_seconds
from app.jwt.token import (
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
)
from app.models.user_entity import UserEntity
from shared.security.token_revocation import store_refresh_token

router = APIRouter(prefix="/auth", tags=["Authentication"])
logger = logging.getLogger(__name__)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Pre-computed hash used to perform a constant-time-ish bcrypt verification even
# when the email does not exist, so response latency does not reveal whether an
# account is registered (user-enumeration timing oracle).
_DUMMY_PASSWORD_HASH = pwd_context.hash("dummy-password-for-timing-equalization")

_APP_ENV = os.getenv("APP_ENV", "production")
_COOKIE_SECURE = _APP_ENV == "production"
_ACCESS_COOKIE_MAX_AGE = JWT_ACCESS_TOKEN_EXPIRES_MINUTES * 60


class LoginRequest(BaseModel):

    email: EmailStr

    password: str


@router.post("/login")
def login(data: LoginRequest):

    if not JWT_PRIVATE_KEY or not JWT_PUBLIC_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service misconfigured",
        )

    db: Session = SessionLocal()

    try:
        user = db.query(UserEntity).filter(UserEntity.email == data.email).first()

        # Always run a bcrypt verification (against a dummy hash when the user is
        # unknown) so timing does not leak whether the email is registered.
        password_hash = user.password if user else _DUMMY_PASSWORD_HASH
        password_ok = pwd_context.verify(data.password, password_hash)

        if not user or not password_ok:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials"
            )

        access_token = create_access_token(
            user_id=str(user.id),
            role=user.role,
        )

        refresh_token = create_refresh_token(
            user_id=str(user.id),
            role=user.role,
        )

        refresh_payload = verify_refresh_token(refresh_token)
        if refresh_payload and refresh_payload.get("jti"):
            store_refresh_token(
                str(user.id),
                refresh_payload["jti"],
                refresh_token_ttl_seconds(),
            )

        response = JSONResponse(
            {
                "access_token": access_token,
                "refresh_token": refresh_token,
                "token_type": "bearer",
            }
        )
        response.set_cookie(
            key="access_token",
            value=access_token,
            httponly=True,
            secure=_COOKIE_SECURE,
            samesite="strict",
            max_age=_ACCESS_COOKIE_MAX_AGE,
        )
        return response

    except HTTPException:
        raise
    except SQLAlchemyError as error:
        logger.exception("Database error during login for email=%s", data.email)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service temporarily unavailable",
        ) from error
    except (PyJWTError, ValueError, TypeError) as error:
        logger.exception(
            "Token generation failed during login for email=%s", data.email
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service temporarily unavailable",
        ) from error
    except Exception as error:
        logger.exception("Unexpected error during login for email=%s", data.email)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Login failed",
        ) from error

    finally:
        db.close()
