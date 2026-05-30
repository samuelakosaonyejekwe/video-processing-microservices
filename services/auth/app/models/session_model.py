from datetime import datetime

from pydantic import BaseModel


class SessionModel(BaseModel):

    user_id: str

    session_id: str

    refresh_token_hash: str

    device_id: str

    ip_address: str

    user_agent: str

    created_at: datetime

    expires_at: datetime
