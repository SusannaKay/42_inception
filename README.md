# 42_inception

## Indice

- [Docker](#docker)
- [Kernel](#kernel)
- [Database](#database)
- [Redis](#redis)
- [NGINX](#nginx)
- [WordPress](#wordpress)
- [Server FTP](#server-ftp)
- [Adminer](#adminer)
- [Docker Networks](#docker-networks)
- [Docker Compose YAML](#docker-compose-yaml)
- [Dockerfile](#dockerfile)
- [Docker-compose.yml](#docker-composeyml)
- [Comandi terminale](#comandi-terminale)

## Docker

Docker permette di impacchettare un'applicazione insieme a tutto ciò di cui ha bisogno per funzionare.

Non solo codice, ma anche OS minimo, Node, Python, Redis, DB, librerie varie e configurazione.

Ci sono 3 concetti di Docker da capire:

1. Image: è il progetto già preparato.
2. Container: è un'istanza di Image.
3. Dockerfile: file che dice a Docker come costruire l'immagine.

Flow:

docker legge il file, costruisce l'immagine e poi crea un container.

Il container è come se fosse una piccola VM, con la differenza che la VM contiene hardware virtuale, BIOS, OS completo e programmi. Il container invece usa direttamente il kernel del sistema operativo host.

Docker in sostanza avvia processi: ogni container per il kernel è solo un processo separato.



### Kernel

È il programma che viene caricato subito dopo il boot del computer e rimane in esecuzione fino allo spegnimento. Controlla tutto l'hardware, ed ogni programma dialoga con lui per le richieste: malloc, apertura file (con relativa assegnazione fd), utilizzo CPU, gestione RAM, fork, execve ecc. Tutto passa per il kernel.

Con Docker i container girano sullo stesso kernel; in una VM invece ogni VM ha il suo kernel.

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

In una macchina virtuale, gira un intero sistema operatovo con un init system che gestisce i servizi in background (deamons).
In Docker, il container esiste unicamente finché il suo processo principale (PID 1) é in esecuzione. 

#### Perché il subject vieta l'uso di tail o sleep?
Perché utilizzandoli per non far terminare il container lo stiamo artificialmente trasformando in una finta VM. 
Il processo primario diventa tail o sleep anziché il server web o il db ( ad esempio). 
Il kernel inoltra i segnali di stop esclusivamente al PID 1 all'interno dell'ambiente isolato. 
tail o sleep ignorano o non gestiscono questi segnali per i sotto processi. Quindi quando Docker tenta di arrestare il container, il servizio associato non riceve il segnale di chiusura e si rischia la corruzione dei dati. 
Inoltre da subject, i container si devono riavviare automaticamente in caso di arresto anomalo. Usando tail -f su pid1, docker non se ne accorge perché tail sta ancora in piedi ( anche se il servizio é morto ) ed il container rimane attivo. 

#### Come gestire quindi i processi da subject?
Ogni servizio va configurato per girare direttamente in foreground ( e non in background ).

#### Background vs Foreground

La differenza sta nel modo in cui un programma interagisce con il terminale e con il ciclo di vita dell'ambiente in cui é eseguito. 

Foreground:
Questo tipo di processo prende il controllo del terminale.
Output tipo stdout e stderr vengono direttamente stampati a schermo
la shell resta bloccata finché il programma non termina

Docker é progettato specificamente per monitorare un singolo processo (PID1) Se questo processo gira in foreground, docker sa esattamente quando é vivo, quando produce log, quando smette di funzionare.

Esempi di processi foreground:
- cat
- top
- nginx -g 'deamon off;' ( avvia NGINX agganciandolo al terminale )

Background:

Un processo in background (Deamons) appena parte viene sganciato dal terminale. 
Il processo viene lanciato in memoria e restituisce subito exit code 0 alla shell. 
Su VM/Linux/server fisico, software tipo MariaDB o NGINX vengono avviati in background, lasciando a systemd il compito di monitorarli. 

Se in un container Docker lanciamo un comando in background, il comando iniziale termina subito ( exit code restituito ) ed il container si spegne all'istante.

E questo puo' indurre ad usare tail/sleep per mantenere vivo il container. Quindi la limitazione del subject é per costringerci a runnare i processi in foreground. 

#### PID 1

Il PID1 é il primo processo avviato dal kernel all'interno di un namespace. é l'init process. 

il PID namespace é una funzionalitá del kernel Linux che permette a un gruppo di processi di avere una propria numerazione dei PID, separata dal resto del sistema. Cambia il modo in cui alcuni processi vedono e numerano i processi. 

Quindi dockerd sul sistema avrá il suo PID, poi Docker crea un container usando PID namespace, e il primo processo lanciato dentro al container avrá PID1. Tutti i processi figli avranno PID2, PID3 ecc. ma solo all'interno del container.

```text
VM:
Host kernel
   │
   ├── VM1 → kernel proprio → PID 1
   └── VM2 → kernel proprio → PID 1

Docker:
Host kernel
   │
   ├── PID namespace A → vede nginx come PID 1
   └── PID namespace B → vede mariadb come PID 1
´´´
Nei processi standard con PID diverso da 1, se il kernel invia un segnale SIGTERM o SIGINT, il sistema arresta il programma immediatamente. 

Il PID1 segue regole diverse:
- il kernel disabilita i gestori di default dei segnali per proteggere l'OS da crash accidentali del processo init. 
- Il PID1 riceve un segnale solo se il codice dell'applicazione ha definito un gestore per quel segnale ( signal handler ).

Con Docker stop:
- docker invia un segnale SIGTERM al PID1
- se PID1 é NGNIX o MariaDB che implementano un gestore di segnali, il servzio avvia un graceful shutdown ( quindi salva tutto, chiude correttamente le connessioni e termina pulito )
- Se PID1 é uno script o comando tipo tail/sleep, questo ignora SIGTERM, Docker attende il timeout di sicurezza (10 secondi) e poi invia SIGKILL.

Processi zombie:
Quando un processo genera un processo figlio e poi termina prima del figlio:
- il processo figlio diventa orfano
- il kernel riassegna automaticamente l'orfano al nuovo pid1
- quando il figlio termina la sua esecuzione, diventa un processo zombie: non occupa CPU, ma occupa uno slot nella PT del kernel ( process table ),o finché il genitore non legge exit status con wait() o waitpid().
Se il PID1 non gestisce waith(), la PT puó riempirsi di processi zombie, esaurendo i PID disponibili per quel container.

Se nel Dockerfile scriviamo
ENTRYPOINT ["/entrypoint.sh"]

all'avvio, il comando eseguito sará entrypoint.sh ed avrá PID1.
Poi avviamo MariaDB in background e poi attende tail -f

bash avrá PID1
MariaDB PID2
tail PID3

con docker stop, docker invia lo SIGTERM a PID1, che peró non inoltra ai processi figli e dopo 10sec arriva SIGKILL. 

Piú avanti la soluzione a questo problema.

-

Nel container, il PID1 é il processo lanciato da ENTRYPOINT o CMD. 

esempio:

```dockerfile
FROM debian:12
RUN apt update && apt install -y nginx
CMD ["nginx", "-g", "daemon off;"]
```

Dentro il container, nginx sará PID1. 

C'é differenza tra

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```
e
```dockerfile
CMD nginx -g "daemon off;"
```

Nel primo caso Docker esegue direttamente il binario nginx, che diventa PID1.

Nel secondo caso Docker esegue la shell, che diventa PID1, e la shell avvia nginx come processo figlio. 
In questo caso, se il container riceve SIGTERM, la shell lo ignora e non inoltra il segnale a nginx, che resta in esecuzione. Dopo 10 secondi, Docker invia SIGKILL alla shell, che muore.


## Database

Da subject, ma in generale può stare in un altro container.

Quindi in uno c'è l'app, in un altro c'è il DB. Ogni container è separato.

Con Docker Compose avvio tutti i container insieme. Se dovessi rimuovere il container mariadb, perderei anche il DB al suo interno. Per questo si usano i volumi.

Il DB salva i dati nel volume e questo, anche se faccio `docker rm mariadb`, rimane per il futuro.

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

Un altro container potrà usare lo stesso volume e ritrovare i dati salvati.

Avere il DB in un container ti permette anche di gestire diverse versioni del programma usato. Ad esempio in un progetto abbiamo PostgreSQL 17, in un altro il 14: con i container è più sicuro e semplice gestire le due versioni differenti.

### Differenza tra DB e volume

Un database è un programma. Un volume è semplicemente uno spazio dove quel programma salva i file.

È una cartella separata dal programma, dove sono salvati i file binari a cui il programma ha accesso.

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

PostgreSQL pensa di scrivere in `.../data`, ma in realtà Docker sta reindirizzando quella cartella verso il volume.

Quindi:

- Container = esegue un programma.
- Volume = conserva i file prodotti o utilizzati da quel programma.
- Database = un tipo di programma che legge e scrive dati su quei file.

### Differenza tra MariaDB e PostgreSQL

Entrambi sono DB relazionali molto usati insieme a MySQL.

- MariaDB nasce come fork di MySQL; è molto semplice e veloce da usare.
- PostgreSQL è nato con l'obiettivo di essere più completo e robusto, e per gestire richieste più complesse e concatenate.

## Redis

È una memoria gigante: invece di leggere dal disco, tiene tutto in RAM. Per questo si usa per accedere ai dati usati spesso, più velocemente.

Altrimenti si rischia di floodare inutilmente il DB di richieste.

Il DB salva su disco, Redis in memoria, e questa a un certo punto viene liberata.

Redis può anche periodicamente salvare i dati su disco.

```text
Utente
↓
Redis
↓
PostgreSQL
```

Redis può salvare qualsiasi tipo di dato, non solo stringhe.

In `docker-compose.yml` spesso si vede qualcosa del genere:

```yaml
services:
  app:
    ...

  postgres:
    ...

  redis:
    ...
```

Ogni componente ha un compito diverso:

- PostgreSQL (o MariaDB) salva i dati in modo permanente.
- Redis rende il sistema più veloce e gestisce dati temporanei.
- L'app esegue la logica del programma.

## NGINX

NGINX è il "portiere" dell'infrastruttura: riceve le richieste, le smista, serve file statici, gestisce HTTPS e può distribuire il carico tra più applicazioni.

È un web server: riceve tutte le richieste e le smista.

Esempi:

- `/` → NGINX decide di mandarti alla root.
- `/images/logo.png` → NGINX prende direttamente il file e lo restituisce senza passare per Next.js.
- `/api/login` → NGINX inoltra la richiesta al backend.

```text
Internet
↓
Nginx
↓
app
```

NGINX è un reverse proxy: riceve le richieste e le gira al server corretto. In questo modo hai tanti servizi ma esponi solo la porta 443.

Quando digitiamo HTTPS, il certificato lo gestisce NGINX.

È utile anche per il load balancing e per la sicurezza.

NGINX può bloccare:

- richieste troppo grandi
- IP sospetti
- bot
- attacchi banali

## WordPress

WordPress è una grande applicazione in PHP con già diversi file e cartelle.

Quando vai sul dominio succede questo:

```text
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
```

WP è il software che genera le pagine e salva tutto nel DB.

Quando scrivi un blog post non viene generata una pagina HTML, ma un record all'interno del DB.

Quando visiti la pagina del blog post, WP legge il DB, trova l'articolo, genera l'HTML e lo invia al browser.

Le immagini sono file; il DB salva solo il percorso e poi vengono caricate.

### Perché WordPress ha bisogno di un volume a parte oltre a quello del DB?

Usando l'esempio delle immagini:

- il file va nel volume di WP;
- il percorso viene salvato nel volume del DB.

Perché non salvarlo nel volume del DB? Perché i DB sono ottimizzati per testo, numeri, relazioni e query, non per gestire immagini.

Nel volume di WP vengono salvati anche plugin, temi, upload, ecc.

Quindi: un'applicazione può avere più volumi, ciascuno con uno scopo diverso.

### Schema per il progetto

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

## MariaDB




## Server FTP

FTP è un protocollo per trasferire file tra due computer. Sul server si installa qualcosa come `vsftpd` che rimane in ascolto.

Se facciamo un container FTP, in pratica facciamo la stessa cosa: cambia solo dove il programma viene eseguito. Il processo è lo stesso (`vsftpd`) e salva i file che riceve in una cartella montata sul volume di WP.

### Con e senza Docker

```text
senza docker
Linux
├── Processo Nginx
├── Processo MariaDB
├── Processo vsftpd
└── Processo PHP
```

```text
con docker
Linux
├── Processo Nginx   (filesystem A)
├── Processo MariaDB (filesystem B)
├── Processo vsftpd  (filesystem C)
└── Processo PHP     (filesystem D)
```

Docker usa funzionalità del kernel come namespaces e cgroups per far credere a ciascun processo di essere in un ambiente separato.

# Docker non virtualizza un computer. Virtualizza l'ambiente in cui gira un processo.

## Adminer

Adminer è un'applicazione web che ti permette di amministrare un DB dal browser; è solo un'interfaccia grafica.

```text
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
```

### Docker Network con Adminer

```text
┌──────────────┐
│   Adminer    │
└──────────────┬───────┘
       │
       │ SQL
       ▼
┌──────────────┐
│   MariaDB    │
└──────────────┘
```

Adminer si collega a MariaDB come farebbe PHP: non vede il volume, fa le query che arrivano a MariaDB, MariaDB legge i file, restituisce il risultato e Adminer lo visualizza.

Adminer è un client.

Esattamente come:

- Chrome è un client HTTP.
- FileZilla è un client FTP.
- Un client IRC parla con il tuo ft_irc.

La differenza è solo il protocollo:

- Browser ⇄ Nginx → HTTP
- FileZilla ⇄ FTP Server → FTP
- Adminer ⇄ MariaDB → protocollo del database (MySQL/MariaDB o PostgreSQL)

Tutti questi componenti seguono lo stesso schema:

client → server → dati

- Chrome → Nginx → file HTML
- FileZilla → FTP Server → filesystem
- Adminer → MariaDB → database

## Docker Compose YAML

Serve a dire come devono essere collegati e avviati i container.

Esempio:

```yaml
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
```

`services:` definisce i servizi che compongono l'applicazione.

- `mariadb:` è il nome logico del servizio.
- `image:` crea l'immagine a partire da `mariadb:11`.
- `volumes:` monta il volume Docker `db_data` nel container su `/var/lib/mysql`.

Quindi il volume non vive in `/var/lib/mysql`, è semplicemente montato lì.

Se il volume non esiste, Docker lo crea, poi crea il container e collega il volume. MariaDB inizia a scrivere in `/var/lib/...`, Docker intercetta e salva i dati nel volume sul computer host.

```text
Host
│
├── Docker
│     │
│     └── Volume db_data
│
└── Container MariaDB
      │
      └── /var/lib/mysql
```

Supponiamo di avere questo:

```yaml
services:
  wordpress:
    image: wordpress
    volumes:
      - wordpress_data:/var/www/html

  ftp:
    image: vsftpd
    volumes:
      - wordpress_data:/home/ftp
```

In questo caso il volume è lo stesso, cambia solo il punto di mount. Essendo ogni processo isolato, quei path sono solo il punto in cui il volume appare dentro al container.

Quando parte, Docker dice al kernel: "monta questa cartella in questo punto dentro questo container". I servizi non sanno nulla di Docker: pensano di scrivere nel loro filesystem, ma in realtà Docker intercetta tutto.

### Named Volume vs Bind Mount

```yaml
volumes:
  - db_data:/var/lib/mysql
```

`db_data` è un volume gestito da Docker. Questo è un Named Volume.

```yaml
volumes:
  - ./my_project:/app
```

Questa è una cartella sull'host montata nel container `/app`: un Bind Mount. Tutte le modifiche nella cartella si riflettono nel container.

Quando usare uno o l'altro?

- Se sono dati tuoi, ad esempio codice, usa un bind mount.
- Se sono dati dell'app generati al runtime, usa un named volume.

I named volumes servono a separare i dati dell'applicazione dal codice dell'applicazione.

## Docker Networks

Una Docker Network è una rete virtuale creata da Docker che permette ai container di comunicare tra loro in modo isolato dal resto del sistema.

Quando due container appartengono alla stessa Docker Network:

- possono comunicare direttamente;
- possono risolversi tramite il nome del servizio (`postgres`, `redis`, ecc.);
- il traffico rimane interno alla rete Docker e non passa sulla rete fisica del computer.

In pratica Docker crea una LAN privata per i container, isolando di fatto tutti i container dalla rete dell'host.

```text
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
```

I container sono come "mini PC" isolati tra loro, quindi non sanno dove si trova il volume. Ma Docker lo sa.

Se da dentro il container `app` io dovessi accedere al volume `db_data` attraverso il container `mariadb`, Docker risolverebbe il nome `mariadb` e instraderebbe la richiesta verso quel container specifico.

Ogni servizio ha un DNS associato a un nome. Ecco perché Compose usa i nomi dei servizi come hostname.

Come fa l'app a sapere che `mariadb` è il DB a cui connettersi? Tramite una variabile d'ambiente.

```yaml
environment:
  DB_HOST: mariadb
  DB_USER: wordpress
  DB_PASSWORD: password
```

Vantaggi della Docker Network:

- isolamento tra applicazioni;
- nessun conflitto tra porte interne;
- DNS automatico;
- maggiore sicurezza;
- è il comportamento predefinito di Docker.

## Host Network

La Host Network è una modalità in cui il container non usa una rete virtuale propria.

Invece, utilizza direttamente la rete del computer host.

Questo significa che il container condivide:

- gli indirizzi IP;
- le interfacce di rete;
- le porte;

con il sistema operativo host.

Non c'è alcun livello di isolamento di rete.

```text
Host

192.168.1.50

├── Next.js
├── PostgreSQL
├── Redis
```

Vantaggi della Host Network:

- niente livello di virtualizzazione della rete;
- leggermente meno overhead;
- utile quando un'applicazione deve usare direttamente la rete dell'host.

## Immagine vs Container

Una Docker image è un modello immutabile che contiene:

- un filesystem;
- programmi e librerie;
- configurazioni di base;
- istruzioni su quale processo avviare.

Un container è un'istanza in esecuzione di quell'immagine e vive finché vive il suo processo principale.

Tutti i container condividono lo stesso kernel della VM, quindi partono rapidi, consumano poca RAM e possono coesistere centinaia di container contemporaneamente. Sono letteralmente processi isolati.

Dalla stessa immagine puoi creare più container tutti indipendenti tra loro.

Ogni immagine è composta da più layer:

```text
+---------------------------+
| Layer 5  (CMD bash)       |
+---------------------------+
| Layer 4  (apt install)    |
+---------------------------+
| Layer 3  (copia file)     |
+---------------------------+
| Layer 2  (configurazione) |
+---------------------------+
| Layer 1  (filesystem base)|
+---------------------------+
```

Ogni layer rappresenta una modifica al filesystem. Ogni istruzione nel Dockerfile crea un nuovo layer.

I layer sono riutilizzabili: se modifichi il layer 4, vengono ricostruiti solo i layer 4 e 5, non tutti dall'inizio.

I layer per il container sono read-only. Quando un container viene avviato, Docker aggiunge un ultimo layer sopra all'immagine che è un write layer, l'unico scrivibile. Qui vengono salvate le modifiche del container.

Se crei un nuovo container dalla stessa immagine, avrà un write layer diverso.

Ecco perché servono i volumi per il DB: i dati restano esterni al container e al write layer. Se il container viene eliminato, il DB no.

## Dockerfile

È un insieme di istruzioni che Docker legge per costruire l'immagine. Docker prende queste istruzioni e costruisce l'immagine layer dopo layer.

### FROM
E' la prima riga del Dockerfile.

`FROM <image>` indica la base dell'immagine che poi il build estenderá. Può essere un'immagine ufficiale di Docker Hub, oppure un'immagine che ho creato. 

Nel nostro caso, la base sará l'OS scelto (alpine o debian)

Ogni immagine ufficiale ha un tag che indica la versione. Ad esempio `debian:12` o `alpine:3.18`. Se non viene indicato, Docker prende l'ultima versione disponibile. 

### RUN

`RUN <comando>` esegue un comando all'interno del container temporaneo e salva le modifiche in un nuovo layer. Il container temporaneo viene eliminato. 
Esempio:

```dockerfile
RUN apt update
RUN apt install -y nginx
```

### COPY

`COPY` prende file dal build context e lo copia nella cartella specificata.

Ad esempio:

```dockerfile
COPY index.html /tmp/
```

Copia il file index.html nella destinazione /tmp/ , processo che avviene durante la build time (non il run time). Se modifichi il file nella cartella di build, devi rebuildare l'immagine.

### EXPOSE

EXPOSE <porta> imposta la config dell'immagine, e gli indica quale porta dovrá esporre. Dirá a Docker che il container ascolta su quella porta. 

### CMD

`CMD <comando>` indica il comando da eseguire quando il container parte. Può essere sovrascritto con `docker run <image> <comando>`.

### ENTRYPOINT

`ENTRYPOINT <comando>` indica il comando da eseguire quando il container parte. Non può essere sovrascritto con `docker run <image> <comando>`.

#### Differenza tra CMD e ENTRYPOINT

- CMD Fornisce un comando o argomenti predefiniti per il container. Puó essere sovrascritto al momento dell'esecuzione del container.
- ENTRYPOINT Imposta un comando fisso che viene eseguito quando il container parte. Con Docker run <image> <comando> il comando verrá aggiunto in coda ad ENTRYPOINT, diventando argomento di ENTRYPOINT. 


#### Build time

I comandi eseguiti durante la build sono:

- `FROM`
- `RUN`
- `COPY`
- `ADD`

Queste istruzioni vengono eseguite una sola volta durante `docker build`.

#### Run time

I comandi e le risorse usate all'esecuzione sono:

- `CMD`
- `ENTRYPOINT`
- volumi
- reti
- env var
- porte

Vengono usati quando fai `docker run` oppure `docker compose`.



### Regola generale

- i file di configurazione si copiano nell'immagine;
- tutto ciò che invece si aggiorna lo metti in volume.

```text
IMAGE
├── nginx installato
├── nginx.conf
└── certificati/configurazioni statiche

VOLUME
└── dati creati durante l'esecuzione
```

## Docker-compose.yml

docker-compose.yml è un file di configurazione che permette di definire e gestire più container come un'unica applicazione.

Dockerfile descrive come costruire un'immagine, mentre docker-compose.yml descrive come più container interagiscono tra loro, quali immagini usare, come collegarli in rete, quali volumi montare e quali variabili d'ambiente impostare.
L'indentazione in questo file é importante. All'interno abbiamo 4 sezioni principali:

### Services

La sezione `services` definisce i container che compongono l'applicazione. Ogni servizio rappresenta un container o un insieme di container che eseguono la stessa immagine. Per ogni servizio puoi specificare:

- `image`: l'immagine Docker da usare per il servizio. La recupera giá pronta da un registry ( es. Docker Hub, anche se noi useremo immagini locali ).

- `build`: Dice a Compose di compilare un'immagine al volo a partire da un Dockerfile presente in una directory locale (context).

- `ports`: (Port Mapping. Sintassi HOST:CONTAINER ), rende le porte del container accessibili dall'esterno. Ad esempio, `8080:80` significa che la porta 80 del container sarà accessibile sulla porta 8080 dell'host.

- `expose`: Rende le porte accessibili solo agli altri container presenti nella stessa rete Compose, senza esporle al mondo esterno o all'host.

- `volumes`: monta volumi o directory locali nel container.

- `environment`: imposta variabili d'ambiente per il container.

- `env_file`: permette di caricare variabili d'ambiente da un file esterno.

- `depends_on`: specifica le dipendenze tra i servizi, assicurando che un servizio venga avviato solo dopo che i servizi da cui dipende sono pronti. Quindi ad esempio `depends_on: - mariadb` significa che il servizio corrente aspetta che il servizio `mariadb` sia avviato prima di partire. 

- `restart`: definisce la politica di riavvio del container in caso di arresto o crash. Ad esempio: 
  - `restart: always` farà sì che il container venga riavviato automaticamente se si ferma. 
  - `restart:unless-stopped`: il container si riavvia automaticamente a meno che non venga fermato manualmente.
  - `restart:on-failure`: il container si riavvia solo se termina con un codice di errore (diverso da 0).
  - `restart:no` non riavvia mai il container automaticamente.

### Networks

Definisce le reti virtuali che collegano i container tra loro. In maniera predefinita, Compose crea una rete privata in cui tutti i container possono comunicare tra loro usando i nomi dei servizi come hostname tramite il DNS interno di Docker.

Se non specifico nulla, Docker crea in automatico una rete di tipo bridge.
- Tutti i servizi dichiarati nel file vengono inseriti in questa rete comune.
- Ciascun container puó raggiungere gli altri semplicemente usando il nome del servizio come hostname. 

- `bridge`: driver predefinito per singolo host, crea uno switch virtuale isolato all`interno della macchina. I container comunicano tra loro e possono uscire su internet via NAT. Ma sono invisibili dall-esterno a meno di port-mapping. 
- `host`: rimuove l`isolamento di rete tra container e host. Il container condivide lo stack di rete dell host.


- Custom bridge network: rete bridge personalizzata, creato e gestito dal deamon Docker sull'host. A differenza delle bridget predefinite, offrono controllo, collegamento e scollegamento a runtime senza riavvio, supporto DNS automatico. 

Flusso di comunicazione tra container:

Quando un container si avvia all'interno di una rete, Docker configura il suo file `/etc/resolv.conf` con l'indirizzo IP del DNS interno della rete. 

Se una applicazione tenta di connettersi ad un altro container usando il nome del servizio, l'os del container invia la richiesta per il nome_servizio al DNS interno.
Il server DNS di DOcker consulta la tabella interna della rete per trovare l'IP corretto e restituisce la risposta al container richiedente.


### Volumes

Permette di dichiarare e gestire volumi dedicati per mantenere intatti i dati anhe quando i container vengono distrutti o ricreati. Questo perché i container sono effimeri: quando un container viene fermato o rimosso, tutti i dati scritti sul suo layer di scrittura interno ( il writable layer ) vengono persi. I volumi invece sono persistenti e sopravvivono alla vita del container.

Dichiarazione di un volume:

```yaml
volumes:
  db_data:
    driver: local
```
poi referenziato nel servizio:

```yaml
services:
  mariadb:
    image: mariadb:11
    volumes:
      - db_data:/var/lib/mysql
``` 
Qui `db_data` è un volume Docker che viene montato nel container MariaDB su `/var/lib/mysql`, dove il database salva i suoi dati. Anche se il container MariaDB viene rimosso, i dati rimangono intatti nel volume `db_data`.

- NOME_VOLUME:PERCORSO_INTERNO_AL_CONTAINER
se il volume non esiste al primo avvio, Docker lo crea automaticamente.

### secrets

I secrets sono un meccanismo per gestire in modo sicuro informazioni sensibili come password, chiavi API o certificati. Invece di includere queste informazioni direttamente nel file docker-compose.yml o nel codice dell'applicazione, i secrets permettono di mantenerle separate e accessibili solo ai container che ne hanno bisogno.

Rendono i dati accessibili come file temporanei all'interno del container. 

A basso livello: 

Quando assegno un secret ad un container, Docker lo monta all'interno del container come file di testo. 

Per impostazione predefinita, i file vengono montati in `/run/secrets/<nome_secret>`. Il contenuto del file è leggibile solo dal processo principale del container, e non è accessibile da altri container o dall'host.

All'interno del container, il percorso /run/secrets/<nome_secret> è montato come un filesystem temporaneo (tmpfs). 

Architettura logica:

si divide in due passaggi: Dichiarazione globale alla radice del file e poi l'assegnazione selettiva al singolo servizio. 

Dichiarazione globale:

```yaml
secrets:
  db_password:
    file: ./secrets/db_password.txt
```
Da file locale (`file`) legge il contenuto da un file presente su host. Questo file non va incluso nella repo ( quindi va aggiunto a .gitignore ).

se usiamo invece `environment` lo prende direttamente dal file docker-compose.yml.

Assegnazione al servizio:

```yaml
services:
  mariadb:
    image: mariadb:11
    secrets:
      - db_password
```

Il file verrá montato in `/run/secrets/db_password` all'interno del container MariaDB. Il processo principale del container può leggere il contenuto di questo file per ottenere la password del database senza esporla nel file docker-compose.yml o nel codice dell'applicazione.


## Comandi terminale

- `docker run <nome immagine>` crea un container dall'immagine.
flag -v <sorgente>:<destinazione> - monta volume di nome sorgente in destinazione
flag -v <path progetto>:<path dentro container> - monta la cartella del progetto in locale, nella cartella dentro al container
- `docker start <id container>` riattiva un container stoppato ma già creato.
- `docker ps` lista i container attivi.
- `docker ps -a` lista tutti i container (attivi + inattivi).
- `docker images` lista le immagini salvate localmente.
- `docker rm <container id>` rimuove un container.
- `docker history <nome immagine>` mostra i layer dell'immagine.
- `docker build -t <nome immagine> .` costruisce l'immagine.
- `docker volume create <nome volume>` crea un volume Docker, non lo collega peró a nessun container. Per collegarlo <nome volume>:/mountpoint



Altri comandi Docker:

- `docker image ...`
- `docker container ...`
- `docker volume ...`
- `docker network ...`

Dentro al container, se esegui `exit`, il processo principale si chiude e il container si stoppa. Il container esiste ancora, ma è fermo.

