import os


def normalize_pem(value: str) -> str:
    normalized = value.strip()
    if "\\n" in normalized:
        normalized = normalized.replace("\\n", "\n")
    return normalized


def load_pem(env_name: str, file_path: str = "") -> str:
    if file_path and os.path.exists(file_path):
        with open(file_path, encoding="utf-8") as pem_file:
            file_value = pem_file.read().strip()
            if file_value:
                return normalize_pem(file_value)

    value = os.getenv(env_name, "")
    if value and value.strip():
        return normalize_pem(value)

    return ""
