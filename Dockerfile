ARG IMAGE=php
ARG VERSION=8.2-apache

FROM $IMAGE:$VERSION

MAINTAINER macwinnie <dev@macwinnie.me>

# environmental variables
ENV TERM xterm
ENV DEBIAN_FRONTEND noninteractive
ENV WORKINGUSER www-data
ENV PHP_TIMEZONE "Europe/Berlin"
ENV SET_LOCALE "de_DE.UTF-8"
ENV APACHE_LOG_DIR /var/log/apache2
ENV APACHE_WORKDIR /var/www/html
ENV PHP_XDEBUG 0
ENV YESWWW false
ENV NOWWW false
ENV HTTPS true
ENV COMPOSER_NO_INTERACTION 1
ENV START_CRON 0
ENV CRON_PATH /etc/cron.d/docker
ENV NODE_ENV production

# expose ports
EXPOSE 80
EXPOSE 443

# copy all relevant files
COPY files/ /

# organise file permissions and run installer
RUN chmod a+x /install.sh && \
    /install.sh && \
    rm -f /install.sh

WORKDIR ${APACHE_WORKDIR}

# run on every (re)start of container
ENTRYPOINT ["entrypoint"]
CMD ["apache2-foreground"]
