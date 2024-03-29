#!/bin/bash

set -e

# adjust executable rights and move files to correct places
chmod a+x /boot.sh
chmod a+x /entrypoint
mv /entrypoint              /usr/local/bin/
mv /docker-php-pecl-install /usr/local/bin/

# upgrade and install applets and services
echo
echo -e '\033[1;30;42m fetch apt cache and install helpers \033[0m'
apt-get update -q --fix-missing
apt-get -yq install -y --no-install-recommends \
        software-properties-common procps apt-utils jq

echo
echo -e '\033[1;30;42m upgrade all installed \033[0m'
apt-get -yq upgrade

echo
echo -e '\033[1;30;42m install needed tools \033[0m'
apt-get -yq install -y --no-install-recommends \
        python3-setuptools python3-pip python3-pkg-resources pipx \
        python3-jinja2 python3-yaml \
        vim nano less \
        htop tree tmux screen sudo git zsh ssh screen \
        supervisor expect \
        gnupg openssl \
        curl wget unzip \
        default-mysql-client sqlite3 libsqlite3-dev libpq-dev \
        libkrb5-dev libc-client-dev \
        zlib1g-dev \
        msmtp msmtp-mta \
        locales locales-all \
        cron \
        libfreetype6-dev libjpeg62-turbo-dev libmcrypt-dev libpng-dev libzip-dev libicu-dev \
        libldb-dev libldap2-dev \
        openssl pkg-config liblasso3 \
        libmagickwand-dev  libmagickcore-dev imagemagick \
        libcurl4-openssl-dev libonig-dev \
        dialog
        # libapache2-mod-auth-mellon

pipx ensurepath
pipx install j2cli
chown -R ${WORKINGUSER} $( eval echo ~${WORKINGUSER} )
sudo -u${WORKINGUSER} pipx ensurepath
sudo -u${WORKINGUSER} pipx install j2cli

node_line="(LTS)"
# node_line="(Current)"
node_version="$( curl -s https://api.github.com/repos/nodejs/node/releases | jq -r '[ .[] | select(.name | contains("'${node_line}'")) | .tag_name | split("v") | .[1] | split(".") | .[0] ] | sort | .[-1]' )"
curl -sL "https://deb.nodesource.com/setup_${node_version}.x" | sudo bash -
apt-get install -y nodejs

echo
echo -e '\033[1;30;42m defining aliases \033[0m'

set +e

# add aliases
read -d '' bash_alias << 'EOF'
# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
EOF

set -e

echo "$bash_alias" >> /etc/bash.bashrc

# change user permissions
chown -R "${WORKINGUSER}" $( eval echo "~${WORKINGUSER}" )

echo
echo -e '\033[1;30;42m installing composer \033[0m'

# install composer
chmod a+x /composer.sh
/bin/sh /composer.sh
mv composer.phar /usr/local/bin/composer
rm -f /composer.sh

sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" || true

echo
echo -e '\033[1;30;42m installing Apache things \033[0m'

# install php libraries
# # mcrypt-1.0.4 only supports PHP8 until 8.1.0 ...
# pecl install mcrypt-1.0.4
pecl install imagick
pecl install mongodb
docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql
docker-php-ext-configure calendar
docker-php-ext-configure imap --with-kerberos --with-imap-ssl
docker-php-ext-configure gd --with-freetype --with-jpeg
docker-php-ext-install -j$( nproc ) \
    mysqli zip \
    pdo pdo_mysql pdo_sqlite \
    imap zip \
    exif \
    intl \
    curl mbstring opcache \
    pgsql pdo_pgsql \
    calendar \
    ldap \
    gd

docker-php-ext-enable \
    imagick

# install xdebug
chmod a+x /usr/local/bin/docker-php-pecl-install
docker-php-pecl-install xdebug
rm ${PHP_INI_DIR}/conf.d/docker-php-pecl-xdebug.ini

# perform installation cleanup
apt-get -y clean
apt-get -y autoclean
apt-get -y autoremove
rm -r /var/lib/apt/lists/*

# secure apache shoutouts
sed -i 's/ServerSignature On/ServerSignature\ Off/' /etc/apache2/conf-enabled/security.conf
sed -i 's/ServerTokens\ OS/ServerTokens Prod/' /etc/apache2/conf-enabled/security.conf

# enable php modules
a2enmod rewrite

# #install mod_auth_mellon metadata script
# git clone --depth 1 -b master https://github.com/latchset/mod_auth_mellon.git
# cp mod_auth_mellon/mellon_create_metadata.sh /usr/bin/
# rm -rf mod_auth_mellon
