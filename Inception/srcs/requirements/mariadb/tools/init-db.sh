#!/bin/sh

set -e

: "${DB_NAME:?DB_NAME not set}"
: "${DB_USER:?DB_USER not set}"
DB_PASS=$(cat /run/secrets/db_pass)
: "${DB_PASS:?DB_PASS not found}"
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root)
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD not found}"

MARKER=/var/lib/mysql/.inception_setup_done


mariadb_root() {
    if mariadb -u root -e "SELECT 1" > /dev/null 2>&1; then
        mariadb -u root "$@"
    else
        mariadb -u root -p"$DB_ROOT_PASSWORD" "$@"
    fi
}

if [ ! -f "$MARKER" ]; then
    if [ ! -d /var/lib/mysql/mysql ]; then
        mariadb-install-db
    fi

    mariadbd --skip-networking &
    i=0
    while [ "$i" -lt 30 ] && ! mariadb-admin ping > /dev/null 2>&1;
    do
        echo "Waiting for mariadb...($i)"
        sleep 1
        i=$((i+1))
    done
    if [ "$i" -ge 30 ]; then
        echo "mariadb does not respond" >&2
        exit 1
    fi

    mariadb_root << EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF

    mariadb-admin -u root -p"$DB_ROOT_PASSWORD" shutdown
    wait
    touch "$MARKER"
    echo "$DB_NAME database successfully configured"
fi

exec mariadbd --user=mysql
