import os

import requests


def test_gateway_health():

    gateway_url = (
        os.getenv("GATEWAY_BASE_URL")
        or f"http://{os.getenv('GATEWAY_HOST', 'localhost')}:{os.getenv('GATEWAY_PORT', '8080')}"  # noqa: E501
    )

    response = requests.get(f"{gateway_url}/health")

    assert response.status_code == 200


def test_auth_health():

    gateway_url = (
        os.getenv("GATEWAY_BASE_URL")
        or os.getenv("AUTH_BASE_URL")
        or f"http://{os.getenv('AUTH_HOST', 'localhost')}:{os.getenv('AUTH_PORT', '8000')}"  # noqa: E501
    )

    response = requests.get(
        f"{gateway_url}/health/jwt",
        timeout=15,
    )

    assert response.status_code == 200
    body = response.json()
    assert body.get("public_key_loaded") is True
    assert body.get("algorithm") == "RS256"


def test_converter_health():

    converter_url = (
        os.getenv("CONVERTER_BASE_URL")
        or f"http://{os.getenv('CONVERTER_HOST', 'localhost')}:{os.getenv('CONVERTER_PORT', '8002')}"  # noqa: E501
    )

    response = requests.get(f"{converter_url}/health")

    assert response.status_code == 200


def test_auth_and_gateway_jwt_config_match():

    gateway_url = os.getenv("GATEWAY_BASE_URL", "http://localhost:8080")

    gateway_jwt = requests.get(f"{gateway_url}/health/jwt", timeout=15).json()

    assert gateway_jwt["public_key_loaded"] is True
    assert gateway_jwt["algorithm"] == "RS256"
    assert gateway_jwt.get("issuer")
    assert gateway_jwt.get("audience")
    assert gateway_jwt.get("public_key_fingerprint")
