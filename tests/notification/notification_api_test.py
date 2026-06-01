import os
import requests

BASE_URL = os.getenv("NOTIFICATION_SERVICE_URL") or (
    f"http://{os.getenv('NOTIFICATION_HOST', 'localhost')}:{os.getenv('NOTIFICATION_PORT', '8002')}"  # noqa: E501
)


def test_notification_root():

    response = requests.get(f"{BASE_URL}/")

    assert response.status_code == 200

    assert response.json() == {"message": "Notification Service Running"}


def test_notification_health():

    response = requests.get(f"{BASE_URL}/health")

    assert response.status_code == 200

    assert response.json() == {"status": "healthy"}
