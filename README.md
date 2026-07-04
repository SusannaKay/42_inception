# 42_inception

## Docker

Docker permette di impacchettare un'applicazione insieme a tutto ciò di cui ha bisogno per funzionare. 

Non solo codice, ma anche OS minimo, Node, Python, Redis, DB, librerie varie, configurazione. 

Ci sono 3 concetti di docker da capire:
1. Image: è il progetto già preparato
2. Container: è una istanza di Image
3. Dockerfile: file che dice a docker come costruire l'immagine

Flow:
docker legge il file, costruisce l'immagine e poi crea un container.

Il container è come se fosse un piccolo VM con la differenza che la VM contiene hardware virtuale, bios, OS completo, programmi. Il container invece usa direttamente il kernel del sistema operativo host.

Docker in sostanza avvia processi, ogni container per il kernel è solo un processo separato

#### kernel
è il programma che viene caricato subito dopo il boot del computer e rimane in esecuzione fino allo spegnimento. Controlla tutto l'hardware, ed ogni programma dialoga con lui per le richieste. che sia un malloc, l'apertura di un file ( con relativa assegnazione fd ), utilizzo cpu, gestione ram, fork, execve ecc.. tutto passa per il kernel. 
Con docker i container girano sullo stesso kernel, cosa ce in vm non funziona così, ogni vm ha il suo kernel

```text
Utente
  │
  ▼
Programma C / Python / PHP / Node
  │
  ▼
Kernel
  │
  ├── CPU
  ├── RAM
  └── Disco
```

## Database
Da subject ma in generale può stare in un altro container. 

Quindi in uno c'è l'app, in un altro c'è il db. Ogni container è separato

Con docker compose avvio tutti i container insieme ma se io dovessi rimuovere il container mariadb, perderei anche il db al suo interno. Per questo si usano i volumi. 
Il db salva i dati nel volume e questo, anche se facciamo docker rm mariadb, rimane per il futuro 

```text
Container
┌──────────────┐
│ MariaDB      │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Volume       │
└──────────────┘
```

Un altro container potrà usare lo stesso volume e ritrovare i dati salvati 

avere il db in un container ti permette anche di gestire diverse versioni del programma usato. Ad esempio in un progetto abbiamo postgressql 17 in un altro il 14, con i container è più sicuro e semplice gestire le due versioni differenti. 

### differenza tra db e volume

Un database è un programma. Un volume è semplicemente uno spazio dove quel programma salva i file.
è una cartella a parte dal programma, dove sono salvati i file binari, a cui il programma ha accesso 

```text
Container
┌─────────────────────────┐
│ PostgreSQL              │
│ /var/lib/postgresql/data│
└─────────────┬───────────┘
              │
              ▼
┌─────────────────────────┐
│ Docker Volume           │
│ base/                   │
│ global/                 │
│ pg_wal/                 │
│ ...                     │
└─────────────────────────┘
```

Postgres pensa di scrivere in .../data ma in realtà docker sta reinderizzando quella cartella verso il volume.

Quindi:

Container = esegue un programma.
Volume = conserva i file prodotti o utilizzati da quel programma.
Database = un tipo di programma che legge e scrive dati su quei file.

### Differenza tra mariaDb e postgreSQL

entrambi sono i db relazionali più usati insieme a MySQL. 

mariaDB nasce come fork di mysql è molto semplice e veloce da usare
postgressql è nato dopo con lo scopo di renderlo più completo e robusto e per fare richieste più complesse e concatenate

## Redis

è una memoria gigante, invece di leggere dal disco, tiene tutto in ram. Per questo si usa per accedere ai dati che si usano spesso, più velocemente. Altrimenti si rischia di dover flooddare inutilmente il db di richieste. 
Il db salva su disco, redis in memoria, e questa a na certa viene liberata.
Redis può periodicamente salvare i dati su disco volendo.  
Utente

↓

Redis

↓

PostgreSQL

può salvare qualsiasi tipo di dato, non solo stringhe 

In docker-compose.yml spesso si vede roba tipo 

services:
  app:
    ...

  postgres:
    ...

  redis:
    ...

ogni componente ha un compito diverso:
postgressql ( o mariaDB nel nostro caso ) salva i dati in modo permanente
Redis: rende il sistema + veloce e gestsce dati temporanei
app: esegue la logica del programma

## NGINX
è il "portiere" dell'infrastruttura: riceve le richieste, le smista, serve file statici, gestisce HTTPS e può distribuire il carico tra più applicazioni.

è un web server: riceve tutte le richieste e le smista. Ad esempio scrivi 
/ nginx decide di mandarti alla root
/images/logo.png (quindi tutti i file statici di un sito)nginx prende direttamente il file e lo restituisce senza fare ogni volta una richiesta a next.js ad esempio
/api/login nginx la inoltra direttamente al backend

Internet

↓

Nginx

↓

app

è un reverse proxy cioè nginx riceve le richieste e le gira al server corretto
in questo modo hai tanti servzi ma esponi solo 443, cioè nginx e poi ci pensa lui

quando digitiamo https, il certificato lo gestisce nginx
è utile per load balancing 
sicurezza:
Nginx può bloccare:

richieste troppo grandi
IP sospetti
bot
attacchi banali

## Wordpress

è una enorme applicazione in php con dentro già diversi file e cartelle. Quando vai sul dominio succede questo:

Browser

↓

Nginx / Apache

↓

PHP

↓

WordPress

↓

MariaDB / MySQL

↓

WordPress

↓

Browser

WP è il software che genera le pagine, salva tutto in DB 
Quando scrivi un blog post non viene generata una pagina html ma un record all'interno del db 
Quando poi visiti la pagina del blogpost, wp legge il db, trova l'articolo, genera l'html e lo invia al browser 
le immagini sono dei file, il db salva solo il percorso e poi vengono caricate 

Perchè Wp ha bisogno di un volume a parte oltre a quello del db? 

usando l'esempio delle immagini:
quando carichi una immagine, il file va dentro al volume di wp, mentre il percorso viene salvato nel volume del db.
Perchè non inserirlo nel volume del db? perchè i db sono ottimizzati per testo, numeri, relazioni e query. Non per gestire le immagini
nel volume di wp vengono salvati anche i plugin , temi ecc

QUINDI a completamento del discorso di prima: 
Un'applicazione può avere più volumi, ciascuno con uno scopo diverso.

schema per il progetto

```text
Docker
┌──────────────────────┐
│      WordPress       │
└──────────┬───────────┘
           │
           │
           ▼
   Volume wp-content
   (upload, temi, plugin)

           │
           ▼
┌──────────────────────┐
│      MariaDB         │
└──────────┬───────────┘
           │
           ▼
    Volume database
```

## server ftp 

file transfer protocol, protocollo per trasferire file tra due computerno. Sul server installi qualcosa tipo vsftpd che rimane in ascolto. 

Se facciamo un FTP container, in pratica facciamo la stessa cosa: cambia solo dove il programma viene eseguito, il processo è lo stesso ( vsftpd ) e salva i file che riceve in una cartella che viene dirottata verso il volume di wp. 




senza docker

```text
Linux
├── Processo Nginx
├── Processo MariaDB
├── Processo vsftpd
└── Processo PHP
```

con docker:

```text
Linux
├── Processo Nginx   (filesystem A)
├── Processo MariaDB (filesystem B)
├── Processo vsftpd  (filesystem C)
└── Processo PHP     (filesystem D)
```

docker usa funzionalità del kernel come namespaces e cgroups per far credere a ciascun processo di essere in un ambiente separato. 

# Docker non virtualizza un computer. Virtualizza l'ambiente in cui gira un processo.

## Adminer

è un'applicazione web che ti permette di amministrare un db dal browser, è solo una interfaccia grafica 

Browser

↓

Adminer

↓

MariaDB

↓

risultati

↓

Adminer

↓

Browser


Docker Network

```text
┌──────────────┐
│   Adminer    │
└──────┬───────┘
       │
       │ SQL
       ▼
┌──────────────┐
│   MariaDB    │
└──────────────┘
```

Adminer si collega a MDB come farebbe php, non vede il volume, fa le query che arrivano a MDB, MDB legge i file, restituisce il risultato, Adminer lo visualizza. Fine

Adminer è un client.

Esattamente come:

Chrome è un client HTTP.
FileZilla è un client FTP.
Un client IRC parlerà con il tuo ft_irc.

La differenza è solo il protocollo:

Browser ⇄ Nginx → HTTP
FileZilla ⇄ FTP Server → FTP
Adminer ⇄ MariaDB → protocollo del database (MySQL/MariaDB o PostgreSQL)

tutti questi componenti seguono lo stesso schema:
client -> server-> dati

Chrome → Nginx → file HTML
FileZilla → FTP Server → filesystem
Adminer → MariaDB → database

## Docker-compose.YAML
Serve a dire come devono essere collegati e avviati i container

es:

services:

  mariadb:
    image: mariadb:11
    volumes:
      - db_data:/var/lib/mysql

  adminer:
    image: adminer
    ports:
      - "8080:8080"

volumes:
  db_data:

services: 
tutto ciò che sta sotto sono i servizi che compongono l'applicazione
mariadb:
nome logico del servizio 
image:
crea l'immagine a partire da mariadb vers. 11
volumes:
      - db_data:/var/lib/mysql
questa riga significa che il volume Docker db_data viene montato dentro al container, punto di mount /var/lib/mysql
quindi il volume non vive in quel path, è semplicemente montato li 

se il volume non esiste, lo crea
poi crea il container
poi collega il volume
mariaDB inizia a scrivere in /var/lib/ecc, docker lo intercetta e scrive dove effettivamente è storato in db ovvero nel computer host ( in una cartella di docker )

Host
│
├── Docker
│     │
│     └── Volume db_data
│
└── Container MariaDB
      │
      └── /var/lib/mysql

Supponiamo di avere qualcosa tipo:

services:

  wordpress:
    image: wordpress
    volumes:
      - wordpress_data:/var/www/html

  ftp:
    image: vsftpd
    volumes:
      - wordpress_data:/home/ftp

in questo caso il volume è lo stesso, cambia solo il punto di mount ( la "porta" da cui si ha accesso a quel volume ). Essendo ogni processo isolato, quei path sono solo il punto in cui il volume appare dentro al container.
Quando parte,  docker dice al kernel "monta questa cartella in questo punto dentro a questo container" fine. Ovviamente i servizi non sanno nulla di docker, "pensano" di scrivere nel loro filesystem, ma in realtà docker intercetta tutto.

### Named Volume vs Bind Mount

volumes:
  - db_data:/var/lib/mysql

db_data è un volume gestito da Docker. QUesto è Named Volume 

volumes:
  - ./my_project:/app
questa è una cartella sull'host montata nel container /app. Questo è Bind Mount. Ovviamente tutte le modifiche nella cartella si riflettono nel container 

Quando usare uno o l'altro? 
tendenzialmente la domanda che devo farmi è: questi sono miei dati o dati dell'app? 
per miei dati, ad esempio potrei riferirmi a del codice
dati dell'app, quelli generati dall'app stessa e lo gestisce docker per me

I named volumes servono per separare i dati dell'applicazione dal codice dell'applicazione.

## Docker Networks

Una Docker Network è una rete virtuale creata da Docker che permette ai container di comunicare tra loro in modo isolato dal resto del sistema.

Quando due container appartengono alla stessa Docker Network:

possono comunicare direttamente;
possono risolversi tramite il nome del servizio (postgres, redis, ecc.);
il traffico rimane interno alla rete Docker e non passa sulla rete fisica del computer.

In pratica Docker crea una LAN privata per i container, isolando di fatto tutti i container dalla rete dell'host.

                 Host

            192.168.1.50
                  │
          ┌───────┴────────┐
          │ Docker Network │
          └───────┬────────┘
                  │
      ┌───────────┼───────────┐
      ▼           ▼           ▼
   app        postgres      redis
172.18.0.2   172.18.0.3   172.18.0.4


I container sono come "mini pc" isolati tra loro, quindi non sanno dove si trova, ad esempio, il volume. Ma docker lo sa. QUindi se da dentro il container "app" io dovessi accedere al volume db_data attraverso il container mariadb, io dovrei cercare mariadb, docker sa che, se legge mariadb, deve risolvere il nome e instradare la richiesta verso quel container specifico. Ogni servizio ha un DNS associato ad un nome. Quindi lui sa che mariadb corrisponde ad un indirizzo preciso e fa una specie di redirect verso quell'indirizo. Ecco anche perchè compose usa i nomi dei servizi, li usa come hostname. 
Come fa app a sapere che c'è "mariadb" a cui fare la richiesta per scrivere dati? tramite un env. Praticamente ogni container ha un env dove sono segnati tutte ste robe 

environment:
  DB_HOST: mariadb
  DB_USER: wordpress
  DB_PASSWORD: password

Vantaggi della Docker Network
isolamento tra applicazioni;
nessun conflitto tra porte interne;
DNS automatico;
maggiore sicurezza;
è il comportamento predefinito di Docker.

## Host Network 

La Host Network è una modalità in cui il container non usa una rete virtuale propria.

Invece, utilizza direttamente la rete del computer host.

Questo significa che il container condivide:

gli indirizzi IP;
le interfacce di rete;
le porte

con il sistema operativo host.

Non c'è alcun livello di isolamento di rete.

Host

192.168.1.50

├── Next.js
├── PostgreSQL
├── Redis

Vantaggi della Host Network
niente livello di virtualizzazione della rete;
leggermente meno overhead;
utile quando un'applicazione deve usare direttamente la rete dell'host.