from fastapi import APIRouter, HTTPException, status
from passlib.context import CryptContext
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database.connection import SessionLocal
from app.models.user_entity import UserEntity
from app.models.user_model import User

router = APIRouter(prefix="/auth", tags=["Authentication"])

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(user: User):

    db: Session = SessionLocal()

    try:
        existing = db.query(UserEntity).filter(
            UserEntity.email == user.email
        ).first()

        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered"
            )

        db_user = UserEntity(
            username=user.username,
            email=user.email,
            password=pwd_context.hash(user.password),
            role="user"
        )

        db.add(db_user)
        db.commit()
        db.refresh(db_user)

        return {
            "message": "User registered successfully",
            "user": {
                "id": db_user.id,
                "username": db_user.username,
                "email": db_user.email
            }
        }

    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already exists"
        ) from exc

    finally:
        db.close()
