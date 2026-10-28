#!/bin/sh

set -e

: "${DB_HOST:?DB_HOST not set}"
: "${DB_NAME:?DB_NAME not set}"
: "${DB_USER:?DB_USER not set}"
: "${DOMAIN_NAME:?DOMAIN_NAME not set}"
: "${WP_TITLE:?WP_TITLE not set}"
: "${WP_ADMIN:?WP_ADMIN not set}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL not set}"
: "${WP_USER:?WP_USER not set}"
: "${WP_USER_EMAIL:?WP_USER_EMAIL not set}"

ADMIN_PASS=$(grep "^PASSWORD_ADMIN=" /run/secrets/credentials | cut -d'=' -f2-)
: "${ADMIN_PASS:?ADMIN_PASS not found}"
USER_PASS=$(grep "^PASSWORD_USER=" /run/secrets/credentials | cut -d'=' -f2-)
: "${USER_PASS:?USER_PASS not found}"
DB_PASS=$(cat /run/secrets/db_pass)
: "${DB_PASS:?DB_PASS not found}"


i=0
while [ "$i" -lt 30 ] && ! mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1" > /dev/null 2>&1;
do
	echo "Waiting for mariadb...($i)"
	sleep 1
	i=$((i+1))
done

if [ "$i" -ge 30 ]; then
	echo "mariadb does not respond" >&2
	exit 1
fi
echo "mariadb is ready!"

if [ ! -f /var/www/html/wp-includes/version.php ]; then
	wp core download --allow-root --force
	echo "Success! WordPress core downloaded"
fi

if [ ! -f /var/www/html/wp-config.php ]; then
	wp config create --allow-root \
	--dbname="$DB_NAME" \
	--dbuser="$DB_USER" \
	--dbpass="$DB_PASS" \
	--dbhost="$DB_HOST"
	echo "Success! wp-config.php generated"
fi

if ! wp core is-installed --allow-root > /dev/null 2>&1; then
	wp core install --allow-root \
	--url="https://$DOMAIN_NAME" \
	--title="$WP_TITLE" \
	--admin_user="$WP_ADMIN" \
	--admin_password="$ADMIN_PASS" \
	--admin_email="$WP_ADMIN_EMAIL"
	echo "Success! Core install completed"
fi

if ! wp user get "$WP_USER" --allow-root > /dev/null 2>&1; then
	wp user create --allow-root "$WP_USER" "$WP_USER_EMAIL" --user_pass="$USER_PASS" --role=author
	echo "Success! User $WP_USER created"
fi

chown -R www-data:www-data /var/www/html
php-fpm8.2 -t
exec php-fpm8.2 -F
