ARG IMAGE=debian
ARG VERSION=trixie

FROM ${IMAGE}:${VERSION}

LABEL org.opencontainers.image.authors="macwinnie <dev@macwinnie.me>"

ENV TERM=xterm \
    DEBIAN_FRONTEND=noninteractive \
    WORKINGUSER=www-data \
    PHP_TIMEZONE=Europe/Berlin \
    SET_LOCALE=de_DE.UTF-8 \
    APACHE_LOG_DIR=/var/log/apache2 \
    APACHE_WORKDIR=/var/www/html \
    PHP_XDEBUG=0 \
    YESWWW=false \
    NOWWW=false \
    HTTPS=true \
    COMPOSER_NO_INTERACTION=1 \
    START_CRON=0 \
    CRON_PATH=/etc/cron.d/docker

EXPOSE 80 \
       443

COPY files/ /

RUN chmod a+x /install.sh && \
    /install.sh && \
    rm -f /install.sh

WORKDIR ${APACHE_WORKDIR}

ENTRYPOINT ["entrypoint"]
CMD ["apache2-foreground"]
