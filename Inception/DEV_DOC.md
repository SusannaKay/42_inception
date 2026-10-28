# Developer documentation

This guide explains how to set up, build and work on the Inception stack.

## Set up the environment from scratch

### Prerequisites

- A Linux virtual machine (Debian recommended) with:
  - Docker Engine and the Docker Compose plugin (`docker compose`);
  - `make`;
  - `sudo` rights (needed to create and delete `/home/skayed/data`).
- Your user in the `docker` group, or use `sudo` for Docker commands.
- The domain resolved locally:
  ```bash
  echo "127.0.0.1 skayed.42.fr" | sudo tee -a /etc/hosts
  ```

### Repository structure

```
.
├── Makefile
├── secrets/                  # passwords, ignored by Git
│   ├── credentials.txt
│   ├── db_pass.txt
│   └── db_root.txt
└── srcs/
    ├── .env                  # non-sensitive configuration
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/   (Dockerfile, conf/50-server.cnf, tools/init-db.sh)
        ├── nginx/     (Dockerfile, conf/nginx.conf, tools/config.sh)
        └── wordpress/ (Dockerfile, conf/www.conf, tools/init-wp.sh)
```

### Configuration files

`srcs/.env`:

```
DOMAIN_NAME=skayed.42.fr

DB_NAME=wordpress
DB_USER=<database_user>
DB_HOST=mariadb

WP_TITLE=<site_title>
WP_ADMIN=<admin_username>        # must not contain "admin" / "administrator"
WP_ADMIN_EMAIL=<admin_email>
WP_USER=<second_username>
WP_USER_EMAIL=<second_user_email>
```

Secrets (no quotes):

```bash
mkdir -p secrets
printf '%s' '<db_root_password>' > secrets/db_root.txt
printf '%s' '<db_user_password>' > secrets/db_pass.txt
printf 'PASSWORD_ADMIN=%s\nPASSWORD_USER=%s\n' '<admin_password>' '<user_password>' > secrets/credentials.txt
```

`secrets/` must stay out of Git (it is listed in `.gitignore`).

## Build and launch

```bash
make        # mkdir the data folders + docker compose up -d --build
```

What happens at the first start:

1. **mariadb** initializes the datadir, creates the database and its user, sets the root password, then writes the marker file `.inception_setup_done` and starts `mariadbd` in the foreground.
2. **wordpress** waits for the database (up to 30 s), downloads WordPress with WP-CLI, creates `wp-config.php`, installs the site, creates the second user and starts `php-fpm8.2 -F` on port 9000.
3. **nginx** generates a self-signed certificate for `DOMAIN_NAME` and starts on port 443, forwarding `.php` requests to `wordpress:9000`.

At the following starts, every step that is already done is skipped.

### Makefile targets

| Target | Command |
|---|---|
| `all` / `up` | create `/home/skayed/data/{mariadb,wordpress}`, `docker compose up -d --build` |
| `stop` / `start` | `docker compose stop` / `start` |
| `down` / `clean` | `docker compose down` |
| `fclean` | `docker compose down -v --rmi all` + `sudo rm -rf /home/skayed/data` |
| `re` | `fclean` then `all` |

## Manage containers and volumes

```bash
# State and logs
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f
docker logs <container>

# Shell inside a container
docker exec -it <mariadb|wordpress|nginx> sh

# Rebuild a single service
docker compose -f srcs/docker-compose.yml up -d --build <service>

# Images, network, volumes
docker images
docker network inspect srcs_inception
docker volume ls
docker volume inspect srcs_mariadb_data srcs_wordpress_data

# Database
docker exec -it mariadb mariadb -u root -p

# WordPress through WP-CLI
docker exec wordpress wp user list --allow-root
```

The network and volume names get the Compose project prefix (`srcs_` by default, from the folder of the compose file). Check them with `docker network ls` and `docker volume ls`.

## Where the data is stored and how it persists

| Volume | Mounted in | Stored on the host |
|---|---|---|
| `mariadb_data` | `mariadb:/var/lib/mysql` | `/home/skayed/data/mariadb` |
| `wordpress_data` | `wordpress:/var/www/html` and `nginx:/var/www/html` | `/home/skayed/data/wordpress` |

These are Docker **named volumes** (`driver: local`) whose `driver_opts` set the storage path on the host. The data survives `make stop`, `make down` and rebuilds of the images. Only `make fclean` deletes it, because it removes the volumes and the `/home/skayed/data` folder.

For a full reset (new passwords, empty site), run `make re`.
