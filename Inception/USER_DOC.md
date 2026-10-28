# User documentation

This guide explains how to use the Inception stack as an end user or administrator.

## Services provided

| Service | What it does | Reachable from |
|---|---|---|
| NGINX | Web server, HTTPS entry point (TLSv1.2/1.3) | `https://skayed.42.fr` (port 443) |
| WordPress + PHP-FPM | The website and its admin panel | Through NGINX only |
| MariaDB | Database of the website | Internal Docker network only |

## Start and stop the project

Run these commands from the root of the repository:

```bash
make        # build and start everything
make stop   # pause the containers
make start  # resume the paused containers
make down   # stop and remove the containers (website data is kept)
```

`make fclean` deletes **everything**, including the database and the website files. Use it only to start over from scratch.

## Access the website and the admin panel

1. Make sure `/etc/hosts` contains `127.0.0.1 skayed.42.fr`.
2. Open **https://skayed.42.fr** in the browser.
3. The certificate is self-signed, so the browser shows a security warning: choose to continue anyway.
4. The administration panel is at **https://skayed.42.fr/wp-admin**. Log in with the wp accounts.

There are two WordPress accounts:

- an **administrator**, whose username is `WP_ADMIN` in `srcs/.env`;
- an **author**, whose username is `WP_USER` in `srcs/.env`.

## Locate and manage credentials

Credentials are never stored in the Dockerfiles or in Git.

| What | Where |
|---|---|
| Usernames, emails, domain, database name | `srcs/.env` |
| WordPress admin and author passwords | `secrets/credentials.txt` (`PASSWORD_ADMIN=` and `PASSWORD_USER=`) |
| Database user password | `secrets/db_pass.txt` |
| Database root password | `secrets/db_root.txt` |

The passwords are applied only during the first setup. To change them later:

- **WordPress users**: from the admin panel (Users → Profile), or with WP-CLI:
  ```bash
  docker exec wordpress wp user update <username> --user_pass=<new_password> --allow-root
  ```
- **Starting over with new passwords**: edit the files above, then run `make re`. This deletes all existing data.

## Check that the services are running

```bash
docker compose -f srcs/docker-compose.yml ps   # all three should be "Up"
docker logs nginx                              # logs of one service
docker logs wordpress
docker logs mariadb
```

Quick checks:

```bash
# The website answers over HTTPS
curl -k -I https://skayed.42.fr

# Only TLSv1.2/1.3 are accepted (this one must fail)
curl -k --tlsv1.1 --tls-max 1.1 https://skayed.42.fr

# The database is up and contains the WordPress tables
docker exec -it mariadb mariadb -u root -p -e "SHOW TABLES FROM wordpress;"
```
