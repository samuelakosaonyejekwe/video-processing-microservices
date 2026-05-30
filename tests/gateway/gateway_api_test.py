import os
import requests

BASE_URL = os.getenv("GATEWAY_SERVICE_URL") or (
    f"http://{os.getenv('GATEWAY_HOST', 'localhost')}:{os.getenv('GATEWAY_PORT', '8080')}"
)


def test_gateway_root():

    response = requests.get(
        f"{BASE_URL}/"
    )

    assert response.status_code == 200

    assert response.json() == {
        "message": "Gateway Service Running"
    }


def test_gateway_health():

    response = requests.get(
        f"{BASE_URL}/health/"
    )

    assert response.status_code == 200

    assert response.json() == {
        "status": "healthy"
    }