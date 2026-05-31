#!/bin/sh
set -eu

export GATEWAY_UPSTREAM="${GATEWAY_UPSTREAM:-gateway-service:8080}"
envsubst '${GATEWAY_UPSTREAM}' < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'
