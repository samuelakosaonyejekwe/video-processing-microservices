import os

import pytest


def pytest_configure():

    os.environ.setdefault("APP_ENV", "test")
    os.environ.setdefault("SMTP_HOST", "localhost")
    os.environ.setdefault("SMTP_PASSWORD", "test")
    os.environ.setdefault("RABBITMQ_HOST", "localhost")
    os.environ.setdefault("RABBITMQ_USERNAME", "guest")
    os.environ.setdefault("RABBITMQ_PASSWORD", "guest")
