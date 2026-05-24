from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_root():

    response = client.get("/")

    assert response.status_code == 200

    assert response.json() == {
        "message": "Converter Service Running"
    }


def test_convert_endpoint():

    files = {
        "file": (
            "sample.mp4",
            b"fake-video-content",
            "video/mp4"
        )
    }

    response = client.post(
        "/convert",
        files=files
    )

    assert response.status_code == 200

    assert "Conversion job queued" in response.text