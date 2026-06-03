#!/bin/bash

set -euo pipefail

for i in $(seq 1 "${STRESS_TEST_REQUEST_COUNT}")
do

    curl -X POST \
      "${GATEWAY_UPLOAD_ENDPOINT}" \
      -F "file=@${STRESS_TEST_VIDEO_FILE}" &

    PID=$!

    wait "${PID}"

done

echo "Stress test completed successfully."