#!/bin/bash

set -euo pipefail

for i in $(seq 1 ${RABBITMQ_TEST_MESSAGE_COUNT})
do

    kubectl exec \
      deployment/${RABBITMQ_DEPLOYMENT_NAME} \
      -n ${MESSAGING_NAMESPACE} \
      -- rabbitmqadmin publish \
      routing_key=${VIDEO_UPLOAD_QUEUE} \
      payload="autoscaling-test-message-${i}"

done

echo "RabbitMQ load generation completed successfully."