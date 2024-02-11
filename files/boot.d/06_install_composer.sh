#!/usr/bin/env bash

if [ -f "${APACHE_WORKDIR}/composer.json" ]; then
    # run composer install in workdir
    echo "Running composer installation within the Apache work directory ${APACHE_WORKDIR}"
    cd "${APACHE_WORKDIR}"
    composer install
fi

if [ "${APACHE_PUBLIC_DIR}" != "${APACHE_WORKDIR}" ] && [ -f "${APACHE_PUBLIC_DIR}/composer.json" ]; then
    # run composer install in public dir
    echo "Running composer installation within the Apache public directory ${APACHE_PUBLIC_DIR}"
    cd "${APACHE_PUBLIC_DIR}"
    composer install
fi
