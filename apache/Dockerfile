FROM httpd:2.4-alpine
RUN sed -i \
    -e 's/^Listen 80$/Listen 443/' \
    -e 's/^#\(LoadModule \(proxy\|proxy_http\|ssl\|socache_shmcb\|headers\)_module .*\)/\1/' \
    conf/httpd.conf \
    && printf '\nInclude conf/extra/asi.conf\n' >> conf/httpd.conf
COPY --chmod=0644 apache/asi.conf conf/extra/asi.conf
COPY --chmod=0644 app/public/estilos.css htdocs/estilos.css
