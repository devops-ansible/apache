#!/usr/bin/env bash

###
## adjust timezone
###

echo "Now working on your timezone and define it to ${PHP_TIMEZONE} ..."
timezone_file="/usr/share/zoneinfo/${PHP_TIMEZONE}"
if [ -e $timezone_file ]; then
    time_ini="${PHP_INI_DIR}/conf.d/date_timezone.ini"
    time_ini_setting="date.timezone=${PHP_TIMEZONE}"
    if [ ! -f "$time_ini" ]; then
        echo "$time_ini_setting" > $time_ini
    else
        grep -q 'date.timezone *= *.*' $time_ini && sed -E -i "s~date.timezone *= *.*~$time_ini_setting~" $time_ini || echo "$time_ini_setting" >> $time_ini
    fi
fi
host_timezone="/etc/timezone"
if [ -e $host_timezone ]; then
    echo "${PHP_TIMEZONE}" > $host_timezone
    ln -sf "/usr/share/zoneinfo/${PHP_TIMEZONE}" /etc/localtime

    #update-locale "LANG=${SET_LOCALE}"
    export LC_ALL="${SET_LOCALE}"
    export LANG="${SET_LOCALE}"
    export LANGUAGE="${SET_LOCALE}"
fi
