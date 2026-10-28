#!/bin/sh
set -e

: "${DOMAIN_NAME:?DOMAIN_NAME not set}"

if [ ! -f "/etc/ssl/certs/inception.crt" ]; then
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/inception.key \
    -out /etc/ssl/certs/inception.crt \
    -subj "/CN=$DOMAIN_NAME"
fi


nginx -t
exec nginx -g 'daemon off;'