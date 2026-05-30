import os

import pytest


def pytest_configure():

    os.environ.setdefault("APP_ENV", "test")
    os.environ.setdefault("JWT_PUBLIC_KEY", "")
    os.environ.setdefault("JWT_ALGORITHM", "HS256")
    os.environ.setdefault("JWT_SECRET", "test-secret-key-for-unit-tests")
    os.environ.setdefault("JWT_ISSUER", "video-converter")
    os.environ.setdefault("JWT_AUDIENCE", "video-converter-api")
