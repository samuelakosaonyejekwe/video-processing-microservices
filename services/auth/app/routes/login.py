from fastapi import APIRouter, HTTPException, status
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

from app.database.connection import SessionLocal
from app.jwt.token import create_access_token, create_refresh_token
from app.models.user_entity import UserEntity

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
        user = db.query(UserEntity).filter(
            UserEntity.email == data.email
        ).first()

        if not user or not pwd_context.verify(
            data.password,
            user.password
        ):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials"
            )

        access_token = create_access_token(
            user_id=str(user.id),
            role=user.role
        )

        refresh_token = create_refresh_token(
            user_id=str(user.id),
            role=user.role
        )

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer"
        }

    finally:
        db.close()
