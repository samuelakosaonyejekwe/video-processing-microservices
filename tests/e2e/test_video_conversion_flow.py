import os

import requests


def test_video_upload_flow():

    gateway_url = os.getenv(
        "GATEWAY_BASE_URL"
    )

    upload_endpoint = (
        f"{gateway_url}/upload"
    )

    response = requests.post(
        upload_endpoint
    )

    assert response.status_code in [
        200,
        201,
        202
    ]