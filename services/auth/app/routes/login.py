from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class LoginRequest(BaseModel):

    email: str

    password: str


@router.post("/login")
def login(data: LoginRequest):

    if data.email == "admin@example.com" and data.password == "password123":

        return {
            "access_token": "sample-jwt-token",
            "token_type": "bearer"
        }

    raise HTTPException(
        status_code=401,
        detail="Invalid credentials"
    )