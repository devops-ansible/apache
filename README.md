# Apache Base Image

[!WARNING]
Since PHP 7.4 reached EOL in January 2023, the default branch of this Apache Repo is changed in August 2023 to PHP8 – and so the `latest` tag will contain PHP 8 instead of PHP 7 ... the `php7` tag will contain the PHP 7 version in future still.

## Provisioned by devops-ansible.de

Base-usage is to provide a as far as possible customizable Apache Webserver for (almost) every PHP-Application.

Within this Repository you only find the Dockerfile and the pipeline configuration to build the image.

## How to get this container run

## Environmental Variables

This image is customizable by these environmental variables:

| env                   | default               | change recommended | description |
| --------------------- | --------------------- |:------------------:| ----------- |
| **NODE\_ENV**         | `production`          | yes                | Node environment definition – by this setting, `devDependencies` are not installed by running `npm install`. **FOR DEVELOPMENT** set to anything else than `production`! |
| **COMPOSER\_NO\_DEV** | `1`                   | yes                | analoguous to `NODE_ENV` this now defaults to a prod environment for `composer` installation |
| **PHP\_TIMEZONE**      | `Europe/Berlin`      | yes                | timezone-file to use as default – can be one value selected out of `/usr/share/zoneinfo/`, i.e. `<region>/<city>` |
| **APACHE\_WORKDIR**   | `/var/www/html`       | yes                | home folder of apache web application |
| **APACHE\_LOG\_DIR**  | `/var/log/apache2`    | yes                | folder for log files of apache |
| **APACHE\_PUBLIC\_DIR** | `$APACHE_WORKDIR` | yes               | folder used within apache configuration to be published – can be usefull if i.e. subfolder `public` of webproject should be exposed. Should regularly be child of `APACHE_WORKDIR`. |
| **PHP\_XDEBUG**       | `0`                   | yes                | You can use this to enable xdebug. start-apache2 script will enable xdebug if **PHP_XDEBUG** is set to *1* |
| **MODS**              |                       | no                 | space separated list of PHP modules to be enabled on boot – modules have to be installed (i.e. through a special bootup script within `/boot.d/`-folder) |
| **YESWWW**            | *false*               | yes                | Duplicate content has to be avoided – therefore a decision for containers delivering content of `www.domain.tld` and `domain.tld` has to be made which one should be the mainly used one. **YESWWW** will be overridden by **NOWWW** if both are true. |
| **NOWWW**             | *false*               | yes                | See **YESWWW** |
| **HTTPS**             | *true*                | yes                | relevant for **YESWWW** and **NOWWW** since config rules have to be adjusted. |
| **PHPINI**            | `{}`                  | yes                | JSON-String of key value dictionary to define additional ini settings for `php.ini`, i.e. `{"post_max_size":"250M","upload_max_filesize":"250M"}` |
| **SMTP\_HOST**        |                       | yes                | should be set to your smtp host, i.e. `mail.example.com` |
| **SMTP\_PORT**        |                       | yes                | defaults to `587` |
| **SMTP\_FROM**        |                       | yes                | should be set to your sending from address, i.e. `motiontool@example.com` |
| **SMTP\_USER**        |                       | yes                | defaults to `SMTP_FROM` and has to be the user, you are authenticating on the **SMTP_HOST** |
| **SMTP\_PASS**        |                       | yes                | should be set to your plaintext(!) smtp password, i.e. `I'm very Secr3t!` |
| **WORKINGUSER**       | `www-data`            | no                 | user that works as apache user – not implemented changable |
| **TERM**              | `xterm`               | no                 | set terminal type – default *xterm* provides 16 colors |
| **DEBIAN\_FRONTEND**  | `noninteractive`      | no                 | set frontent to use – default self-explaining  |
| **START\_CRON**        | `0`                   | if `cron` needed   | set to `1` if cron should be startet at boot of the container |
| **CRON\_PATH**         | `/etc/cron.d/docker`  | no                 | path to default cron file that will be provided with the default crontab content, see below |
| **APACHE\_ADDITIONAL** |                       | yes                | additional configuration for apache – may be multiline content, but is no more Portainer-safe if multiline! |
| **DISABLE\_CHOWN**     |                       | no                 | disable the user change for all files in `$HOME` of `WORKINGUSER` and `APACHE_WORKDIR`. |
| **WWW\_UID**           |                       | no                 | change `www-data` UID |
| **WWW\_GID**           |                       | no                 | change `www-data` GID |
| **CHOWN\_DEBUG**       |                       | no                 | will output debug messages while running chown |


## Installed Tools

| tool(s)                      | description |
| ---------------------------- | ----------- |
| **software-properties-common**, **procps** | simplify further installations |
| **python-setuptools**, **python-pip**, **python-pkg-resources** | simplify python installations |
| **python-jinja2**, **j2cli** | used for template provisioning |
| **python-yaml**, **python-paramiko** | provision Image for further provisioning via Ansible | **vim**, **nano**            | editors |
| **python-httplib2**            | Small, fast HTTP client library for Python |
| **python-keyczar**             | Toolkit for safe and simple cryptography |
| **htop**, **tree**, **tmux**, **screen**, **sudo**, **git**, **zsh**, **ssh**, **screen** | usefull ops tools – oh-my-zsh is installed further|
| **supervisor**               | process manager that allows to manage long-running programs |
| **gnupg**, **openssl**       | encryption tools |
| **curl**, **wget**           | fetch remote content |
| **mysql-client**, **libpq-dev**, **postgresql-client**, **sqlite3**, **libsqlite3-dev** | install database things – except of SQLite3 no real database is installed since full databases should run at least on a separate container |
| **libkrb5-dev**, **libc-client-dev** | devtools especially for email |
| **zlib1g-dev**               | compression library |
| **libfreetype6-dev**, **libjpeg62-turbo-dev**, **libmcrypt-dev**, **libpng-dev** | simplify working with and on images |
| **nodejs** + **npm**         | javascript development tools – LTS stream |
| **composer**                 | php package manager |
| **msmtp**, **msmtp-mta**     | simple and easy to use SMTP client replacing sendmail |
| **cron**                     | recurring tasks – has to be activated by ENV variables |

## PHP Libraries installed

**imap**, **pdo**, **pdo_mysql**, **imap**, **zip**, **gd**, **exif**, **mcrypt**

## PHP Modules enabled

**rewrite**

## Files and directories to be aware of

### `/boot.d/` – direcotry for additional scripts on bootup

If you want to do the container sth on bootup, this folder is the location to place your `*.sh`-files.

### `/templates/apache.j2` – the Apache Config

The apache config used within containers of this image. It will be provisioned at every start of the container – so you should consider to mount a new template instead of mounting a default apache config directly.

<details>
 <summary>Full Template</summary>

```jinja2
<VirtualHost *:80>

    ServerAdmin root
    DocumentRoot {{ APACHE_PUBLIC_DIR | default(APACHE_WORKDIR) }}

    <Directory {{ APACHE_PUBLIC_DIR | default(APACHE_WORKDIR) }}/>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order deny,allow
        Allow from all
    </Directory>

    AccessFileName .htaccess
	<FilesMatch "^\.ht">
		Require all denied
	</FilesMatch>

    LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
	LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
	LogFormat "%h %l %u %t \"%r\" %>s %O" common
	LogFormat "%{Referer}i -> %U" referer
	LogFormat "%{User-agent}i" agent

    CustomLog /proc/self/fd/1 combined

    <FilesMatch \.php$>
		SetHandler application/x-httpd-php
	</FilesMatch>

    ErrorLog {{ APACHE_LOG_DIR }}/error.log
    CustomLog {{ APACHE_LOG_DIR }}/access.log combined

    # Multiple DirectoryIndex directives within the same context will add
	# to the list of resources to look for rather than replace
	# https://httpd.apache.org/docs/current/mod/mod_dir.html#directoryindex
	DirectoryIndex disabled
	DirectoryIndex index.php index.html

</VirtualHost>
```
</details>

### Default cron entries

By default the `CRON_PATH` variable directs to `/etc/cron.d/docker`. *You should mount that file from your host data or a volume.*  
If you mount an empty file for the beginning, that would be fine since if the file is empty at boot, the following default content with comments and description of the cron file will be provided into it:

```sh
# This crontab file holds commands for all users to be run by
# cron. Each command is to be defined within a separate line.
#
# To define the time you can provide concrete (numeric) values,
# comma separate them or use `*` to use any of the possible
# values.
# You can also use basic calculation - i.e. if you want to run
# a job every 20th minute use `*/20`.
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
# `/etc/cron.d` directory and for that there is also the need
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
```

## Contribution guidelines

This Repository is Creative Commons non Commercial - You can contribute by forking and using pull requests. The team will review them asap.

## last built

2024-05-12 22:41:25
