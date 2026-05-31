from app.config import JWT_REFRESH_TOKEN_EXPIRES_DAYS
from shared.security.token_revocation import is_token_revoked as _is_token_revoked


async def is_token_revoked(jti: str) -> bool:
    return _is_token_revoked(jti)


def refresh_token_ttl_seconds() -> int:
    return JWT_REFRESH_TOKEN_EXPIRES_DAYS * 24 * 60 * 60
