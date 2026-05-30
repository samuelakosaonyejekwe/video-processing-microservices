from jose import jwt, JWTError
from fastapi import HTTPException


def validate_jwt(
    token: str,
    public_key: str,
    issuer: str,
    audience: str,
    algorithm: str = "RS256",
):

    try:
        payload = jwt.decode(
            token,
            public_key,
            algorithms=[algorithm],
            issuer=issuer,
            audience=audience,
        )

        return payload

    except JWTError as exc:
        raise HTTPException(
            status_code=401,
            detail="Invalid token",
        ) from exc
