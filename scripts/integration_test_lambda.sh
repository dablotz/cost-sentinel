#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION (e.g. us-east-1)}"
: "${LAMBDA_FUNCTION_NAME:?Set LAMBDA_FUNCTION_NAME (e.g. cost-sentinel-dev-ingestor)}"
: "${DASHBOARD_BUCKET_NAME:?Set DASHBOARD_BUCKET_NAME (your dashboard bucket)}"

LATEST_KEY="${LATEST_KEY:-latest.json}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EVENT_TEMPLATE="$REPO_ROOT/app/ingestor/events/integration_sns_event.json"
EVENT_FILE="$(mktemp)"
OUT_FILE="$(mktemp)"

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")-$$"

cleanup() {
  rm -f "$EVENT_FILE" "$OUT_FILE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -f "$EVENT_TEMPLATE" ]]; then
  echo "ERROR: Missing event template: $EVENT_TEMPLATE"
  exit 1
fi

# Replace placeholder with unique run ID for this execution
sed "s/REPLACE_AT_RUNTIME/${RUN_ID}/g" "$EVENT_TEMPLATE" > "$EVENT_FILE"

echo "Invoking Lambda '${LAMBDA_FUNCTION_NAME}' in ${AWS_REGION} (run_id=${RUN_ID})"
aws lambda invoke \
  --region "$AWS_REGION" \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --payload "fileb://${EVENT_FILE}" \
  "$OUT_FILE" >/dev/null

echo "Lambda response:"
cat "$OUT_FILE" || true
echo

echo "Polling s3://${DASHBOARD_BUCKET_NAME}/${LATEST_KEY} for run_id=${RUN_ID}"
deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))

while true; do
  now=$(date +%s)
  if (( now > deadline )); then
    echo "ERROR: Timeout after ${TIMEOUT_SECONDS}s waiting for latest.json to contain run_id=${RUN_ID}"
    exit 1
  fi

  if aws s3api get-object \
      --region "$AWS_REGION" \
      --bucket "$DASHBOARD_BUCKET_NAME" \
      --key "$LATEST_KEY" \
      /tmp/latest.json >/dev/null 2>&1; then

    # Validate JSON and ensure it contains our run_id.
    # Your handler writes { parsed_message: {...}, raw_message: "..." }
    if python3 - <<PY >/dev/null 2>&1
import json
path = "/tmp/latest.json"
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict):
    raise SystemExit(2)

pm = data.get("parsed_message")
raw = data.get("raw_message") or ""

run_id = pm.get("test_run_id") if isinstance(pm, dict) else None
ok = (run_id == "${RUN_ID}") or ("${RUN_ID}" in raw)

if not ok:
    raise SystemExit(3)
PY
    then
      echo "SUCCESS: latest.json updated and contains run_id=${RUN_ID}"
      exit 0
    fi
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
