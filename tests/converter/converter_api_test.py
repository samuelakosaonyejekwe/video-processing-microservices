import os
import requests

BASE_URL = os.getenv("CONVERTER_SERVICE_URL") or (
    f"http://{os.getenv('CONVERTER_HOST', 'localhost')}:{os.getenv('CONVERTER_PORT', '8001')}"
)


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