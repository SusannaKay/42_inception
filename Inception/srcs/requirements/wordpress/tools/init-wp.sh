curl https://wordpress.org/latest.zip -o /tmp/wordpress.zip
unzip /tmp/wordpress.zip -d /var/www/html/
cd /var/www/html/wordpress


wp config create \
    --dbname=DB_NAME \
    --dbuser=WP_USER \
    --dbpass=WP_PASSWORD \
    --dbhost=DB_HOST \
    --allow-root

wp db create

wp core install --url=localhost --title=Inception --admin_user=admin --admin_password=admin --admin_email=admin@example.com --allow-root



