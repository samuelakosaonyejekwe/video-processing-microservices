from fastapi import APIRouter, HTTPException, status
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

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

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class LoginRequest(BaseModel):

    email: EmailStr

    password: str


def get_db():

    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()


@router.post("/login")
def login(data: LoginRequest):

    db: Session = SessionLocal()

    try:
        user = db.query(UserEntity).filter(UserEntity.email == data.email).first()

        if not user or not pwd_context.verify(data.password, user.password):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials"
            )

        access_token = create_access_token(
            user_id=str(user.id),
            role=user.role,
            email=user.email,
        )

        refresh_token = create_refresh_token(
            user_id=str(user.id),
            role=user.role,
            email=user.email,
        )

        refresh_payload = verify_refresh_token(refresh_token)
        if refresh_payload and refresh_payload.get("jti"):
            store_refresh_token(
                str(user.id),
                refresh_payload["jti"],
                refresh_token_ttl_seconds(),
            )

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
        }

    finally:
        db.close()
