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
    ) or f"http://{os.getenv('CONVERTER_HOST', 'localhost')}:{os.getenv('CONVERTER_PORT', '8001')}"

    response = requests.get(
        f"{converter_url}/health"
    )

    assert response.status_code == 200