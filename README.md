# SPT + Fika в Docker

Готовая сборка для хостинга сервера [SPT](https://github.com/SP-Tushonka/build) с опциональным
[Fika](https://github.com/project-fika/Fika-Server-CSharp) (кооп) в Docker на Linux-VPS.
Файлы SPT и Fika скачиваются контейнером автоматически по версиям из `.env`.

## Установка

Нужны Docker с плагином `docker compose` и обратный прокси с HTTPS (nginx, Caddy и т.п.):
контейнер слушает только `127.0.0.1:6969`.

```bash
git clone https://github.com/hammzat/spt-docker.git /opt/spt
cd /opt/spt
cp .env.example .env              # указать версии и публичный адрес сервера
sudo ln -s /opt/spt/spt.sh /usr/local/bin/spt
spt start
```

Прокси должен пересылать запросы (включая WebSocket) с `SPT_BACKEND_IP:SPT_BACKEND_PORT`
на `127.0.0.1:6969`. В лаунчере игроки указывают `https://<SPT_BACKEND_IP>:<SPT_BACKEND_PORT>`.

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
