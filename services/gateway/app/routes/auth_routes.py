import os

import httpx
from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from app.config import APP_ENV, JWT_AUTH_SERVICE_URL

router = APIRouter(prefix="/auth", tags=["Authentication"])

ACCESS_COOKIE = "access_token"
REFRESH_COOKIE = "refresh_token"
COOKIE_SECURE = APP_ENV == "production"


class LoginRequest(BaseModel):

    email: EmailStr

    password: str


class RegisterRequest(BaseModel):

    username: str

    email: EmailStr

    password: str


class RefreshRequest(BaseModel):

    refresh_token: str | None = None


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=0.5, min=0.5, max=4),
    retry=retry_if_exception_type((httpx.ConnectError, httpx.ReadTimeout)),
    reraise=True,
)
async def _post_auth(path: str, json_data: dict, headers: dict | None = None) -> httpx.Response:
    async with httpx.AsyncClient(timeout=30.0) as client:
        return await client.post(
            f"{JWT_AUTH_SERVICE_URL}{path}",
            json=json_data,
            headers=headers or {},
        )


def _apply_auth_cookies(response: JSONResponse, tokens: dict) -> None:
    access_token = tokens.get("access_token")
    refresh_token = tokens.get("refresh_token")

    if access_token:
        response.set_cookie(
            key=ACCESS_COOKIE,
            value=access_token,
            httponly=True,
            secure=COOKIE_SECURE,
            samesite="strict",
            max_age=int(os.getenv("ACCESS_TOKEN_COOKIE_MAX_AGE", "3600")),
        )

    if refresh_token:
        response.set_cookie(
            key=REFRESH_COOKIE,
            value=refresh_token,
            httponly=True,
            secure=COOKIE_SECURE,
            samesite="strict",
            max_age=int(os.getenv("REFRESH_TOKEN_COOKIE_MAX_AGE", str(7 * 24 * 3600))),
        )


def _clear_auth_cookies(response: Response) -> None:
    response.delete_cookie(ACCESS_COOKIE)
    response.delete_cookie(REFRESH_COOKIE)


@router.post("/login")
async def login(data: LoginRequest):
    try:
        response = await _post_auth("/auth/login", data.model_dump())
    except (httpx.ConnectError, httpx.ReadTimeout) as error:
        raise HTTPException(status_code=503, detail="Auth service unavailable") from error

    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail=response.json().get("detail", "Login failed"),
        )

    payload = response.json()
    json_response = JSONResponse(content=payload)
    _apply_auth_cookies(json_response, payload)
    return json_response


@router.post("/register")
async def register(data: RegisterRequest):
    try:
        response = await _post_auth("/auth/register", data.model_dump())
    except (httpx.ConnectError, httpx.ReadTimeout) as error:
        raise HTTPException(status_code=503, detail="Auth service unavailable") from error

    if response.status_code not in (200, 201):
        raise HTTPException(
            status_code=response.status_code,
            detail=response.json().get("detail", "Registration failed"),
        )

    return response.json()


@router.post("/refresh")
async def refresh(data: RefreshRequest, request: Request):
    refresh_token = data.refresh_token or request.cookies.get(REFRESH_COOKIE)
    if not refresh_token:
        raise HTTPException(status_code=401, detail="Refresh token missing")

    try:
        response = await _post_auth("/auth/refresh", {"refresh_token": refresh_token})
    except (httpx.ConnectError, httpx.ReadTimeout) as error:
        raise HTTPException(status_code=503, detail="Auth service unavailable") from error

    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail=response.json().get("detail", "Refresh failed"),
        )

    payload = response.json()
    json_response = JSONResponse(content=payload)
    _apply_auth_cookies(json_response, payload)
    return json_response


@router.post("/logout")
async def logout(request: Request):
    authorization = request.headers.get("Authorization")
    cookie_token = request.cookies.get(ACCESS_COOKIE)

    if not authorization and cookie_token:
        authorization = f"Bearer {cookie_token}"

    if not authorization:
        response = JSONResponse(content={"detail": "Logged out"})
        _clear_auth_cookies(response)
        return response

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{JWT_AUTH_SERVICE_URL}/auth/logout",
                headers={"Authorization": authorization},
            )
    except (httpx.ConnectError, httpx.ReadTimeout):
        response = JSONResponse(content={"detail": "Logged out"})
        _clear_auth_cookies(response)
        return response

    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail=response.json().get("detail", "Logout failed"),
        )

    json_response = JSONResponse(content=response.json())
    _clear_auth_cookies(json_response)
    return json_response
