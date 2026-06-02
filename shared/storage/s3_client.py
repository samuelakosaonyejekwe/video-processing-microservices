import os
import threading

import boto3

_cached_client = None
_client_lock = threading.Lock()


def create_s3_client():
    """Return a process-wide cached boto3 S3 client.

    boto3 clients are thread-safe and rebuilding one per call re-runs credential
    resolution and connection-pool setup on every S3 operation. Cache it.
    """
    global _cached_client
    if _cached_client is not None:
        return _cached_client
    with _client_lock:
        if _cached_client is None:
            _cached_client = _build_s3_client()
    return _cached_client


def _build_s3_client():
    region = os.getenv("AWS_REGION", "")
    app_env = os.getenv("APP_ENV", "production").lower()
    kwargs = {"region_name": region}

    endpoint_url = os.getenv("AWS_S3_ENDPOINT_URL") or os.getenv("S3_ENDPOINT_URL")
    access_key = os.getenv("AWS_ACCESS_KEY_ID")
    secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")

    if endpoint_url:
        kwargs["endpoint_url"] = endpoint_url

    if access_key and secret_key:
        kwargs["aws_access_key_id"] = access_key
        kwargs["aws_secret_access_key"] = secret_key
    elif app_env == "production" and endpoint_url:
        raise RuntimeError(
            "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required in production"
        )

    # When no explicit credentials are provided, leave them unset so boto3 can
    # resolve them through its standard chain (env vars, shared config, instance
    # profile/IRSA). Never fall back to hardcoded credentials.
    return boto3.client("s3", **kwargs)
