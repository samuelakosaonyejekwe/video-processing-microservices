import os

import requests


def test_gateway_metrics():

    gateway_metrics_url = os.getenv(
        "GATEWAY_METRICS_URL"
    )

    response = requests.get(
        gateway_metrics_url
    )

    assert response.status_code == 200