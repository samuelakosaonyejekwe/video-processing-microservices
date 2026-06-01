FROM nginx:1.27-alpine

RUN apk upgrade --no-cache && apk add --no-cache gettext

COPY services/frontend/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY services/frontend/docker-entrypoint.sh /docker-entrypoint.sh
COPY services/frontend/public /usr/share/nginx/html

RUN chmod +x /docker-entrypoint.sh

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/ >/dev/null || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
