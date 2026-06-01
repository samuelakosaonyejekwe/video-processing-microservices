import os

import jwt
import httpx
from jwt.exceptions import PyJWTError
from shared.http.internal_client import internal_http_client
from shared.http.upstream_errors import upstream_error_detail
from shared.security.client_ip import get_client_ip
from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from app.config import (
    APP_ENV,
    JWT_ALGORITHM,
    JWT_AUDIENCE,
    JWT_AUTH_SERVICE_URL,
    JWT_ISSUER,
    JWT_PUBLIC_KEY,
)

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
async def _post_auth(
    path: str,
    json_data: dict,
    headers: dict | None = None,
    *,
    request: Request | None = None,
) -> httpx.Response:
    outbound_headers = dict(headers or {})
    if request is not None:
        client_ip = get_client_ip(request)
        if client_ip and client_ip != "unknown":
            outbound_headers.setdefault("X-Forwarded-For", client_ip)

    async with internal_http_client() as client:
        return await client.post(
            f"{JWT_AUTH_SERVICE_URL}{path}",
            json=json_data,
            headers=outbound_headers,
        )


def _raise_upstream_error(response: httpx.Response, default: str) -> None:
    raise HTTPException(
        status_code=response.status_code,
        detail=upstream_error_detail(response, default),
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
    response.delete_cookie(ACCESS_COOKIE, path="/")
    response.delete_cookie(REFRESH_COOKIE, path="/")


def _cookie_auth_response(email: str | None = None) -> JSONResponse:
    content = {"message": "Authenticated", "token_type": "cookie"}
    if email:
        content["email"] = email
    return JSONResponse(content=content)


@router.get("/session")
async def session(request: Request):
    token = request.cookies.get(ACCESS_COOKIE)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    try:
        payload = jwt.decode(
            token,
            JWT_PUBLIC_KEY,
            algorithms=[JWT_ALGORITHM],
            issuer=JWT_ISSUER,
            audience=JWT_AUDIENCE,
        )
    except PyJWTError as error:
        raise HTTPException(status_code=401, detail="Not authenticated") from error

    if payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="Not authenticated")

    return {
        "authenticated": True,
        "user_id": payload.get("sub"),
    }


@router.post("/login")
async def login(data: LoginRequest, request: Request):
    try:
        response = await _post_auth(
            "/auth/login",
            data.model_dump(),
            request=request,
        )
    except (httpx.ConnectError, httpx.ReadTimeout) as error:
        raise HTTPException(
            status_code=503, detail="Auth service unavailable"
        ) from error
    except httpx.HTTPError as error:
        raise HTTPException(
            status_code=503, detail="Auth service unavailable"
        ) from error

    if response.status_code != 200:
        _raise_upstream_error(response, "Login failed")

    payload = response.json()
    json_response = _cookie_auth_response(str(data.email))
    _apply_auth_cookies(json_response, payload)
    return json_response


@router.post("/register")
async def register(data: RegisterRequest, request: Request):
    try:
        response = await _post_auth(
            "/auth/register",
            data.model_dump(),
            request=request,
        )
    except (httpx.ConnectError, httpx.ReadTimeout) as error:
        raise HTTPException(
            status_code=503, detail="Auth service unavailable"
        ) from error
    except httpx.HTTPError as error:
        raise HTTPException(
            status_code=503, detail="Auth service unavailable"
        ) from error

    if response.status_code not in (200, 201):
        _raise_upstream_error(response, "Registration failed")

    return response.json()


@router.post("/refresh")
async def refresh(data: RefreshRequest, request: Request):
    refresh_token = data.refresh_token or request.cookies.get(REFRESH_COOKIE)
    if not refresh_token:
        raise HTTPException(status_code=401, detail="Refresh token missing")

    try:
        response = await _post_auth(
            "/auth/refresh",
            {"refresh_token": refresh_token},
            request=request,
        )
    except (httpx.ConnectError, httpx.ReadTimeout) as error:
        raise HTTPException(
            status_code=503, detail="Auth service unavailable"
        ) from error
    except httpx.HTTPError as error:
        raise HTTPException(
            status_code=503, detail="Auth service unavailable"
        ) from error

    if response.status_code != 200:
        _raise_upstream_error(response, "Refresh failed")

    payload = response.json()
    json_response = _cookie_auth_response()
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

    refresh_token = request.cookies.get(REFRESH_COOKIE)
    logout_body = {"refresh_token": refresh_token} if refresh_token else {}

    try:
        async with internal_http_client() as client:
            response = await client.post(
                f"{JWT_AUTH_SERVICE_URL}/auth/logout",
                headers={"Authorization": authorization},
                json=logout_body,
            )
    except (httpx.ConnectError, httpx.ReadTimeout):
        response = JSONResponse(content={"detail": "Logged out"})
        _clear_auth_cookies(response)
        return response

    if response.status_code != 200:
        _raise_upstream_error(response, "Logout failed")

    json_response = JSONResponse(content=response.json())
    _clear_auth_cookies(json_response)
    return json_response
