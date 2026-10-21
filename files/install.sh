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
        procps apt-utils \
        dpkg-dev devscripts build-essential patch quilt

echo
echo -e '\033[1;30;42m configure PHP repository \033[0m'

# install Sury repository signing key
curl -fsSL \
    https://packages.sury.org/debsuryorg-archive-keyring.deb \
    -o /tmp/debsuryorg-archive-keyring.deb
dpkg -i /tmp/debsuryorg-archive-keyring.deb
rm -f /tmp/debsuryorg-archive-keyring.deb

# configure Sury PHP binary AND source repository (Deb822: one stanza)
cat > /etc/apt/sources.list.d/php.sources <<'EOF'
Types: deb deb-src
URIs: https://packages.sury.org/php/
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/debsuryorg-archive-keyring.gpg
EOF

# Remove a redundant source-only entry from earlier builds, if present.
rm -f /etc/apt/sources.list.d/php-src.sources

# Re-fetch package indexes, including the Sury binary and source indexes.
rm -rf /var/lib/apt/lists/*
apt-get update

echo
echo -e '\033[1;30;42m verify PHP 7.4 repository \033[0m'
echo "Architecture: $(dpkg --print-architecture)"
apt-cache policy php7.4-cli php7.4-imap

# Fail explicitly if a required legacy PHP binary package has no candidate.
for package in php7.4-cli libapache2-mod-php7.4 php7.4-imap; do
    candidate="$(apt-cache policy "$package" | awk '/Candidate:/ {print $2; exit}')"
    if [ -z "$candidate" ] || [ "$candidate" = '(none)' ]; then
        echo "ERROR: $package unavailable in configured Trixie repositories" >&2
        echo 'APT source configuration:' >&2
        cat /etc/apt/sources.list.d/php.sources >&2
        echo 'APT package index files:' >&2
        ls -l /var/lib/apt/lists/ >&2
        exit 1
    fi
done

# The source package must also be available for the local build.
if ! apt-cache showsrc php7.4 >/dev/null 2>&1; then
    echo 'ERROR: PHP 7.4 source unavailable (check deb-src configuration).' >&2
    exit 1
fi

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

echo
echo -e '\033[1;30;42m prepare PHP 7.4 source build \033[0m'

# Install the dependencies declared by Sury's PHP source package.
apt-get -yq build-dep php7.4
mkdir -p /work/php74-security
cd /work/php74-security

# Extract a fresh source tree. Debian applies its existing quilt
# patch series automatically during this step.
apt-get source php7.4
cd php7.4-*/

echo
echo -e '\033[1;30;42m verify PHP 7.4 security patch sources \033[0m'

# Sury's source includes changes overlapping the external PHP 7.4 backport.
# Do not download or apply the same changes a second time.
# These checks verify selected source features, NOT complete CVE coverage.
# 0062: multipart body-parts limit
# 0164: state corruption and multipart parser hardening
for patchname in \
    0062-Introduce-max_multipart_body_parts-INI.patch \
    0164-Avoid-state-corruption-via-bailout.patch; do
    test -f "debian/patches/$patchname" || {
        echo "ERROR: Missing expected source patch: $patchname" >&2
        exit 1
    }
    grep -Fqx "$patchname" debian/patches/series || {
        echo "ERROR: Patch is not listed in debian/patches/series: $patchname" >&2
        exit 1
    }
done

for expected in \
    'php_mime_should_save_hdr' \
    'static char *substring_conf(char *start, size_t len, char quote)' \
    'body_parts_cnt = INI_INT("max_multipart_body_parts")' \
    'if (--body_parts_cnt < 0)'; do
    grep -Fq "$expected" main/rfc1867.c || {
        echo "ERROR: Missing expected multipart source change: $expected" >&2
        exit 1
    }
done

# Save the exact source-package revision and checks for inspection in the container.
mkdir -p /usr/local/share/php74-security
head -n 6 debian/changelog > /usr/local/share/php74-security/source-changelog.txt
sha256sum \
    debian/patches/0062-Introduce-max_multipart_body_parts-INI.patch \
    debian/patches/0164-Avoid-state-corruption-via-bailout.patch \
    > /usr/local/share/php74-security/source-patch-sha256.txt
printf '%s\n' \
    'Selected Sury source changes verified during image build.' \
    'This is not proof that CVE-2026-109618 and CVE-2026-109619 are fully fixed.' \
    > /usr/local/share/php74-security/README.txt

echo 'Expected Sury source changes found; full CVE coverage is not independently verified.'

echo
echo -e '\033[1;30;42m build PHP 7.4 Debian packages \033[0m'

# Label the locally rebuilt packages, without claiming an unverified CVE fix.
export DEBEMAIL='docker-build@localhost'
export DEBFULLNAME='Docker PHP Build'
dch --local '+localbuild1' \
    'Rebuild Sury PHP 7.4 source with its existing patch series.'

# Build the complete set of PHP binary packages.
dpkg-buildpackage -us -uc -b -j"$(nproc)"

echo
echo -e '\033[1;30;42m install locally built PHP 7.4 packages \033[0m'
cd /work/php74-security

# Install matching core packages together.
# Include any other php7.4 packages produced by the source build
# that are currently installed, to keep binary versions consistent.
python3 - <<'PY'
import glob
import subprocess

installed = set(subprocess.check_output(
    ['dpkg-query', '-W', '-f=${binary:Package}\n'], text=True
).splitlines())

packages = []
for path in glob.glob('/work/php74-security/*.deb'):
    name = subprocess.check_output(
        ['dpkg-deb', '-f', path, 'Package'], text=True
    ).strip()
    if name in installed and (
        name.startswith('php7.4-') or name == 'libapache2-mod-php7.4'
    ):
        packages.append(path)

required = {'php7.4-common', 'php7.4-cli', 'libapache2-mod-php7.4', 'php7.4-imap'}
built = {
    subprocess.check_output(['dpkg-deb', '-f', path, 'Package'], text=True).strip()
    for path in packages
}
missing = required - built
if missing:
    raise SystemExit('ERROR: Required PHP packages were not built: ' + ', '.join(sorted(missing)))

with open('/tmp/php74-built-packages.list', 'w') as f:
    f.write('\n'.join(sorted(packages)) + '\n')
PY

# apt resolves dependencies between the newly built local packages.
xargs -r -a /tmp/php74-built-packages.list \
    apt-get -yq install --no-install-recommends

echo
echo -e '\033[1;30;42m verify installed PHP 7.4 packages \033[0m'

# Ensure that the local build, not the original repository packages, is installed.
for package in php7.4-common php7.4-cli libapache2-mod-php7.4 php7.4-imap; do
    version="$(dpkg-query -W -f='${Version}' "$package")"
    case "$version" in
        *+localbuild1*) ;;
        *) echo "ERROR: $package is not the locally rebuilt version: $version" >&2; exit 1 ;;
    esac
done

dpkg-query -W -f='${binary:Package} ${Version}\n' \
    php7.4-common php7.4-cli libapache2-mod-php7.4 php7.4-imap
php -v
php -r 'if (!extension_loaded("imap")) { fwrite(STDERR, "IMAP missing\n"); exit(1); }'

echo
echo -e '\033[1;30;42m PHP 7.4 package build complete \033[0m'

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
php -m | grep -Ei '^(imap|mysqli|pdo_mysql|pdo_pgsql|gd|intl|ldap|imagick|mongodb|mcrypt)$' || true
php -r 'foreach (["imap", "mysqli", "pdo_mysql", "pdo_pgsql", "gd", "intl", "ldap", "imagick", "mongodb", "mcrypt"] as $ext) { if (!extension_loaded($ext)) { fwrite(STDERR, "Missing PHP extension: $ext\n"); exit(1); } }'

# install xdebug
# Installed through php7.4-xdebug above; disable by default as before.
phpdismod -v 7.4 xdebug

# perform installation cleanup
# Do not run apt-get upgrade here: it could replace the locally built PHP packages.
apt-get -y clean
apt-get -y autoclean
# Retain build dependencies for now; autoremove could remove runtime libraries.
rm -rf /work/php74-security /tmp/php74-built-packages.list
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
: "${APACHE_CONFDIR:=/etc/apache2}"
# Debian's apache2 expects these variables from envvars.
. "${APACHE_CONFDIR}/envvars"
mkdir -p "${APACHE_RUN_DIR:-/var/run/apache2}"
rm -f "${APACHE_PID_FILE:-/var/run/apache2/apache2.pid}"
exec /usr/sbin/apache2 -DFOREGROUND
APACHE
chmod +x /usr/local/bin/apache2-foreground

# #install mod_auth_mellon metadata script
# git clone --depth 1 -b master https://github.com/latchset/mod_auth_mellon.git
# cp mod_auth_mellon/mellon_create_metadata.sh /usr/bin/
# rm -rf mod_auth_mellon
