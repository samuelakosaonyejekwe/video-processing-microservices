from unittest.mock import AsyncMock, Mock, patch

import httpx
import pytest
from fastapi import HTTPException

from app.routes import auth_routes


def test_raise_upstream_error_uses_nested_auth_error():
    response = Mock()
    response.status_code = 401
    response.json.return_value = {
        "error": {"message": "Invalid credentials", "code": "HTTP_401"}
    }

    with pytest.raises(HTTPException) as exc_info:
        auth_routes._raise_upstream_error(response, "Login failed")

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Invalid credentials"


@pytest.mark.asyncio
async def test_post_auth_forwards_client_ip():
    request = Mock()
    request.headers = {}

    with (
        patch(
            "app.routes.auth_routes.get_client_ip",
            return_value="203.0.113.10",
        ),
        patch(
            "app.routes.auth_routes.internal_http_client",
        ) as mock_client_factory,
    ):
        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=httpx.Response(200, json={}))
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None
        mock_client_factory.return_value = mock_client

        await auth_routes._post_auth(
            "/auth/login",
            {"email": "user@example.com", "password": "secret"},
            request=request,
        )

        headers = mock_client.post.await_args.kwargs["headers"]
        assert headers["X-Forwarded-For"] == "203.0.113.10"
