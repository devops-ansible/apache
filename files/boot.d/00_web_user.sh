#!/usr/bin/env bash

###
## Adjust working user
###

echo "Gathering data about working user ..."
if [ -z ${WORKINGUSER+x} ]; then WORKINGUSER="www-data"; export WORKINGUSER; fi
if [ -z ${WORKINGGROUP+x} ]; then WORKINGGROUP="www-data"; export WORKINGGROUP; fi

if [ -z ${WWW_UID+x} ]; then WWW_UID="$( id -u ${WORKINGUSER} )"; export WWW_UID; fi
if [ -z ${WWW_GID+x} ]; then WWW_GID="$( id -g ${WORKINGGROUP} )"; export WWW_GID; fi

grep -x "${WWW_UID}" <<< "$( cat /etc/passwd | awk -F: '{print $3}' | sort -n )" > /dev/null || usermod -u ${WWW_UID} ${WORKINGUSER}
if [ $? -ne 0 ]; then
    echo "User \"${WWW_USER}\" could not be created with UID \"${WWW_UID}\""
    exit 1
fi
grep -x "${WWW_GID}" <<< "$( cat /etc/group | awk -F: '{print $3}' | sort -n )" > /dev/null || groupmod -g ${WWW_GID} ${WORKINGGROUP}
if [ $? -ne 0 ]; then
    echo "User \"${WWW_USER}\" could not be created with default group \"${WWW_GID}\""
    GNAME=$( getent group ${WWW_GID} | cut -d: -f1 )
    usermod -a -G "${GNAME}" "${WWW_USER}"
    echo "Added applicationuser to existing group \"${GNAME}\" instead"
fi

###
## check permissions with all relevant folders
###

echo "Changing folder permissions for Apache workinguser ${WORKINGUSER} ..."
HOME_FOLDER="$( eval echo ~$WORKINGUSER )"
if [[ $APACHE_WORKDIR = "$HOME_FOLDER"* ]]; then
    echo "chown on '${HOME_FOLDER}'"
    docker_chown $( id -u "${WORKINGUSER}" ) "${HOME_FOLDER}"   $( id -g "${WORKINGGROUP}" )
elif [[ $HOME_FOLDER = "$APACHE_WORKDIR"* ]]; then
    echo "chown on '${APACHE_WORKDIR}'"
    docker_chown $( id -u "${WORKINGUSER}" ) "${APACHE_WORKDIR}"   $( id -g "${WORKINGGROUP}" )
else
    docker_chown $( id -u "${WORKINGUSER}" ) "${HOME_FOLDER}"   $( id -g "${WORKINGGROUP}" )
    docker_chown $( id -u "${WORKINGUSER}" ) "${APACHE_WORKDIR}"   $( id -g "${WORKINGGROUP}" )
fi
