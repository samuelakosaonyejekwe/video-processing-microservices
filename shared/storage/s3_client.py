import os

import boto3


def create_s3_client():
    region = os.getenv("AWS_REGION", "eu-central-1")
    kwargs = {"region_name": region}

    endpoint_url = os.getenv("AWS_S3_ENDPOINT_URL") or os.getenv("S3_ENDPOINT_URL")
    if endpoint_url:
        kwargs["endpoint_url"] = endpoint_url
        kwargs["aws_access_key_id"] = os.getenv("AWS_ACCESS_KEY_ID", "minioadmin")
        kwargs["aws_secret_access_key"] = os.getenv(
            "AWS_SECRET_ACCESS_KEY", "minioadmin"
        )

    return boto3.client("s3", **kwargs)
