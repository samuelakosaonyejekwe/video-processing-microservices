import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, EmailStr

from app.config import JWT_AUTH_SERVICE_URL

router = APIRouter(prefix="/auth", tags=["Authentication"])


class LoginRequest(BaseModel):

    email: EmailStr

    password: str


class RegisterRequest(BaseModel):

    username: str

    email: EmailStr

    password: str


class RefreshRequest(BaseModel):

    refresh_token: str


@router.post("/login")
async def login(data: LoginRequest):

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{JWT_AUTH_SERVICE_URL}/auth/login",
            json=data.model_dump(),
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail=response.json().get("detail", "Login failed"),
        )

    return response.json()


@router.post("/register")
async def register(data: RegisterRequest):

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{JWT_AUTH_SERVICE_URL}/auth/register",
            json=data.model_dump(),
        )

    if response.status_code not in (200, 201):
        raise HTTPException(
            status_code=response.status_code,
            detail=response.json().get("detail", "Registration failed"),
        )

    return response.json()


@router.post("/refresh")
async def refresh(data: RefreshRequest):

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{JWT_AUTH_SERVICE_URL}/auth/refresh",
            json=data.model_dump(),
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail=response.json().get("detail", "Refresh failed"),
        )

    return response.json()


@router.post("/logout")
async def logout(request: Request):

    authorization = request.headers.get("Authorization")

    if not authorization:
        raise HTTPException(status_code=401, detail="Not authenticated")

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{JWT_AUTH_SERVICE_URL}/auth/logout",
            headers={"Authorization": authorization},
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail=response.json().get("detail", "Logout failed"),
        )

    return response.json()
