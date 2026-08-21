NAME = inception

COMPOSE = docker compose 
FILE_PATH = srcs/docker-compose.yml

all : up

up:
	$(COMPOSE) -f $(FILE_PATH) up -d --build
down:
	$(COMPOSE) -f $(FILE_PATH) down
start:
	$(COMPOSE) -f $(FILE_PATH) start
stop:
	$(COMPOSE) -f $(FILE_PATH) stop
clean:
	$(COMPOSE) -f $(FILE_PATH) down
fclean:
	$(COMPOSE) -f $(FILE_PATH) down -v --rmi all
re:
	fclean all
.PHONY: all up down start stop clean fclean re 