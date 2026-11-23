FROM nginx:alpine
COPY --chmod=0644 nginx/default.conf /etc/nginx/conf.d/default.conf
RUN mkdir -m 0755 -p /srv/estaticos
COPY --chmod=0644 app/public/estilos.css /srv/estaticos/estilos.css
