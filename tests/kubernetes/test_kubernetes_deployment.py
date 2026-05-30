import os

import subprocess


def test_gateway_deployment_exists():

    namespace = os.getenv(
        "K8S_NAMESPACE"
    )

    result = subprocess.run(
        [
            "kubectl",
            "get",
            "deployment",
            "gateway",
            "-n",
            namespace
        ],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0