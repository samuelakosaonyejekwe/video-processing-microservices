from datetime import datetime

from pydantic import BaseModel


class RevokedToken(BaseModel):

    jti: str

    revoked_at: datetime

    expires_at: datetime
