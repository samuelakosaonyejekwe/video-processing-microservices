import os

import pytest


def pytest_configure(config):

    config.addinivalue_line(
        "markers",
        "integration: marks tests requiring running services",
    )


def pytest_collection_modifyitems(config, items):

    if os.getenv("INTEGRATION_TESTS", "").lower() in ("1", "true", "yes"):
        return

    skip_integration = pytest.mark.skip(
        reason="Set INTEGRATION_TESTS=true to run live service tests"
    )

    for item in items:
        if "integration" in item.nodeid or "e2e" in item.nodeid:
            item.add_marker(skip_integration)
            continue

        if any(
            part in item.nodeid
            for part in (
                "tests/auth/",
                "tests/gateway/",
                "tests/converter/",
                "tests/notification/",
                "tests/kubernetes/",
                "tests/observability/",
                "tests/load/",
                "tests/chaos/",
            )
        ):
            item.add_marker(skip_integration)
