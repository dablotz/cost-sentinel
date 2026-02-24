import json
import os
from datetime import UTC, datetime
from typing import Any

import boto3


def _s3_client():
    return boto3.client("s3")


ALERTS_BUCKET = os.environ["ALERTS_BUCKET"]
KEY_PREFIX = os.environ.get("KEY_PREFIX", "alerts")
WRITE_LATEST = os.environ.get("WRITE_LATEST", "true").lower() == "true"
DASHBOARD_BUCKET = os.environ.get("DASHBOARD_BUCKET", "").strip()


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _to_jsonl(records: list[dict[str, Any]]) -> bytes:
    lines = [json.dumps(r, separators=(",", ":"), sort_keys=True) for r in records]
    return ("\n".join(lines) + "\n").encode("utf-8")


def _s3_put(
    s3_client,
    bucket: str,
    key: str,
    body: bytes,
    content_type: str = "application/json",
) -> None:
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType=content_type,
        ServerSideEncryption="AES256",
    )


def _normalize_sns_event(event: dict[str, Any]) -> list[dict[str, Any]]:
    """
    SNS -> Lambda event shape:
    event["Records"][i]["Sns"]["Message"] is usually JSON for Budgets notifications,
    but we treat it as opaque and store both raw + parsed if possible.
    """
    out: list[dict[str, Any]] = []
    received_at = _utc_now().isoformat()

    for rec in event.get("Records", []):
        sns = rec.get("Sns", {})
        msg_raw = sns.get("Message", "")
        msg_parsed = None
        try:
            msg_parsed = json.loads(msg_raw)
        except Exception:
            msg_parsed = None

        out.append(
            {
                "received_at": received_at,
                "source": "sns",
                "topic_arn": sns.get("TopicArn"),
                "subject": sns.get("Subject"),
                "message_id": sns.get("MessageId"),
                "timestamp": sns.get("Timestamp"),
                "raw_message": msg_raw,
                "parsed_message": msg_parsed,
            }
        )

    return out


def lambda_handler(event, context, s3_client=None):
    s3_client = s3_client or _s3_client()

    records = _normalize_sns_event(event)

    now = _utc_now()
    key = f"{KEY_PREFIX}/{now:%Y/%m/%d}/alerts.jsonl"
    _s3_put(
        s3_client,
        ALERTS_BUCKET,
        key,
        _to_jsonl(records),
        content_type="application/jsonl",
    )

    if WRITE_LATEST and records:
        latest_key = f"{KEY_PREFIX}/latest.json"
        _s3_put(
            s3_client,
            ALERTS_BUCKET,
            latest_key,
            json.dumps(records[-1], indent=2).encode("utf-8"),
        )

    # later, after records created:
    if DASHBOARD_BUCKET and records:
        _s3_put(
            s3_client,
            DASHBOARD_BUCKET,
            "latest.json",
            json.dumps(records[-1], indent=2).encode("utf-8"),
        )

    return {"status": "ok", "written": len(records), "key": key}
