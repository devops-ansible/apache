#!/usr/bin/env bash

###
## chown function
###
docker_chown () {

    if ! ( [ -z ${DISABLE_CHOWN+x} ] || [ $( echo "${DISABLE_CHOWN}" | tr '[:upper:]' '[:lower:]' ) != true ] ); then
        if ! ( [ -z ${CHOWN_DEBUG+x} ] || [ $( echo "${CHOWN_DEBUG}" | tr '[:upper:]' '[:lower:]' ) != true ] ); then
            echo 'Skipping CHOWN due to env variable `DISABLE_CHOWN` being set `True`!'
        fi
        return 0
    fi

    old_dir=$(pwd)

    usr_id=${1}
    grp_id=${3}
    path=${2}

    user=$( getent passwd "${usr_id}" | cut -d: -f1 )

    if [[ -d "${path}" ]]; then
        # Path is a directory
        cd "${path}"
        chval="."
    elif [[ -f "${path}" ]]; then
        # Path is a file
        chval="${path}"
    else
        if ! ( [ -z ${CHOWN_DEBUG+x} ] || [ $( echo "${CHOWN_DEBUG}" | tr '[:upper:]' '[:lower:]' ) != true ] ); then
            echo "${path} is neither a file nor a directory – chown cannot be processed"
        fi
        return
    fi

    files_to_change=$( find "${chval}" ! -user "${user}" -print | wc -l )

    if [ "${files_to_change}" -gt "0" ]; then
        if [ -z ${CHOWN_DEBUG+x} ] || [ $( echo "${CHOWN_DEBUG}" | tr '[:upper:]' '[:lower:]' ) != true ]; then
            chown -R "${usr_id}":"${grp_id}" "${chval}" &
        else
            echo "now running chown on ${path}"
            chown -v -R "${usr_id}":"${grp_id}" "${chval}" &
        fi
    else
        if ! ( [ -z ${CHOWN_DEBUG+x} ] || [ $( echo "${CHOWN_DEBUG}" | tr '[:upper:]' '[:lower:]' ) != true ] ); then
            echo "chown is being skipped on ${path}"
        fi
    fi

    cd "${old_dir}"
}

###
## additional bootup things
###

bootDir="/boot.d/"
echo "Doing additional bootup things from \`${bootDir}\` ..."
cd "${bootDir}"

export PATH="${PATH}:"~/.local/bin

# find all (sub(sub(...))directories of the /boot.d/ folder to be
# checked for executable Shell (!) scripts.
#
# `\( ! -name . \)` would exclude current directory
# find . -type d \( ! -name . \) -exec bash -c "cd '{}' && pwd" \;
dirs=$( find . -type d -exec bash -c "cd '{}' && pwd" \; )
while IFS= read -r cur; do
    bootpath="${cur}/*.sh"
    count=`ls -1 ${bootpath} 2>/dev/null | wc -l`
    if [ $count != 0 ]; then
        echo "... Handling files in directory ${cur}"
        echo
        chmod a+x ${bootpath}
        for f in ${bootpath}; do
            echo "    ... running ${f}"
            source "${f}"
            echo "    ... done with ${f}"
            echo
        done
    fi
done <<< "${dirs}"
