# Воспроизводимая конфигурация КР №2

Номер 11 в группе → вариант 3. Фамилия: Epifanov. Развёртывание 28–29.10.2026.
Исходная VM сохранена снимком `06-before-kr2`; итоговая — `07-kr2`.

## Файлы и сети

Проект находится в `/home/devops/kr2`. Исходники доставляются rsync из собственного
репозитория с `--exclude=.env --exclude=.git --delete`; каждый новый вариант доставки
сначала проверяется через `--dry-run`. `app.py` отличается от шаблона только первой
строкой `# KR2: Epifanov`. requirements.txt не изменён.

`.env` создан на сервере через `openssl rand -hex 32`, владелец devops, права 600.
Секрет не копируется на хост и не попадает в build context. Он передаётся через env_file;
несекретные REDIS_HOST=redis и STUDENT=Epifanov находятся в Compose.

В сети `kr2_backend` Docker DNS разрешает имя redis. Порт 6379 не опубликован,
8003 опубликован только на 127.0.0.1 VM. Redis хранит AOF в именованном томе
`kr2_redis_data`, `/data`. Оба сервиса имеют restart: unless-stopped.
Процессы обоих сервисов имеют UID 999. У Redis проверяется PID 1 через `/proc/1/status`:
пользователь отдельного docker exec не определяет пользователя основного процесса.

## TLS и Nginx

На хосте в `/etc/hosts` добавлено `192.168.56.101 stats.devops.local`.
Существующие записи сохранены, резервная копия — `/etc/hosts.backup-before-kr2`.

В VM выполнено:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/kr2.key -out /etc/ssl/certs/kr2.crt \
  -subj /CN=stats.devops.local -addext subjectAltName=DNS:stats.devops.local
sudo chown root:root /etc/ssl/private/kr2.key /etc/ssl/certs/kr2.crt
sudo chmod 600 /etc/ssl/private/kr2.key
sudo chmod 644 /etc/ssl/certs/kr2.crt
```

Файл `nginx/kr2` устанавливается как `/etc/nginx/sites-available/kr2`, root:root, 644.
Ссылка `/etc/nginx/sites-enabled/kr2` указывает на него. После установки:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

HTTP перенаправляется 301 на HTTPS. HTTPS передаёт запрос в 127.0.0.1:8003 с Host,
X-Real-IP, X-Forwarded-For и X-Forwarded-Proto. Журналы —
`/var/log/nginx/kr2.access.log` и `/var/log/nginx/kr2.error.log`.
Исходный `/etc/nginx/sites-available/devops-site` сохранён побайтно, что проверено SHA256.

## Контроль

На сервере до работы сохранён `~/ufw-before-kr2.txt`. Проверка:

```bash
diff <(sudo ufw status numbered) ~/ufw-before-kr2.txt
sudo sha256sum -c ~/devops-site.before-kr2.sha256
~/scripts/audit.sh       # исходные 14 проверок
~/kr2/scripts/audit.sh   # расширенные 19 проверок
```

Дополнительные проверки используют ID Redis по имени сервиса Compose, loopback-публикацию
8003, режим .env, срок сертификата не менее 30 дней и ссылку активного ресурса Nginx.
Временное нарушение публикации выявляется; конфигурация восстанавливается trap.
Для сохранности данных использовать down без -v. При обновлении секрета требуется
согласованное пересоздание обоих контейнеров; секреты на экран не выводить.

## Диагностика

С хоста проверить getent hosts, HTTP-перенаправление, TLS с --cacert, /health и /whoami.
На VM проверить nginx -t, /var/log/nginx/kr2.error.log, docker compose ps и logs.
Если /health доступен, но / даёт 500, проверить Redis/DNS/аутентификацию.
Если Nginx даёт 502, сначала проверить http://127.0.0.1:8003/health и состояние app.
На защите перезагрузка и откат снимка для диагностики не используются.
