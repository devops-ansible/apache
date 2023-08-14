#!/usr/bin/env bash

###
## configure local xdebug for usage with phpStorm on a Mac or Linux system
###

if [[ ${PHP_XDEBUG} != 0 ]]; then

    echo "Working on XDebug Settings – should be only done in dev-environments ..."

    HOST_IP=$( getent hosts docker.for.mac.localhost | awk '{ print $1 }' )
    if [ -z "$HOST_IP" ]; then
        HOST_IP=$( /sbin/ip route | awk '/default/ { print $3 }' )
    fi
    export HOST_IP

    xdebug_ini="${PHP_INI_DIR}/conf.d/xdebug.ini"

    if [ ! -d "${PHP_INI_DIR}/conf.d" ]; then
        mkdir "${PHP_INI_DIR}/conf.d"
        touch $xdebug_ini
    fi

    j2 /templates/xdebug.j2 > $xdebug_ini

elif [[ -f "${xdebug_ini}" ]]; then

    rm -rf $xdebug_ini

fi
