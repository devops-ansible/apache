#!/usr/bin/env bash

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
