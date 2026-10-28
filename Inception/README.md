*This project has been created as part of the 42 curriculum by skayed.*

# Inception

## Description

Inception is a system administration project: the goal is to set up a small web infrastructure made of several services, each running in its own Docker container, orchestrated with Docker Compose inside a virtual machine.

The stack serves a WordPress website over HTTPS:

- **NGINX**: the only entry point, listening on port 443 with TLSv1.2/TLSv1.3 only.
- **WordPress + PHP-FPM**: runs the website and talks to NGINX through FastCGI on port 9000.
- **MariaDB**: stores the WordPress database, reachable only from the internal network on port 3306.

Every image is built from scratch with a custom Dockerfile based on `debian:bookworm` (the penultimate stable Debian release). No ready-made images are pulled, apart from the Debian base image.

## Instructions

### Prerequisites

- A Linux virtual machine with `docker`, the `docker compose` plugin, `make` and `sudo`.
- The domain pointing to the local machine. Add this line to `/etc/hosts`:
  ```
  127.0.0.1 skayed.42.fr
  ```
- The secret files in `secrets/` and the `srcs/.env` file (see [DEV_DOC.md](DEV_DOC.md) for their format).

### Usage

```bash
make        # create data folders, build the images and start the stack
make stop   # stop the containers without removing them
make start  # start the stopped containers again
make down   # stop and remove the containers (data is kept)
make fclean # remove containers, images, volumes and data on the host
make re     # fclean + full rebuild
```

Once the stack is running, open **https://skayed.42.fr** (the certificate is self-signed, so the browser shows a warning to accept). The admin panel is at **https://skayed.42.fr/wp-admin**.

More details: [USER_DOC.md](USER_DOC.md) for end users and administrators, [DEV_DOC.md](DEV_DOC.md) for developers.

## Project description

### How Docker is used

Each service has its own folder in `srcs/requirements/`, containing:

- a `Dockerfile` that installs the service on top of `debian:bookworm`;
- a `conf/` folder with the configuration files copied into the image;
- a `tools/` folder with the entrypoint script that configures the service at startup.

`srcs/docker-compose.yml` builds the three images (each image has the same name as its service), connects them to a dedicated bridge network, mounts the two named volumes, passes the environment variables from `srcs/.env` and the Docker secrets from `secrets/`. Every container has `restart: always`, so it restarts after a crash. The `Makefile` at the root drives everything through Docker Compose.

### Main design choices

- **No infinite loops.** Each entrypoint script prepares the service and then uses `exec` to replace itself with the real daemon running in the foreground (`mariadbd`, `php-fpm8.2 -F`, `nginx -g 'daemon off;'`). The daemon becomes PID 1 and receives the stop signals from Docker directly.
- **Idempotent, resumable setup.** The init scripts check what is already done before doing it. MariaDB writes a marker file only once the whole setup succeeds, and WordPress checks each step on its own (download, `wp-config.php`, core install, second user). This way, a restart in the middle of the first setup resumes it instead of leaving it half done.
- **Bounded waits.** WordPress waits for MariaDB to accept connections with a loop limited to 30 attempts, then exits with an error. `restart: always` takes care of retrying.
- **WP-CLI** is used to download, configure and install WordPress and to create the two users (an administrator and an author) without going through the web installer.
- **Self-signed TLS certificate.** NGINX generates it at startup with `openssl`, using the `DOMAIN_NAME` variable.
- **Passwords only in secrets.** Dockerfiles and `.env` contain no passwords: they are read from `/run/secrets/` inside the containers.

### Virtual Machines vs Docker

A virtual machine emulates a full computer: it runs its own kernel on virtualized hardware, so it is strongly isolated but heavy. A Docker container is an isolated process that shares the host kernel, using namespaces and cgroups. It starts in seconds, takes little space, and its image describes the environment in a reproducible way. The trade-off is weaker isolation, since all containers share the same kernel. 

### Secrets vs Environment Variables

Environment variables are convenient for configuration (domain name, database name, usernames), but they are visible with `docker inspect`, inherited by child processes and can easily end up in logs. Docker secrets are mounted as files in `/run/secrets/`, only in the containers that declare them, and are not part of the container configuration. Here non-sensitive values live in `srcs/.env`, and all passwords are passed as secrets and kept out of Git.

### Docker Network vs Host Network

With `network: host` a container shares the host network stack directly: no isolation, and every port it opens is exposed on the machine. A user-defined bridge network (`inception` here) creates a private network for the containers. They reach each other by service name through Docker's internal DNS (`mariadb`, `wordpress`), and only the ports published explicitly are reachable from outside. In this stack that is only 443 on NGINX: MariaDB (3306) and PHP-FPM (9000) are reachable only from inside the network.

### Docker Volumes vs Bind Mounts

A bind mount maps any host path into the container: simple, but tied to the host's folder structure and not managed by Docker. A named volume is created and managed by Docker (`docker volume ls`, `docker volume inspect`), has a name that is independent from the path, and is what the subject requires. This project uses two named volumes, `mariadb_data` and `wordpress_data`, with the `local` driver options set so that their data is stored in `/home/skayed/data/mariadb` and `/home/skayed/data/wordpress` on the host. They remain named volumes managed by Docker, with their storage location chosen explicitly.

## Resources

### Documentation

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Dockerfile best practices](https://docs.docker.com/build/building/best-practices/)
- [Docker secrets in Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [MariaDB command-line client](https://mariadb.com/docs/server/clients-and-utilities/mariadb-client/mariadb-command-line-client)
- [WP-CLI commands](https://developer.wordpress.org/cli/commands/)
- [WP-CLI issue #4968](https://github.com/wp-cli/wp-cli/issues/4968)
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [Tutorial on WordPress with NGINX and PHP-FPM](https://it.linux-console.net/?p=10307)

### AI usage

AI (Claude) was used as a support learning tool, not to generate the project blindly:

- to explain Docker concepts (PID 1, named volumes with driver options, secrets) and clarify parts of the subject;
- to review the code against the subject requirements, which led to making the MariaDB and WordPress init scripts idempotent and resumable;
- to help draft and structure this README, USER_DOC.md and DEV_DOC.md.
