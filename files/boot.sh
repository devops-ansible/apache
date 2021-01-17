#!/usr/bin/env bash

###
## configure Apache2
###

echo 'Writing Apache Config file from Template ...'
j2 /templates/apache.j2 > /etc/apache2/sites-available/000-default.conf


###
## do things with the working directory
###

echo "Gathering data about working user ..."
if [ -z ${WORKINGUSER+x} ]; then WORKINGUSER="www-data"; export WORKINGUSER; fi
if [ -z ${WORKINGGROUP+x} ]; then WORKINGGROUP="www-data"; export WORKINGGROUP; fi

if [ -z ${WWW_UID+x} ]; then WWW_UID="$(id -u $WORKINGUSER)"; export WWW_UID; fi
if [ -z ${WWW_GID+x} ]; then WWW_GID="$(id -g $WORKINGGROUP)"; export WWW_GID; fi

grep -x "$WWW_UID" <<< "$(cat /etc/passwd | awk -F: '{print $3}' | sort -n)" > /dev/null || usermod -u $WWW_UID $WORKINGUSER
grep -x "$WWW_GID" <<< "$(cat /etc/group | awk -F: '{print $3}' | sort -n)" > /dev/null || groupmod -g $WWW_GID $WORKINGGROUP


###
## write out SMTP data
###

if [ ! -z ${SMTP_HOST+x} ] && [ ! -z ${SMTP_FROM+x} ] && [ ! -z ${SMTP_PASS+x} ]; then
    echo "Writing out /etc/msmtprc ..."
    j2 /templates/msmtprc.j2 > /etc/msmtprc
fi


###
## check permissions with all relevant folders
###

echo "Changing folder permissions for Apache workinguser ${WORKINGUSER} ..."
HOME_FOLDER="$(eval echo ~$WORKINGUSER)"
if [[ $APACHE_WORKDIR = "$HOME_FOLDER"* ]]; then
    chown -R $WORKINGUSER:$WORKINGGROUP $HOME_FOLDER
elif [[ $HOME_FOLDER = "$APACHE_WORKDIR"* ]]; then
    chown -R $WORKINGUSER:$WORKINGGROUP $APACHE_WORKDIR
else
    chown -R $WORKINGUSER:$WORKINGGROUP $HOME_FOLDER
    chown -R $WORKINGUSER:$WORKINGGROUP $APACHE_WORKDIR
fi


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


###
## install additional apache2 modules if defined
###

if ! [ -z "$MODS" ] ; then
    echo "Enabling mods defined in \$MODS ..."
    for i in $MODS ; do
        a2enmod $i
    done
fi | grep -q "service apache2 restart" && service apache2 restart


###
## start cron if needed
###

if [[ ${START_CRON} != 0 ]]; then
    echo 'Now starting cron deamon to run your cronjobs.'
    echo "Please be aware to mount your cronjob file to ${CRON_PATH}"
    if [ ! -s "${CRON_PATH}" ]; then
        cat <<EOF >> "${CRON_PATH}"
# This crontab file holds commands for all users to be run by
# cron. Each command is to be defined within a separate line.
#
# To define the time you can provide concrete (numeric) values,
# comma separate them or use \`*\` to use any of the possible
# values.
# You can also use basic calculation - i.e. if you want to run
# a job every 20th minute use \`*/20\`.
#
# The tasks will be started based on the system time and
# timezone.
#
#
# The example below would print a message to the STDOUT of the
# docker container and - if any error does occur – the errors
# will be printed to the STDERR of the container.
#
# Please be aware that you are locating the crontab file within
# \`/etc/cron.d\` directory and for that there is also the need
# to define the user who should run the cron command!
#
# ┌────────────────────────────────── minute (0-59)
# │    ┌───────────────────────────── hour (0-23)
# │    │    ┌──────────────────────── day (1-31)
# │    │    │    ┌─────────────────── month (1-12)
# │    │    │    │    ┌────────────── day of week (0-6, sunday equals 0)
# │    │    │    │    │    ┌───────── user
# │    │    │    │    │    │    ┌──── command
# │    │    │    │    │    │    │
# ┴    ┴    ┴    ┴    ┴    ┴    ┴
# */20 *    *    *    *    root echo 'this is a demonstration cronjob'  1> /proc/1/fd/1  2> /proc/1/fd/2

EOF
    fi
    cron
fi


###
## additional bootup things
###

echo 'Doing additional bootup things from `/boot.d/` ...'
bootpath='/boot.d/*.sh'
count=`ls -1 ${bootpath} 2>/dev/null | wc -l`
if [ $count != 0 ]; then
    chmod a+x ${bootpath}
    for f in ${bootpath}; do source $f; done
fi


###
## enable differentiation of environments by setting ENV environmental variable
###

if [ "$ENV" = "dev" ]; then
    echo Using PHP production mode
else
    echo Using PHP development mode
    echo "error_reporting = E_ERROR | E_WARNING | E_PARSE" > /usr/local/etc/php/conf.d/php.ini
    echo "display_errors = On" >> /usr/local/etc/php/conf.d/php.ini
fi

###
## php.ini enhancements
###
if [ "$PHPINI" != "" ]; then
    initscript="/boot.d/inibuild.php"
    chmod a+x ${initscript}
    ${initscript} $PHPINI >> /usr/local/etc/php/conf.d/php_env.ini
fi
