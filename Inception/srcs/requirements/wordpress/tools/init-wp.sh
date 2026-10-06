#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_pass)
WP_ADMIN_PASSWORD=$(cat /run/secrets/wp_admin_pass)
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_pass)

cd /var/www/html

# Attende MariaDB (max 60 secondi)
for i in $(seq 1 60); do
    mariadb-admin ping -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" --silent && break
    echo "In attesa di MariaDB... ($i)"
    sleep 1
done

# Installa solo al primo avvio: il volume conserva i file
if [ ! -f wp-config.php ]; then
    wp core download --allow-root

    wp config create --allow-root \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost="$DB_HOST:3306"

    wp core install --allow-root \
        --url="https://$DOMAIN_NAME" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email

    wp user create "$WP_USER" "$WP_USER_EMAIL" --allow-root \
        --role=author \
        --user_pass="$WP_USER_PASSWORD"
fi

chown -R www-data:www-data /var/www/html

# php-fpm in foreground come PID 1
exec php-fpm8.2 -F
