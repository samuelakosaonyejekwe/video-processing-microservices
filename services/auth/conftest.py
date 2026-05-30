import os

import pytest


def pytest_configure():

    os.environ.setdefault("APP_ENV", "test")
    os.environ.setdefault("POSTGRES_HOST", "localhost")
    os.environ.setdefault("POSTGRES_PORT", "5432")
    os.environ.setdefault("POSTGRES_DB", "test")
    os.environ.setdefault("POSTGRES_USER", "test")
    os.environ.setdefault("POSTGRES_PASSWORD", "test")
    os.environ.setdefault("POSTGRES_SSL_MODE", "disable")
    os.environ.setdefault(
        "JWT_PRIVATE_KEY",
        "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAK"
        "test-key-placeholder\n-----END RSA PRIVATE KEY-----",
    )
    os.environ.setdefault(
        "JWT_PUBLIC_KEY",
        "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEB"
        "test-key-placeholder\n-----END PUBLIC KEY-----",
    )
    os.environ.setdefault("JWT_ISSUER", "video-converter")
    os.environ.setdefault("JWT_AUDIENCE", "video-converter-api")
