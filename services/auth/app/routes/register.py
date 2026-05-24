from fastapi import APIRouter
from app.models.user_model import User

router = APIRouter()


@router.post("/register")
def register(user: User):

    return {
        "message": "User registered successfully",
        "user": user
    }