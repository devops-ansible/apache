#!/bin/bash
set -euo pipefail

# adjust executable rights and move files to correct places
chmod a+x /boot.sh /entrypoint
mv /entrypoint /usr/local/bin/
if [ -f /docker-php-pecl-install ]; then
    mv /docker-php-pecl-install /usr/local/bin/
fi

# upgrade and install applets and services
echo
echo -e '\033[1;30;42m fetch apt cache and install helpers \033[0m'

rm -rf /var/lib/apt/lists/*
apt-get update -q

apt-get -yq install --no-install-recommends \
        ca-certificates curl gnupg lsb-release \
        procps apt-utils

echo
echo -e '\033[1;30;42m configure PHP repository \033[0m'

# install Sury repository signing key
curl -fsSL \
    https://packages.sury.org/debsuryorg-archive-keyring.deb \
    -o /tmp/debsuryorg-archive-keyring.deb

dpkg -i /tmp/debsuryorg-archive-keyring.deb
rm -f /tmp/debsuryorg-archive-keyring.deb

# configure Sury PHP repository
cat > /etc/apt/sources.list.d/php.sources <<EOF
Types: deb
URIs: https://packages.sury.org/php/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/debsuryorg-archive-keyring.gpg
EOF

# refresh package indexes including PHP 7.4
apt-get update -q

# verify PHP 7.4 packages are available
apt-cache policy php7.4-cli php7.4-imap

# fail explicitly if the required legacy IMAP package is unavailable
for package in php7.4-cli libapache2-mod-php7.4 php7.4-imap; do
    if ! apt-cache show "$package" >/dev/null 2>&1; then
        echo "ERROR: $package unavailable in configured Trixie repositories" >&2
        exit 1
    fi
done

echo
echo -e '\033[1;30;42m upgrade all installed \033[0m'
# avoid full dist upgrade during image construction

echo
echo -e '\033[1;30;42m install needed tools \033[0m'
apt-get -yq install --no-install-recommends \
    procps apt-utils python3-setuptools python3-pip python3-jinja2 python3-yaml \
    vim nano less htop tree tmux screen sudo git zsh openssh-client \
    supervisor expect gnupg openssl curl wget unzip \
    default-mysql-client sqlite3 libsqlite3-dev libpq-dev \
    libkrb5-dev zlib1g-dev msmtp msmtp-mta locales locales-all cron \
    libfreetype-dev libjpeg62-turbo-dev libpng-dev libzip-dev libicu-dev \
    libldap2-dev pkg-config liblasso3 libmagickwand-dev libmagickcore-dev \
    imagemagick libcurl4-openssl-dev libonig-dev dialog \
    apache2 libapache2-mod-php7.4 php7.4-cli php7.4-common \
    php7.4-dev php-pear php7.4-mysql php7.4-sqlite3 php7.4-pgsql \
    php7.4-imap php7.4-gd php7.4-intl php7.4-curl php7.4-mbstring \
    php7.4-ldap php7.4-zip php7.4-xml php7.4-opcache \
    php7.4-mcrypt php7.4-imagick php7.4-mongodb php7.4-xdebug

# keep the system PHP command on PHP 7.4
update-alternatives --set php /usr/bin/php7.4
update-alternatives --set phpize /usr/bin/phpize7.4
update-alternatives --set php-config /usr/bin/php-config7.4

# install jinjanator in an isolated Python environment
apt-get -yq install --no-install-recommends python3-venv
python3 -m venv /opt/jinjanator
/opt/jinjanator/bin/pip install --no-cache-dir jinjanator
ln -s /opt/jinjanator/bin/jinjanate /usr/local/bin/jinjanate

# install Node.js from Debian (not EOL NodeSource 16)
apt-get -yq install --no-install-recommends nodejs npm

echo
echo -e '\033[1;30;42m defining aliases \033[0m'

# add aliases
cat >> /etc/bash.bashrc <<'ALIASES'
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
ALIASES

# change user permissions
USER_HOME="$(getent passwd "${WORKINGUSER}" | cut -d: -f6)"
chown -R "${WORKINGUSER}" "${USER_HOME}"

echo
echo -e '\033[1;30;42m installing composer \033[0m'

# install composer
chmod a+x /composer.sh
/bin/sh /composer.sh
mv composer.phar /usr/local/bin/composer
rm -f /composer.sh

# optional shell customization
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true

echo
echo -e '\033[1;30;42m installing Apache things \033[0m'

# install php libraries
# PHP extensions are installed from Sury packages above, including native IMAP.
# No docker-php-ext-* scripts exist in Debian-packaged PHP.
php -v
php -m | grep -E '^(imap|mysqli|pdo_mysql|pdo_pgsql|gd|intl|ldap|imagick|mongodb|mcrypt)$' || true
php -r 'foreach (["imap", "mysqli", "pdo_mysql", "pdo_pgsql", "gd", "intl", "ldap", "imagick", "mongodb", "mcrypt"] as $ext) { if (!extension_loaded($ext)) { fwrite(STDERR, "Missing PHP extension: $ext\n"); exit(1); } }'

# install xdebug
# Installed through php7.4-xdebug above; disable by default as before.
phpdismod -v 7.4 xdebug

# perform installation cleanup
apt-get -y upgrade
apt-get -y clean
apt-get -y autoclean
apt-get -y autoremove
rm -rf /var/lib/apt/lists/*

# secure apache shoutouts
sed -i 's/ServerSignature On/ServerSignature Off/' /etc/apache2/conf-enabled/security.conf
sed -i 's/ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-enabled/security.conf

# enable php modules
a2enmod rewrite
a2enmod php7.4

# provide official-image-compatible Apache foreground command
cat > /usr/local/bin/apache2-foreground <<'APACHE'
#!/bin/bash
set -e
rm -f /var/run/apache2/apache2.pid
mkdir -p /var/run/apache2
exec apache2 -DFOREGROUND
APACHE
chmod +x /usr/local/bin/apache2-foreground

# #install mod_auth_mellon metadata script
# git clone --depth 1 -b master https://github.com/latchset/mod_auth_mellon.git
# cp mod_auth_mellon/mellon_create_metadata.sh /usr/bin/
# rm -rf mod_auth_mellon
