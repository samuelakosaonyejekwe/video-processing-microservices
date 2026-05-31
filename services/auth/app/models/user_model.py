import re

from pydantic import BaseModel, EmailStr, Field, field_validator

PASSWORD_PATTERN = re.compile(r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,128}$")


class User(BaseModel):

    username: str = Field(min_length=3, max_length=100)

    email: EmailStr

    password: str = Field(min_length=8, max_length=128)

    @field_validator("password")
    @classmethod
    def validate_password_strength(cls, value: str) -> str:
        if not PASSWORD_PATTERN.match(value):
            raise ValueError(
                "Password must be 8-128 characters and include upper, lower, and a digit"
            )
        return value
