import os

import boto3


def create_s3_client():
    region = os.getenv("AWS_REGION", "eu-central-1")
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
    elif endpoint_url:
        kwargs["aws_access_key_id"] = "minioadmin"
        kwargs["aws_secret_access_key"] = "minioadmin"

    return boto3.client("s3", **kwargs)
