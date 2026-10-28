#!/bin/sh 

set -e

: "${DB_NAME:?DB_NAME not set}"
: "${DB_USER:?DB_USER not set}"
DB_PASS=$(cat /run/secrets/db_pass)
: "${DB_PASS:?DB_PASS not found}"
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root)
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD not found}"

if [ ! -d "/var/lib/mysql/$DB_NAME" ]; then
    mariadb-install-db
    mariadbd --skip-networking &
    i=0
    while [ "$i" -lt 10 ] && ! mariadb-admin ping > /dev/null 2>&1;
    do
        echo "Waiting for mariadb...($i)"
        sleep 1
        i=$((i+1))
    done
    if [ "$i" -ge 10 ]; then
        echo "mariadb does not respond" >&2
        exit 1
    fi
    mariadb -u root << EOF
    CREATE DATABASE IF NOT EXISTS $DB_NAME;
    ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';
    CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
    GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';

EOF
    echo "$DB_NAME database successfully created"
    mariadb-admin -u root -p"$DB_ROOT_PASSWORD" shutdown
fi

exec mariadbd --user=mysql
