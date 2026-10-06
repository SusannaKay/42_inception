NAME = inception

COMPOSE = docker compose
FILE_PATH = srcs/docker-compose.yml
DATA_PATH = /home/skayed/data

all: up

up:
	mkdir -p $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress
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
	sudo rm -rf $(DATA_PATH)

re: fclean all

.PHONY: all up down start stop clean fclean re
