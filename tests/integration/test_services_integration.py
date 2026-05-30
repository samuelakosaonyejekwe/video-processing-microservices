import os

import requests


def test_gateway_health():

    gateway_url = os.getenv(
        "GATEWAY_BASE_URL"
    ) or f"http://{os.getenv('GATEWAY_HOST', 'localhost')}:{os.getenv('GATEWAY_PORT', '8080')}"

    response = requests.get(
        f"{gateway_url}/health"
    )

    assert response.status_code == 200


def test_auth_health():

    auth_url = os.getenv(
        "AUTH_BASE_URL"
    ) or f"http://{os.getenv('AUTH_HOST', 'localhost')}:{os.getenv('AUTH_PORT', '8000')}"

    response = requests.get(
        f"{auth_url}/health"
    )

    assert response.status_code == 200


def test_converter_health():

    converter_url = os.getenv(
        "CONVERTER_BASE_URL"
    ) or f"http://{os.getenv('CONVERTER_HOST', 'localhost')}:{os.getenv('CONVERTER_PORT', '8002')}"

    response = requests.get(
        f"{converter_url}/health"
    )

    assert response.status_code == 200


def test_auth_and_gateway_jwt_config_match():

    gateway_url = os.getenv("GATEWAY_BASE_URL", "http://localhost:8080")
    auth_url = os.getenv("AUTH_BASE_URL", "http://localhost:8000")

    auth_jwt = requests.get(f"{auth_url}/health/jwt", timeout=15).json()
    gateway_jwt = requests.get(f"{gateway_url}/health/jwt", timeout=15).json()

    assert auth_jwt["private_key_loaded"] is True
    assert auth_jwt["public_key_loaded"] is True
    assert gateway_jwt["public_key_loaded"] is True
    assert auth_jwt["algorithm"] == gateway_jwt["algorithm"] == "RS256"
    assert auth_jwt["issuer"] == gateway_jwt["issuer"]
    assert auth_jwt["audience"] == gateway_jwt["audience"]
    assert auth_jwt["public_key_fingerprint"] == gateway_jwt["public_key_fingerprint"]