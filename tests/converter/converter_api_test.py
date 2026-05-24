import requests

BASE_URL = "http://localhost:8002"


def test_converter_root():

    response = requests.get(
        f"{BASE_URL}/"
    )

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

    response = requests.post(
        f"{BASE_URL}/convert",
        files=files
    )

    assert response.status_code == 200

    assert "Conversion job queued" in response.text