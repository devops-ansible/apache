#!/usr/bin/env bash

###
## configure Apache2
###

echo 'Writing Apache Config file from Template ...'
j2 /templates/apache.j2 > /etc/apache2/sites-available/000-default.conf

###
## write out SMTP data
###

if [ ! -z ${SMTP_HOST+x} ] && [ ! -z ${SMTP_FROM+x} ] && [ ! -z ${SMTP_PASS+x} ]; then
    echo "Writing out /etc/msmtprc ..."
    j2 /templates/msmtprc.j2 > /etc/msmtprc
fi

###
## install additional apache2 modules if defined
###

if ! [ -z "$MODS" ] ; then
    echo "Enabling mods defined in \$MODS ..."
    for i in $MODS ; do
        a2enmod $i
        if [[ $? != 0 ]]; then
            docker-php-ext-enable $i
        fi
    done
fi

###
## enable differentiation of environments by setting ENV environmental variable
###

if [ ! -z ${ENV+x} ] && [ "${ENV}" = "dev" ]; then
    echo Using PHP development mode
    echo "error_reporting = E_ERROR | E_WARNING | E_PARSE" > /usr/local/etc/php/conf.d/php.ini
    echo "display_errors = On" >> /usr/local/etc/php/conf.d/php.ini
else
    echo Using PHP production mode
fi

###
## php.ini enhancements
###
if [ ! -z ${PHPINI+x} ] && [ "$PHPINI" != "" ]; then
    initscript="/boot.d/inibuild.php"
    chmod a+x ${initscript}
    ${initscript} $PHPINI >> /usr/local/etc/php/conf.d/php_env.ini
fi

