#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${DEBUG_INSTALL:-0}" == 1 ]]; then set -x; fi

log() { printf '\n\033[1;30;42m %s \033[0m\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
trap 'printf "ERROR at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

: "${WORKINGUSER:?WORKINGUSER must be set}"
: "${PHP_INI_DIR:=/usr/local/etc/php}"
: "${NODE_MAJOR:=24}"

# These are supplied by the Docker build context.
install -m 0755 /entrypoint /usr/local/bin/entrypoint
chmod 0755 /boot.sh
# Preserve the helper for compatibility with existing image consumers.
if [[ -f /docker-php-pecl-install ]]; then
    install -m 0755 /docker-php-pecl-install /usr/local/bin/docker-php-pecl-install
fi

log 'Installing system dependencies'
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -yq
apt-get install -yq --no-install-recommends \
    procps apt-utils jq \
    python3-setuptools python3-pip python3-pkg-resources pipx \
    python3-jinja2 python3-yaml \
    vim nano less htop tree tmux screen sudo git zsh openssh-client \
    supervisor expect gnupg openssl curl wget unzip ca-certificates \
    default-mysql-client sqlite3 libsqlite3-dev libpq-dev \
    zlib1g-dev msmtp msmtp-mta locales locales-all cron \
    libfreetype6-dev libjpeg62-turbo-dev libmcrypt-dev libpng-dev \
    libzip-dev libicu-dev libldb-dev libldap2-dev \
    pkg-config liblasso3 libmagickwand-dev libmagickcore-dev imagemagick \
    libcurl4-openssl-dev libonig-dev dialog \
    autoconf automake libtool gcc g++ make libssl-dev libsasl2-dev

log 'Installing Jinjanator'
export PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin
pipx install jinjanator
# Also retain the user-specific pipx installation from the original image.
user_home="$(getent passwd "$WORKINGUSER" | cut -d: -f6)"
[[ -n "$user_home" && -d "$user_home" ]] || die "No home directory for $WORKINGUSER"
chown -R "$WORKINGUSER" "$user_home"
sudo -H -u "$WORKINGUSER" pipx ensurepath
sudo -H -u "$WORKINGUSER" pipx install jinjanator

log "Installing Node.js ${NODE_MAJOR}.x"
# NODE_MAJOR is explicitly configurable; avoid parsing GitHub release names.
curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource-setup.sh
bash /tmp/nodesource-setup.sh
rm -f /tmp/nodesource-setup.sh
apt-get install -yq --no-install-recommends nodejs

log 'Configuring shell aliases'
cat >> /etc/bash.bashrc <<'ALIASES'
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
ALIASES

log 'Installing Composer'
[[ -f /composer.sh ]] || die '/composer.sh missing'
sh /composer.sh
install -m 0755 composer.phar /usr/local/bin/composer
rm -f composer.phar /composer.sh

log 'Installing Oh My Zsh'
# Preserve the original non-fatal behavior; avoid piping directly to a shell.
if curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
    -o /tmp/ohmyzsh-install.sh; then
    RUNZSH=no CHSH=no bash /tmp/ohmyzsh-install.sh || true
    rm -f /tmp/ohmyzsh-install.sh
fi

log 'Preparing PHP extension configuration'
command -v phpize >/dev/null || die 'phpize missing'
command -v php-config >/dev/null || die 'php-config missing'
command -v docker-php-ext-install >/dev/null || die 'docker-php-ext-install missing'

# For official PHP images, PHP_INI_DIR is already configured as the scan root.
# For custom builds, verify that PHP actually scans this location.
php_scan_dir="$(php --ini | sed -n 's/^Scan for additional .ini files in: *//p' | tr -d '"' | tr -d "'" )"
[[ "$php_scan_dir" != '(none)' && -n "$php_scan_dir" ]] || \
    die 'PHP was compiled without an INI scan directory; configure PHP with --with-config-file-scan-dir'
# PHP_INI_SCAN_DIR can contain several colon-separated paths.
if [[ ":${php_scan_dir}:" != *":${PHP_INI_DIR}/conf.d:"* ]]; then
    die "PHP scans '$php_scan_dir', not '${PHP_INI_DIR}/conf.d'; align PHP_INI_DIR with the PHP build"
fi
mkdir -p "${PHP_INI_DIR}/conf.d"

# Xdebug 3.6 prereleases are published on GitHub, not necessarily PECL.
# Return a version and source URL separated by a tab.
resolve_xdebug_source() {
    local stable version url releases
    stable="$(curl -fsSL --retry 3 https://pecl.php.net/rest/r/xdebug/stable.txt)"
    if ! php -r 'exit(version_compare(PHP_VERSION, "8.6.0", ">=") ? 0 : 1);' || \
       php -r 'exit(version_compare($argv[1], "3.6.0", ">=") ? 0 : 1);' "$stable"; then
        printf '%s\t%s\n' "$stable" "https://pecl.php.net/get/xdebug-${stable}.tgz"
        return
    fi

    # GitHub's releases API includes prereleases absent from PECL's index.
    # Prefer the newest 3.6.0 RC, beta, or alpha (in that order).
    releases="$(curl -fsSL --retry 3 \
        'https://api.github.com/repos/xdebug/xdebug/releases?per_page=100')"
    version="$(jq -r '[.[].tag_name | select(test("^3\\.6\\.0(alpha|beta|RC)[0-9]+$"; "i"))] | .[]' \
        <<<"$releases" | sort -V | tail -n 1)"
    [[ -n "$version" ]] || die 'No Xdebug 3.6.0 prerelease found on GitHub'
    url="https://github.com/xdebug/xdebug/archive/refs/tags/${version}.tar.gz"
    printf '%s\t%s\n' "$version" "$url"
}

# Download and build the latest stable PECL source archive, or a pinned version.
# Third argument controls whether the extension should be enabled.
install_php_extension() {
    local name="$1" version="${2:-}" enable="${3:-yes}"
    local build_dir source_url resolved
    if [[ -z "$version" && "$name" == xdebug ]]; then
        resolved="$(resolve_xdebug_source)"
        IFS=$'\t' read -r version source_url <<< "$resolved"
    elif [[ -z "$version" ]]; then
        version="$(curl -fsSL --retry 3 "https://pecl.php.net/rest/r/${name}/stable.txt")"
    fi
    # Explicit XDEBUG_VERSION may also name a GitHub-only prerelease.
    if [[ -z "${source_url:-}" ]]; then
        if [[ "$name" == xdebug && "$version" =~ ^3\.6\.0(alpha|beta|RC)[0-9]+$ ]]; then
            source_url="https://github.com/xdebug/xdebug/archive/refs/tags/${version}.tar.gz"
        else
            source_url="https://pecl.php.net/get/${name}-${version}.tgz"
        fi
    fi
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)+(alpha[0-9]+|beta[0-9]+|RC[0-9]+)?$ ]] || die "Invalid $name version: $version"
    [[ "$enable" == yes || "$enable" == no ]] || die "Invalid enable flag: $enable"
    log "Building $name $version"
    build_dir="$(mktemp -d)"
    (
        set -Eeuo pipefail
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir"
        curl -fsSL --retry 3 "$source_url" -o source.tgz
        mkdir src
        tar -xzf source.tgz -C src --strip-components=1
        cd src
        # Imagick 3.8.x uses XtOffsetOf, which PHP 8.6 headers no longer provide.
        # Replace it with the standard C offsetof macro before compilation.
        if [[ "$name" == imagick ]]; then
            # PHP 8.6 no longer provides XtOffsetOf. Patch all C/header uses.
            while IFS= read -r -d '' file; do
                sed -i 's/XtOffsetOf(/offsetof(/g' "$file"
            done < <(grep -rlZ --include='*.c' --include='*.h' 'XtOffsetOf(' . || true)
            # offsetof is declared in stddef.h; confine this to Imagick.
            export CPPFLAGS="${CPPFLAGS:-} -include stddef.h"
        fi
        phpize
        ./configure --with-php-config="$(command -v php-config)"
        make -j"$(nproc)"
        make install
    )
    if [[ "$enable" == yes ]]; then
        printf 'extension=%s.so\n' "$name" > "${PHP_INI_DIR}/conf.d/30-${name}.ini"
        php -r 'if (!extension_loaded($argv[1])) exit(1);' "$name" || \
            die "$name failed to load in PHP CLI"
    else
        rm -f "${PHP_INI_DIR}/conf.d/30-${name}.ini"
        [[ -f "$(php-config --extension-dir)/${name}.so" ]] || die "$name shared object missing"
    fi
}

log 'Building bundled PHP extensions'
# docker-php-ext-install requires PHP source in /usr/src/php.
if [[ ! -f /usr/src/php/ext/standard/config.m4 ]]; then
    command -v docker-php-source >/dev/null || die 'PHP source and docker-php-source missing'
    docker-php-source extract
fi
docker-php-ext-configure pgsql --with-pgsql
docker-php-ext-configure calendar
docker-php-ext-configure gd --with-freetype --with-jpeg
docker-php-ext-install -j"$(nproc)" \
    bcmath mysqli zip pdo pdo_mysql pdo_sqlite \
    exif intl curl mbstring pgsql pdo_pgsql calendar ldap gd

log 'Building third-party PHP extensions'
install_php_extension mongodb "${MONGODB_VERSION:-}" yes
install_php_extension imagick "${IMAGICK_VERSION:-}" yes
if [[ "${BUILD_XDEBUG:-1}" == 1 ]]; then
    install_php_extension xdebug "${XDEBUG_VERSION:-}" no
fi

log 'Verifying PHP extensions'
php -r '
foreach (["mongodb", "imagick"] as $extension) {
    if (!extension_loaded($extension)) {
        fwrite(STDERR, "$extension failed to load\n");
        exit(1);
    }
    echo "$extension: ", phpversion($extension), "\n";
}
echo "PHP: ", PHP_VERSION, "\n";
echo "ZTS: ", PHP_ZTS ? "enabled\n" : "disabled\n";
'
if [[ "${BUILD_XDEBUG:-1}" == 1 ]]; then
    [[ -f "$(php-config --extension-dir)/xdebug.so" ]] || die 'xdebug.so missing'
fi

log 'Securing Apache configuration'
sed -i 's/ServerSignature On/ServerSignature Off/' /etc/apache2/conf-enabled/security.conf
sed -i 's/ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-enabled/security.conf
a2enmod rewrite

log 'Cleaning package caches'
apt-get clean
apt-get autoclean
# Do not autoremove here: it can remove libraries needed by compiled extensions.
rm -rf /var/lib/apt/lists/*
log 'Installation complete'
