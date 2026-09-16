#!bin/bash

set -e

DATADIR="/var/lib/mysql"
SOCKET="/var/run/mysqld/mysqld.sock"

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld
chown -R mysql:mysql $DATADIR

if [ ! -d "$DATADIR/mysql" ]; then
    mysql_install_db --user=mysql --datadir="$DATADIR"
fi

if [ ! -f "$DATADIR/.initialized" ]; then

    echo "=> Starting temporary server"

    mariadb  --user=mysql --skip-networking  --socket="$SOCKET" & pid="$!"
    echo "=> Waiting for server startup"

    while ! mysqladmin --socket="$SOCKET" ping &>/dev/null; do
        sleep 1
    done

    echo "=> Creating database wordpress"

    mariadb --user=mysql --socket="$SOCKET" <<-EOSQL
        CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
        CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${DB_NAME}\` TO '${DB_USER}'@'%';
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        FLUSH PRIVILEGES;
EOSQL

    touch "$DATADIR/.initialized"

    if ! kill -s TERM "$pid" || ! wait "$pid"; then
        echo >&2 'MariaDB init process failed.'
        exit 1
    fi

    echo "=> Done!"
mariadb-admin --user=mysql --socket="$SOCKET" shutdown
wait "$pid"
fi

echo "=> Starting MariaDB"
exec mariadbd --user=mysql
