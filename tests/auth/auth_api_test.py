import os
import uuid
import requests

BASE_URL = os.getenv("AUTH_SERVICE_URL") or (
    f"http://{os.getenv('AUTH_HOST', 'localhost')}:{os.getenv('AUTH_PORT', '8000')}"
)


def generate_test_user():

    unique_id = uuid.uuid4().hex[:8]
    _base_email = os.getenv("E2E_TEST_EMAIL", "")
    if _base_email and "@" in _base_email:
        _local, _domain = _base_email.split("@", 1)
        email = f"{_local}+test-{unique_id}@{_domain}"
    else:
        email = f"testuser_{unique_id}@example.com"

    return {
        "username": f"testuser_{unique_id}",
        "email": email,
        "password": os.getenv("TEST_USER_PASSWORD", "TestPass123"),
    }


def test_auth_root():

    response = requests.get(f"{BASE_URL}/", timeout=10)

    assert response.status_code == 200

    assert response.json() == {"message": "Auth Service Running"}


def test_register():

    payload = generate_test_user()

    response = requests.post(f"{BASE_URL}/auth/register", json=payload, timeout=10)

    assert response.status_code in [200, 201]

    response_data = response.json()

    assert response_data is not None


def test_login():

    test_user = generate_test_user()

    register_response = requests.post(
        f"{BASE_URL}/auth/register", json=test_user, timeout=10
    )

    assert register_response.status_code in [200, 201]

    login_payload = {"email": test_user["email"], "password": test_user["password"]}

    login_response = requests.post(
        f"{BASE_URL}/auth/login", json=login_payload, timeout=10
    )

    assert login_response.status_code == 200

    response_data = login_response.json()

    assert "access_token" in response_data

    assert response_data["access_token"] is not None
