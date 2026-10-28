FROM debian:bookworm

RUN apt update -y && \
apt install -y nginx openssl && \
rm -rf /var/lib/apt/lists/* &&\
rm -rf /etc/nginx/sites-enabled/default

COPY ./conf/nginx.conf /etc/nginx/nginx.conf
COPY ./tools/config.sh /usr/local/bin/config.sh
RUN chmod +x /usr/local/bin/config.sh
EXPOSE 443

ENTRYPOINT ["/usr/local/bin/config.sh"]