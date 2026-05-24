import requests

BASE_URL = "http://localhost:8001"


def test_auth_root():

    response = requests.get(
        f"{BASE_URL}/"
    )

    assert response.status_code == 200

    assert response.json() == {
        "message": "Auth Service Running"
    }


def test_register():

    payload = {
        "username": "testuser",
        "email": "testuser@example.com",
        "password": "password123"
    }

    response = requests.post(
        f"{BASE_URL}/auth/register",
        json=payload
    )

    assert response.status_code == 200


def test_login():

    payload = {
        "email": "admin@example.com",
        "password": "password123"
    }

    response = requests.post(
        f"{BASE_URL}/auth/login",
        json=payload
    )

    assert response.status_code == 200

    assert "access_token" in response.json()