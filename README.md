# SPT + Fika in Docker

**English** · [Русский](#русский)

A ready-to-use setup for hosting an [SPT](https://github.com/SP-Tushonka/build) server with optional
[Fika](https://github.com/project-fika/Fika-Server-CSharp) co-op in Docker on a Linux VPS.
The container downloads SPT and Fika automatically, using the versions set in `.env`.

## Installation

You need Docker with the `docker compose` plugin and nginx (or another reverse proxy):
the container listens on `127.0.0.1:6969` only.

```bash
git clone https://github.com/hammzat/spt-docker.git /opt/spt
cd /opt/spt
cp .env.example .env              # set the versions and the server's public address
sudo ln -s /opt/spt/spt.sh /usr/local/bin/spt
spt start
```

Players enter `https://<SPT_BACKEND_IP>:<SPT_BACKEND_PORT>` in the launcher.

## nginx

nginx accepts players on `SPT_BACKEND_PORT` (443 by default) and proxies to SPT on
`127.0.0.1:6969`. SPT itself speaks HTTPS with a self-signed certificate and uses WebSockets
(notifications, Fika), so the upstream is `https://` and the `Upgrade` headers are required.

`/etc/nginx/sites-available/spt`:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 443 ssl;
    server_name spt.example.com;          # your domain or IP

    # Let's Encrypt for a domain: certbot --nginx -d spt.example.com
    # For an IP only, a self-signed certificate works (see below).
    ssl_certificate     /etc/nginx/ssl/spt.crt;
    ssl_certificate_key /etc/nginx/ssl/spt.key;

    client_max_body_size 100m;            # profile saves can be large

    location / {
        proxy_pass https://127.0.0.1:6969;
        proxy_ssl_verify off;             # SPT's certificate is self-signed

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_buffering off;
        proxy_read_timeout 3600s;         # keep WebSockets open during raids
        proxy_send_timeout 3600s;
    }
}
```

Self-signed certificate (if you have no domain):

```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout /etc/nginx/ssl/spt.key -out /etc/nginx/ssl/spt.crt -subj "/CN=spt"
```

Enable and open the port:

```bash
sudo ln -s /etc/nginx/sites-available/spt /etc/nginx/sites-enabled/spt
sudo nginx -t && sudo systemctl reload nginx
sudo ufw allow 443/tcp                # if you use ufw
```

In `.env`, `SPT_BACKEND_IP` is the domain or IP players connect to and `SPT_BACKEND_PORT`
is the nginx port (443). Fika's P2P raid ports are separate and are not proxied through nginx.

## Layout

```
/opt/spt
├── .env                 SPT / Fika versions, server address
├── docker-compose.yml
├── Dockerfile, entrypoint.sh
├── mods/                server mods (same layout as SPT_Runtime/user/mods)
├── profiles/            player profiles
├── config/              your own SPT_Data/configs/*.json overrides (optional)
├── client-assets/       vanilla game bundles required by ManimalInterchange (from the client's StreamingAssets/Windows)
├── server/              SPT files, installed automatically — do not edit by hand
└── backups/             output of `spt backup`
```

## Server commands

```
spt start                  build and start
spt stop | restart         stop / restart (after editing mods by hand)
spt status                 versions, container state, RAM/CPU
spt logs                   follow logs (Ctrl+C to exit)
spt update 4.1.6           switch SPT version
spt update 4.1.6 2.4.1     switch SPT and Fika
spt fika 2.4.1 | none      switch or disable Fika
spt mods                   list mods
spt backup                 back up profiles and configs
```

SPT versions: https://github.com/SP-Tushonka/build/releases
Fika versions: https://github.com/project-fika/Fika-Server-CSharp/releases
The server's SPT version must match the client, and the Fika version must match players' Fika plugin.

## Mods

**With the script (from Windows):** `sync-mods.ps1` mirrors your local server mods folder to the
server over SSH — uploads only new and changed files, deletes what no longer exists locally,
and restarts the server. Requires the OpenSSH client and Git for Windows (GNU tar).

```powershell
$p = @{ Source = 'C:\SPT\SPT_Runtime\user\mods'; Server = 'root@203.0.113.10' }
.\sync-mods.ps1 @p -DryRun      # preview changes
.\sync-mods.ps1 @p              # sync and restart
.\sync-mods.ps1 @p -NoRestart   # sync without restarting
```

The local folder is the source of truth: mod config edits made on the server will be overwritten.
`mods/fika-server` is left alone — the container installs it.

**By hand (WinSCP/SFTP):** copy the mod folder into `/opt/spt/mods/`, then run `spt restart`.

## SPT settings

Put a modified file, e.g. `ragfair.json`, into `/opt/spt/config/` — it is copied into
`SPT_Data/configs` on every start and survives SPT updates.
The address and port in `http.json` are always taken from `.env`.

---

# Русский

[English](#spt--fika-in-docker) · **Русский**

Готовая сборка для хостинга сервера [SPT](https://github.com/SP-Tushonka/build) с опциональным
[Fika](https://github.com/project-fika/Fika-Server-CSharp) (кооп) в Docker на Linux-VPS.
Файлы SPT и Fika скачиваются контейнером автоматически по версиям из `.env`.

## Установка

Нужны Docker с плагином `docker compose` и nginx (или другой обратный прокси):
контейнер слушает только `127.0.0.1:6969`.

```bash
git clone https://github.com/hammzat/spt-docker.git /opt/spt
cd /opt/spt
cp .env.example .env              # указать версии и публичный адрес сервера
sudo ln -s /opt/spt/spt.sh /usr/local/bin/spt
spt start
```

В лаунчере игроки указывают `https://<SPT_BACKEND_IP>:<SPT_BACKEND_PORT>`.

## nginx

nginx принимает игроков на `SPT_BACKEND_PORT` (по умолчанию 443) и проксирует на SPT
`127.0.0.1:6969`. SPT сам работает по HTTPS с самоподписанным сертификатом и использует
WebSocket (уведомления, Fika), поэтому upstream — `https://`, а заголовки `Upgrade` обязательны.

Конфиг — как в [английском разделе](#nginx): `/etc/nginx/sites-available/spt`.
Для домена сертификат проще получить через `certbot --nginx -d ваш.домен`,
для голого IP подойдёт самоподписанный (команда `openssl` там же).

```bash
sudo ln -s /etc/nginx/sites-available/spt /etc/nginx/sites-enabled/spt
sudo nginx -t && sudo systemctl reload nginx
sudo ufw allow 443/tcp                # если используется ufw
```

В `.env`: `SPT_BACKEND_IP` — домен или IP, к которому подключаются игроки,
`SPT_BACKEND_PORT` — порт nginx (443). P2P-порты рейдов Fika отдельные, через nginx не идут.

## Структура

```
/opt/spt
├── .env                 версии SPT / Fika, адрес сервера
├── docker-compose.yml
├── Dockerfile, entrypoint.sh
├── mods/                серверные моды (как SPT_Runtime/user/mods)
├── profiles/            профили игроков
├── config/              свои версии SPT_Data/configs/*.json (необязательно)
├── client-assets/       стандартные бандлы игры, нужны ManimalInterchange (из клиентского StreamingAssets/Windows)
├── server/              файлы SPT, ставятся автоматически — руками не трогать
└── backups/             результат `spt backup`
```

## Команды на сервере

```
spt start                  собрать и запустить
spt stop | restart         остановить / перезапустить (после ручной правки модов)
spt status                 версии, состояние, RAM/CPU
spt logs                   логи в реальном времени (Ctrl+C — выйти)
spt update 4.1.6           сменить версию SPT
spt update 4.1.6 2.4.1     сменить SPT и Fika
spt fika 2.4.1 | none      сменить или отключить Fika
spt mods                   список модов
spt backup                 бэкап профилей и конфигов
```

Версии SPT: https://github.com/SP-Tushonka/build/releases
Версии Fika: https://github.com/project-fika/Fika-Server-CSharp/releases
Версия SPT на сервере должна совпадать с клиентом, версия Fika — с плагином Fika у игроков.

## Моды

**Скриптом (с Windows):** `sync-mods.ps1` копирует на сервер по SSH всё из локальной папки
серверных модов — только новые и изменённые файлы, удаляет то, чего локально больше нет,
и перезапускает сервер. Нужны OpenSSH-клиент и Git for Windows (GNU tar).

```powershell
$p = @{ Source = 'C:\SPT\SPT_Runtime\user\mods'; Server = 'root@203.0.113.10' }
.\sync-mods.ps1 @p -DryRun      # посмотреть, что изменится
.\sync-mods.ps1 @p              # синхронизировать и перезапустить
.\sync-mods.ps1 @p -NoRestart   # без перезапуска
```

Локальная папка — главная: правки конфигов модов прямо на сервере скрипт перезапишет.
`mods/fika-server` скрипт не трогает, его ставит контейнер.

**Вручную (WinSCP/SFTP):** закинуть папку мода в `/opt/spt/mods/`, затем `spt restart`.

## Настройки SPT

Положите изменённый файл, например `ragfair.json`, в `/opt/spt/config/` — он будет
подставляться в `SPT_Data/configs` при каждом запуске и переживёт обновление SPT.
В `http.json` адрес и порт всегда выставляются из `.env`.
