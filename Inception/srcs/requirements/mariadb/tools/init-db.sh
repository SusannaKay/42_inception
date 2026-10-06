#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_pass)
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root)

DATADIR="/var/lib/mysql"
SOCKET="/run/mysqld/mysqld.sock"

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld "$DATADIR"

if [ ! -d "$DATADIR/mysql" ]; then
    mysql_install_db --user=mysql --datadir="$DATADIR" > /dev/null
fi

if [ ! -f "$DATADIR/.initialized" ]; then
    echo "=> Avvio server temporaneo"
    mariadbd --user=mysql --skip-networking --socket="$SOCKET" &
    pid="$!"

    for i in $(seq 1 30); do
        mariadb-admin --socket="$SOCKET" ping --silent && break
        sleep 1
    done

    echo "=> Creo database e utente"
    mariadb -u root --socket="$SOCKET" <<EOSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOSQL

    touch "$DATADIR/.initialized"

    echo "=> Spengo il server temporaneo"
    kill -s TERM "$pid"
    wait "$pid"
fi

echo "=> Avvio MariaDB"
exec mariadbd --user=mysql
