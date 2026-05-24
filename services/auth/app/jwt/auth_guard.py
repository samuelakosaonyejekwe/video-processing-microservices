from fastapi import Header, HTTPException
from app.jwt.token import verify_access_token


def auth_guard(authorization: str = Header(None)):

    if authorization is None:

        raise HTTPException(
            status_code=401,
            detail="Authorization header missing"
        )

    try:

        token = authorization.split(" ")[1]

        payload = verify_access_token(token)

        return payload

    except Exception:

        raise HTTPException(
            status_code=401,
            detail="Invalid or expired token"
        )