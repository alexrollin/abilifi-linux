# WP-dev profile image — WordPress on SQLite + WP-CLI, preinstalled.
# Every step here was PROVEN live in the CF @cloudflare/sandbox before this Dockerfile was written
# (php 8.1 + pdo_sqlite, wp-cli, WP 7.0 core, sqlite-database-integration, `wp core install` -> admin user,
#  282KB .sqlite db). See profiles/wp-dev/PROOF.md.
FROM docker.io/cloudflare/sandbox:0.10.1
ENV DEBIAN_FRONTEND=noninteractive

# 1. PHP + sqlite + the extensions WP-CLI needs
RUN apt-get update -qq && apt-get install -y -qq \
      php-cli php-sqlite3 php-curl php-mbstring php-xml unzip curl \
    && rm -rf /var/lib/apt/lists/*

# 2. WP-CLI
RUN curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

# 3. WP core + SQLite integration (download DIRECT — no DB needed; the drop-in IS the DB).
#    NOTE: `wp core install` (admin creds) is NOT baked — it runs per-instance at provision time
#    with UNIQUE creds (never bake shared admin creds into a template image).
WORKDIR /var/www/wp
RUN wp core download --allow-root \
    && curl -sL https://downloads.wordpress.org/plugin/sqlite-database-integration.latest-stable.zip -o /tmp/sq.zip \
    && mkdir -p wp-content/plugins \
    && (cd wp-content/plugins && unzip -q /tmp/sq.zip) \
    && cp wp-content/plugins/sqlite-database-integration/db.copy wp-content/db.php \
    && sed -i "s|{SQLITE_IMPLEMENTATION_FOLDER_PATH}|/var/www/wp/wp-content/plugins/sqlite-database-integration|g; s|{SQLITE_PLUGIN}|sqlite-database-integration/load.php|g" wp-content/db.php \
    && wp config create --dbname=wp --dbuser=root --dbpass='' --allow-root --skip-check --force \
    && rm /tmp/sq.zip

EXPOSE 8080
# At provision: wp core install --url=... --admin_user=... --admin_password=<unique> --admin_email=... --allow-root
