import requests

BASE_URL = "http://localhost:8003"


def test_notification_root():

    response = requests.get(
        f"{BASE_URL}/"
    )

    assert response.status_code == 200

    assert response.json() == {
        "message": "Notification Service Running"
    }


def test_notification_health():

    response = requests.get(
        f"{BASE_URL}/health"
    )

    assert response.status_code == 200

    assert response.json() == {
        "status": "healthy"
    }