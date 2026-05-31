from typing import Any


def upstream_error_detail(response, default: str = "Upstream request failed") -> str:
    try:
        body: Any = response.json()
    except ValueError:
        text = (response.text or "").strip()
        return text[:200] if text else default

    if isinstance(body, dict):
        detail = body.get("detail")
        if isinstance(detail, str) and detail:
            return detail
        if isinstance(detail, list) and detail:
            return str(detail[0])

        error = body.get("error")
        if isinstance(error, dict):
            message = error.get("message")
            if isinstance(message, str) and message:
                return message

        message = body.get("message")
        if isinstance(message, str) and message:
            return message

    return default
