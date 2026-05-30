from pydantic import BaseModel


class Role(BaseModel):

    role_name: str
