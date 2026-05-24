from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_root():

    response = client.get("/")

    assert response.status_code == 200

    assert response.json() == {
        "message": "Auth Service Running"
    }


def test_register():

    payload = {
        "username": "testuser",
        "email": "testuser@example.com",
        "password": "password123!"
    }

    response = client.post(
        "/auth/register",
        json=payload
    )

    assert response.status_code == 200


def test_login():

    payload = {
        "email": "testuser@example.com",
        "password": "password123!"
    }

    response = client.post(
        "/auth/login",
        json=payload
    )

    assert response.status_code == 200

    assert "access_token" in response.json()