# 42_inception

## Indice

- [Docker](#docker)
- [Database](#database)
- [Redis](#redis)
- [NGINX](#nginx)
- [WordPress](#wordpress)
- [MariaDB](#mariadb)
- [Server FTP](#server-ftp)
- [Adminer](#adminer)
- [Docker Compose YAML](#docker-compose-yaml)
- [Docker Networks](#docker-networks)
- [Host Network](#host-network)
- [Immagine vs Container](#immagine-vs-container)
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

In una macchina virtuale gira un intero sistema operativo, con un init system che gestisce i servizi in background (daemon).
In Docker, il container esiste unicamente finché il suo processo principale (PID 1) è in esecuzione.

#### Perché il subject vieta l'uso di tail o sleep?

Perché utilizzandoli per non far terminare il container lo stiamo artificialmente trasformando in una finta VM.
Il processo primario diventa `tail` o `sleep` anziché, ad esempio, il server web o il DB.
Il kernel inoltra i segnali di stop esclusivamente al PID 1 all'interno dell'ambiente isolato.
`tail` e `sleep` ignorano o non gestiscono questi segnali per i sottoprocessi. Quindi quando Docker tenta di arrestare il container, il servizio associato non riceve il segnale di chiusura e si rischia la corruzione dei dati.
Inoltre, da subject, i container si devono riavviare automaticamente in caso di arresto anomalo. Usando `tail -f` come PID 1, Docker non se ne accorge perché `tail` sta ancora in piedi (anche se il servizio è morto) e il container rimane attivo.

#### Come gestire quindi i processi da subject?

Ogni servizio va configurato per girare direttamente in foreground (e non in background).

#### Background vs Foreground

La differenza sta nel modo in cui un programma interagisce con il terminale e con il ciclo di vita dell'ambiente in cui è eseguito.

**Foreground**

- il processo prende il controllo del terminale;
- l'output (stdout e stderr) viene stampato direttamente a schermo;
- la shell resta bloccata finché il programma non termina.

Docker è progettato specificamente per monitorare un singolo processo (PID 1). Se questo processo gira in foreground, Docker sa esattamente quando è vivo, quando produce log, quando smette di funzionare.

Esempi di processi foreground:

- `cat`
- `top`
- `nginx -g 'daemon off;'` (avvia NGINX agganciandolo al terminale)

**Background**

Un processo in background (daemon), appena parte, viene sganciato dal terminale.
Il processo viene lanciato in memoria e restituisce subito exit code 0 alla shell.
Su VM/Linux/server fisico, software come MariaDB o NGINX vengono avviati in background, lasciando a systemd il compito di monitorarli.

Se in un container Docker lanciamo un comando in background, il comando iniziale termina subito (restituendo l'exit code) e il container si spegne all'istante.

E questo può indurre a usare `tail`/`sleep` per mantenere vivo il container. Quindi la limitazione del subject serve a costringerci a eseguire i processi in foreground.

#### PID 1

Il PID 1 è il primo processo avviato dal kernel all'interno di un namespace: è l'init process.

Il PID namespace è una funzionalità del kernel Linux che permette a un gruppo di processi di avere una propria numerazione dei PID, separata dal resto del sistema. Cambia il modo in cui alcuni processi vedono e numerano i processi.

Quindi `dockerd` sul sistema avrà il suo PID, poi Docker crea un container usando un PID namespace, e il primo processo lanciato dentro al container avrà PID 1. Tutti i processi figli avranno PID 2, PID 3 ecc., ma solo all'interno del container.

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
```

Nei processi standard con PID diverso da 1, se il kernel invia un segnale `SIGTERM` o `SIGINT`, il sistema arresta il programma immediatamente.

Il PID 1 segue regole diverse:

- il kernel disabilita i gestori di default dei segnali, per proteggere l'OS da crash accidentali del processo init;
- il PID 1 riceve un segnale solo se il codice dell'applicazione ha definito un gestore per quel segnale (signal handler).

Con `docker stop`:

- Docker invia un segnale `SIGTERM` al PID 1;
- se il PID 1 è NGINX o MariaDB, che implementano un gestore di segnali, il servizio avvia un graceful shutdown (quindi salva tutto, chiude correttamente le connessioni e termina pulito);
- se il PID 1 è uno script o un comando come `tail`/`sleep`, questo ignora `SIGTERM`: Docker attende il timeout di sicurezza (10 secondi) e poi invia `SIGKILL`.

**Processi zombie**

Quando un processo genera un processo figlio e poi termina prima del figlio:

- il processo figlio diventa orfano;
- il kernel riassegna automaticamente l'orfano al PID 1;
- quando il figlio termina la sua esecuzione diventa un processo zombie: non occupa CPU, ma occupa uno slot nella process table (PT) del kernel, finché il genitore non legge l'exit status con `wait()` o `waitpid()`.

Se il PID 1 non gestisce `wait()`, la PT può riempirsi di processi zombie, esaurendo i PID disponibili per quel container.

**Esempio del problema**

Se nel Dockerfile scriviamo:

```dockerfile
ENTRYPOINT ["/entrypoint.sh"]
```

all'avvio il comando eseguito sarà `entrypoint.sh`, che avrà PID 1. Se lo script avvia MariaDB in background e poi resta in attesa con `tail -f`:

```text
bash     → PID 1
MariaDB  → PID 2
tail     → PID 3
```

Con `docker stop`, Docker invia `SIGTERM` al PID 1, che però non lo inoltra ai processi figli: dopo 10 secondi arriva `SIGKILL`.

Più avanti la soluzione a questo problema.

---

Nel container, il PID 1 è il processo lanciato da `ENTRYPOINT` o `CMD`.

Esempio:

```dockerfile
FROM debian:12
RUN apt update && apt install -y nginx
CMD ["nginx", "-g", "daemon off;"]
```

Dentro il container, `nginx` sarà PID 1.

C'è differenza tra

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

e

```dockerfile
CMD nginx -g "daemon off;"
```

Nel primo caso (forma exec) Docker esegue direttamente il binario `nginx`, che diventa PID 1.

Nel secondo caso (forma shell) Docker esegue la shell, che diventa PID 1, e la shell avvia `nginx` come processo figlio.
In questo caso, se il container riceve `SIGTERM`, la shell lo ignora e non inoltra il segnale a `nginx`, che resta in esecuzione. Dopo 10 secondi Docker invia `SIGKILL` alla shell, che muore.

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

È un sistema di gestione di database relazionali. Si divide in 3 macro componenti:

- **Il daemon** (`mysqld`/`mariadbd`): ascolta sulla porta di rete (nel nostro caso la 3306) le richieste di informazioni. In Docker, questo sarà il PID 1.
- **Il filesystem** (datadir): la directory dove vengono salvati i dati, di default `/var/lib/mysql`. Per il progetto mappo questo path a una cartella fisica dell'host, in modo che i dati persistano dopo lo spegnimento del container.
- **Il client** (`mysql`/`mariadb`): il programma che usiamo per parlare con il daemon.

Quando avviamo MariaDB per la prima volta non c'è nulla: né DB né, ovviamente, utenti. Quindi creeremo uno script iniziale che fa da ponte tra l'installazione e la configurazione.
Lo script dovrà:

1. accendere il daemon temporaneamente;
2. usare il client da CLI per dare le istruzioni SQL necessarie a creare il DB e assegnare le password lette dai secrets;
3. spegnere il daemon;
4. riavviarlo passandogli il controllo (`exec`).

Quando il processo del DB si avvia, la prima cosa che fa è analizzare un file di config per capire come allocare le risorse nell'OS e come si deve interfacciare. Questo file si chiama `50-server.cnf` e viene creato automaticamente da uno script nel momento in cui installiamo `mariadb-server`.

Lo script di installazione inoltre:

- crea un utente di sistema `mysql` che esegue solo processi;
- crea un gruppo di sistema omonimo;
- blocca la shell di questo utente, in modo che nessuno possa mai fare login come `mysql`.

Nel Dockerfile andremo a copiare un altro file di config in cui modificheremo la porta di ascolto (di default è localhost) e il bind address, che di default sarebbe `127.0.0.1` (ovvero ascolterebbe solo all'interno del suo container). Impostandolo a `0.0.0.0:3306` gli diciamo sostanzialmente che attraverso la 3306 può ricevere connessioni dalla rete Docker.

**Volumi**

Nel config file di MariaDB scriveremo che la datadir è `/var/lib/mysql`. In questo modo il daemon salverà i dati in quella cartella *che sta dentro al container*.
Nel `docker-compose.yml`, invece, gli diremo che sì, il suo volume è in quella directory del container, ma la memorizzazione fisica avverrà in `/home/login/data/mariadb` (questa sarà la cartella reale persistente).

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

Docker non virtualizza un computer. Virtualizza l'ambiente in cui gira un processo.

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
└──────┬───────┘
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

È la prima riga del Dockerfile.

`FROM <image>` indica la base dell'immagine che poi la build estenderà. Può essere un'immagine ufficiale di Docker Hub, oppure un'immagine che ho creato.

Nel nostro caso la base sarà l'OS scelto (Alpine o Debian).

Ogni immagine ufficiale ha un tag che indica la versione, ad esempio `debian:12` o `alpine:3.18`. Se non viene indicato, Docker prende l'ultima versione disponibile.

### RUN

`RUN <comando>` esegue un comando all'interno di un container temporaneo e salva le modifiche in un nuovo layer. Poi il container temporaneo viene eliminato.

Esempio:

```dockerfile
RUN apt update
RUN apt install -y nginx
```

### COPY

`COPY` prende file dal build context e li copia nella cartella specificata.

Ad esempio:

```dockerfile
COPY index.html /tmp/
```

Copia il file `index.html` nella destinazione `/tmp/`, durante la build (non a runtime). Se modifichi il file nella cartella di build, devi ricostruire l'immagine.

### EXPOSE

`EXPOSE <porta>` imposta la config dell'immagine e indica quale porta dovrà esporre: dice a Docker che il container ascolta su quella porta.

### CMD

`CMD <comando>` indica il comando da eseguire quando il container parte. Può essere sovrascritto con `docker run <image> <comando>`.

### ENTRYPOINT

`ENTRYPOINT <comando>` indica il comando da eseguire quando il container parte. Non può essere sovrascritto con `docker run <image> <comando>`.

#### Differenza tra CMD e ENTRYPOINT

- `CMD` fornisce un comando o argomenti predefiniti per il container. Può essere sovrascritto al momento dell'esecuzione del container.
- `ENTRYPOINT` imposta un comando fisso che viene eseguito quando il container parte. Con `docker run <image> <comando>` il comando viene aggiunto in coda a `ENTRYPOINT`, diventandone un argomento.

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

`docker-compose.yml` è un file di configurazione che permette di definire e gestire più container come un'unica applicazione.

Il Dockerfile descrive come costruire un'immagine, mentre `docker-compose.yml` descrive come più container interagiscono tra loro: quali immagini usare, come collegarli in rete, quali volumi montare e quali variabili d'ambiente impostare.
L'indentazione in questo file è importante. All'interno abbiamo 4 sezioni principali.

### Services

La sezione `services` definisce i container che compongono l'applicazione. Ogni servizio rappresenta un container o un insieme di container che eseguono la stessa immagine. Per ogni servizio puoi specificare:

- `image`: l'immagine Docker da usare per il servizio. La recupera già pronta da un registry (es. Docker Hub, anche se noi useremo immagini locali).
- `build`: dice a Compose di compilare un'immagine al volo a partire da un Dockerfile presente in una directory locale (context).
- `ports`: port mapping, con sintassi `HOST:CONTAINER`. Rende le porte del container accessibili dall'esterno. Ad esempio `8080:80` significa che la porta 80 del container sarà accessibile sulla porta 8080 dell'host.
- `expose`: rende le porte accessibili solo agli altri container presenti nella stessa rete Compose, senza esporle al mondo esterno o all'host.
- `volumes`: monta volumi o directory locali nel container.
- `environment`: imposta variabili d'ambiente per il container.
- `env_file`: permette di caricare variabili d'ambiente da un file esterno.
- `depends_on`: specifica le dipendenze tra i servizi, assicurando che un servizio venga avviato solo dopo che i servizi da cui dipende sono pronti. Ad esempio `depends_on: [mariadb]` significa che il servizio corrente aspetta che il servizio `mariadb` sia avviato prima di partire.
- `restart`: definisce la politica di riavvio del container in caso di arresto o crash. Ad esempio:
  - `restart: always`: il container viene riavviato automaticamente se si ferma;
  - `restart: unless-stopped`: il container si riavvia automaticamente, a meno che non venga fermato manualmente;
  - `restart: on-failure`: il container si riavvia solo se termina con un codice di errore (diverso da 0);
  - `restart: no`: non riavvia mai il container automaticamente.

### Networks

Definisce le reti virtuali che collegano i container tra loro. In maniera predefinita, Compose crea una rete privata in cui tutti i container possono comunicare tra loro usando i nomi dei servizi come hostname, tramite il DNS interno di Docker.

Se non specifico nulla, Docker crea in automatico una rete di tipo bridge:

- tutti i servizi dichiarati nel file vengono inseriti in questa rete comune;
- ciascun container può raggiungere gli altri semplicemente usando il nome del servizio come hostname.

Tipi di rete (driver):

- `bridge`: driver predefinito per singolo host, crea uno switch virtuale isolato all'interno della macchina. I container comunicano tra loro e possono uscire su internet via NAT, ma sono invisibili dall'esterno a meno di port mapping.
- `host`: rimuove l'isolamento di rete tra container e host. Il container condivide lo stack di rete dell'host.
- **Custom bridge network**: rete bridge personalizzata, creata e gestita dal daemon Docker sull'host. A differenza della bridge predefinita offre più controllo, collegamento e scollegamento a runtime senza riavvio e DNS automatico.

**Flusso di comunicazione tra container**

Quando un container si avvia all'interno di una rete, Docker configura il suo file `/etc/resolv.conf` con l'indirizzo IP del DNS interno della rete.

Se un'applicazione tenta di connettersi a un altro container usando il nome del servizio, l'OS del container invia la richiesta per `nome_servizio` al DNS interno.
Il server DNS di Docker consulta la tabella interna della rete per trovare l'IP corretto e restituisce la risposta al container richiedente.

### Volumes

Permette di dichiarare e gestire volumi dedicati, per mantenere intatti i dati anche quando i container vengono distrutti o ricreati. Questo perché i container sono effimeri: quando un container viene fermato o rimosso, tutti i dati scritti sul suo layer di scrittura interno (il writable layer) vengono persi. I volumi invece sono persistenti e sopravvivono alla vita del container.

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

La sintassi è `NOME_VOLUME:PERCORSO_INTERNO_AL_CONTAINER`. Se il volume non esiste al primo avvio, Docker lo crea automaticamente.

### Secrets

I secrets sono un meccanismo per gestire in modo sicuro informazioni sensibili come password, chiavi API o certificati. Invece di includere queste informazioni direttamente in `docker-compose.yml` o nel codice dell'applicazione, i secrets permettono di mantenerle separate e accessibili solo ai container che ne hanno bisogno.

Rendono i dati accessibili come file temporanei all'interno del container.

**A basso livello**

Quando assegno un secret a un container, Docker lo monta all'interno del container come file di testo.

Per impostazione predefinita, i file vengono montati in `/run/secrets/<nome_secret>`. Il contenuto del file è leggibile solo dal processo principale del container, e non è accessibile da altri container o dall'host.

All'interno del container, il percorso `/run/secrets/<nome_secret>` è montato come un filesystem temporaneo (tmpfs).

**Architettura logica**

Si divide in due passaggi: dichiarazione globale alla radice del file, poi assegnazione selettiva al singolo servizio.

Dichiarazione globale:

```yaml
secrets:
  db_password:
    file: ./secrets/db_password.txt
```

Con `file`, legge il contenuto da un file presente sull'host. Questo file non va incluso nella repo (quindi va aggiunto a `.gitignore`).

Se usiamo invece `environment`, lo prende direttamente dal file `docker-compose.yml`.

Assegnazione al servizio:

```yaml
services:
  mariadb:
    image: mariadb:11
    secrets:
      - db_password
```

Il file verrà montato in `/run/secrets/db_password` all'interno del container MariaDB. Il processo principale del container può leggere il contenuto di questo file per ottenere la password del database, senza esporla in `docker-compose.yml` o nel codice dell'applicazione.

## Comandi terminale

- `docker run <nome immagine>` crea un container dall'immagine.
  - `-v <volume>:<destinazione>` monta il volume chiamato `<volume>` in `<destinazione>`;
  - `-v <path progetto>:<path dentro container>` monta la cartella locale del progetto nella cartella dentro al container.
- `docker start <id container>` riattiva un container stoppato ma già creato.
- `docker ps` lista i container attivi.
- `docker ps -a` lista tutti i container (attivi + inattivi).
- `docker images` lista le immagini salvate localmente.
- `docker rm <container id>` rimuove un container.
- `docker history <nome immagine>` mostra i layer dell'immagine.
- `docker build -t <nome immagine> .` costruisce l'immagine.
- `docker volume create <nome volume>` crea un volume Docker, ma non lo collega a nessun container. Per collegarlo: `<nome volume>:/mountpoint`.

Altri comandi Docker:

- `docker image ...`
- `docker container ...`
- `docker volume ...`
- `docker network ...`

Dentro al container, se esegui `exit`, il processo principale si chiude e il container si stoppa. Il container esiste ancora, ma è fermo.

