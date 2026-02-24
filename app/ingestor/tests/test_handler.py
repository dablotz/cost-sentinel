import json

import boto3
from botocore.stub import Stubber

from app.ingestor.handler import lambda_handler


def test_dashboard_write(monkeypatch):
    s3 = boto3.client("s3", region_name="us-east-1")
    stubber = Stubber(s3)

    monkeypatch.setenv("ALERTS_BUCKET", "alerts-test")
    monkeypatch.setenv("DASHBOARD_BUCKET", "dashboard-test")
    monkeypatch.setenv("WRITE_LATEST", "true")

    # Expect alerts write
    stubber.add_response(
        "put_object",
        {},
        {
            "Bucket": "alerts-test",
            "Key": Stubber.ANY,
            "Body": Stubber.ANY,
            "ContentType": "application/jsonl",
            "ServerSideEncryption": "AES256",
        },
    )

    # Expect alerts latest write
    stubber.add_response(
        "put_object",
        {},
        {
            "Bucket": "alerts-test",
            "Key": Stubber.ANY,
            "Body": Stubber.ANY,
            "ContentType": "application/json",
            "ServerSideEncryption": "AES256",
        },
    )

    # Expect dashboard latest write
    stubber.add_response(
        "put_object",
        {},
        {
            "Bucket": "dashboard-test",
            "Key": "latest.json",
            "Body": Stubber.ANY,
            "ContentType": "application/json",
            "ServerSideEncryption": "AES256",
        },
    )

    stubber.activate()

    event = {"Records": [{"Sns": {"Message": json.dumps({"hello": "world"})}}]}

    result = lambda_handler(event, None, s3_client=s3)

    assert result["status"] == "ok"
    assert result["written"] == 1

    stubber.deactivate()
