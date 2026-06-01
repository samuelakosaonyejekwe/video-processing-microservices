import base64
import os

import jwt
from jwt.exceptions import PyJWTError


def normalize_pem(value: str) -> str:
    normalized = value.strip().replace("\r\n", "\n").replace("\r", "\n")
    if "\\n" in normalized:
        normalized = normalized.replace("\\n", "\n")
    return normalized


def _decode_pem_value(value: str) -> str:
    normalized = normalize_pem(value)
    if "BEGIN" in normalized:
        return normalized

    try:
        decoded = base64.b64decode(normalized, validate=True).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return normalized

    return normalize_pem(decoded)


def load_pem(env_name: str, file_path: str = "") -> str:
    if file_path and os.path.exists(file_path):
        with open(file_path, encoding="utf-8") as pem_file:
            file_value = pem_file.read().strip()
            if file_value:
                return _decode_pem_value(file_value)

    value = os.getenv(env_name, "")
    if value and value.strip():
        return _decode_pem_value(value)

    return ""


def verify_rsa_key_pair(private_key: str, public_key: str) -> bool:
    if not private_key or not public_key:
        return False

    try:
        token = jwt.encode({"healthcheck": "1"}, private_key, algorithm="RS256")
        jwt.decode(token, public_key, algorithms=["RS256"])
        return True
    except (PyJWTError, ValueError, TypeError):
        return False
