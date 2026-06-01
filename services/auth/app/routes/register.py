import logging

from fastapi import APIRouter, HTTPException, status
from passlib.context import CryptContext
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.database.connection import SessionLocal
from app.models.user_entity import UserEntity
from app.models.user_model import User

router = APIRouter(prefix="/auth", tags=["Authentication"])
logger = logging.getLogger(__name__)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(user: User):

    db: Session = SessionLocal()

    try:
        existing = db.query(UserEntity).filter(UserEntity.email == user.email).first()

        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail="Email already registered"
            )

        existing_username = (
            db.query(UserEntity).filter(UserEntity.username == user.username).first()
        )

        if existing_username:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Username already taken",
            )

        db_user = UserEntity(
            username=user.username,
            email=user.email,
            password=pwd_context.hash(user.password),
            role="user",
        )

        db.add(db_user)
        db.commit()
        db.refresh(db_user)

        return {
            "message": "User registered successfully",
            "user": {
                "username": db_user.username,
                "email": db_user.email,
            },
        }

    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="User already exists"
        ) from exc

    except SQLAlchemyError as exc:
        # Roll back so a connection with a failed/pending transaction is not
        # returned to the pool, and surface a controlled 503.
        db.rollback()
        logger.exception("Database error during registration")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Registration temporarily unavailable",
        ) from exc

    finally:
        db.close()
