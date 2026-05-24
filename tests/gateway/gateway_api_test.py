import requests

BASE_URL = "http://localhost:8000"


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