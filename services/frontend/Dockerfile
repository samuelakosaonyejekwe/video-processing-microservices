FROM nginx:1.27-alpine

COPY services/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY services/frontend/public /usr/share/nginx/html

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/ >/dev/null || exit 1
