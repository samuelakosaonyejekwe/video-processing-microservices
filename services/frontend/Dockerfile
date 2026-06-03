FROM nginx:1.27-alpine

RUN apk upgrade --no-cache && apk add --no-cache gettext

COPY services/frontend/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY services/frontend/docker-entrypoint.sh /docker-entrypoint.sh
COPY services/frontend/public /usr/share/nginx/html

# Run as the non-root "nginx" user (uid/gid 101 in the official image).
# The listen port is 3000 (>1024), so no privileged-port capability is needed.
# Ensure every path nginx writes to at runtime is owned/writable by that user:
#   - cache + temp dirs under /var/cache/nginx
#   - the pid file location /var/run (and /run)
#   - the rendered config target /etc/nginx/conf.d
RUN chmod +x /docker-entrypoint.sh \
    && chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /etc/nginx/conf.d \
    && touch /var/run/nginx.pid \
    && chown -R nginx:nginx /var/run/nginx.pid /var/run /run

USER nginx

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/ >/dev/null || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
