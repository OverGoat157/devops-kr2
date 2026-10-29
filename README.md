# Контрольная работа №2 — вариант 3

Епифанов Денис Андреевич, ЭФБО-17-24. Номер 11 в списке → вариант 3.

Исходный шаблон: https://gitverse.ru/dgimatdinov/kr2-template, commit `3ee6c4b`.
Логика app.py и зависимости requirements.txt сохранены; добавлен только комментарий студента.

## Развёртывание

- VM: `devops-vm`, Ubuntu Server, пользователь `devops`.
- Проект: `/home/devops/kr2`; сервисы Compose `app` и `redis`.
- Домен: `stats.devops.local`, Host-only IP `192.168.56.101`.
- Приложение: Gunicorn `0.0.0.0:8003` в контейнере, публикация VM `127.0.0.1:8003`.
- Хранилище: `redis:7-alpine`, сеть `kr2_backend`, AOF и том `kr2_redis_data` в `/data`.
- Новый виртуальный хост Nginx: `nginx/kr2` → `/etc/nginx/sites-available/kr2`.
- Сертификат: `/etc/ssl/certs/kr2.crt`, SAN `stats.devops.local`; ключ `/etc/ssl/private/kr2.key`, root:root, 600.

На хосте нужна запись `192.168.56.101 stats.devops.local` в hosts.
Файл `.env` генерируется исключительно на VM с новым случайным паролем и правами 600.
Значения пароля и закрытый TLS-ключ в репозитории отсутствуют.
Опубликованный пароль исходного шаблона в истории main не используется на сервере.

```bash
# Хост, из корня репозитория. Сначала прочитать dry-run.
rsync -avz --delete --exclude=.env --exclude=.git --dry-run ./ devops:kr2/
rsync -avz --delete --exclude=.env --exclude=.git ./ devops:kr2/

# VM, только при первом развёртывании.
cd ~/kr2
unset REDIS_PASSWORD
if [ ! -e .env ]; then
  (umask 077; printf 'REDIS_PASSWORD=%s\n' "$(openssl rand -hex 32)" > .env)
fi
chmod 600 .env
docker compose config --quiet
docker compose up -d --build
docker compose ps
```

Команда выпуска сертификата и полный порядок настройки приведены в `docs/server-setup.md`.

## Проверка

```bash
# VM
cd ~/kr2
docker compose ps
docker compose top
docker compose port app 8003
docker compose exec -T redis redis-cli ping  # ожидается NOAUTH
scripts/audit.sh                            # 19 OK, код 0

# Хост, открытый сертификат получен через проверенное SSH-соединение
scp devops:/etc/ssl/certs/kr2.crt ~/kr2.crt
curl --cacert ~/kr2.crt https://stats.devops.local/
curl --cacert ~/kr2.crt https://stats.devops.local/whoami
curl --cacert ~/devops.crt -I https://devops.local/
curl --cacert ~/devops.crt https://devops.local/app/
```

Без `--cacert` самоподписанный сертификат не считается доверенным.
В `/whoami` ожидаются https, stats.devops.local и Host-only адрес клиента.
Прямой запрос с хоста на `stats.devops.local:8003` должен завершаться ошибкой.

Сохранность тома проверена: до `docker compose down` счётчик 4, после `up -d` — 5.
`down -v` для этой работы не использовался. Проверены UID 999 процессов приложения и Redis,
пустой результат поиска `.env` в образе, кэш зависимостей при изменении app.py,
HTTP 301, HTTPS с проверкой сертификата и передача заголовков прокси.

Расширенный аудит в этом репозитории содержит прежние 14 проверок и 5 проверок КР2.
При временной публикации `8003:8003` он выдаёт 18 OK / 1 FAIL и код 1; после возврата
`127.0.0.1:8003:8003` — 19 OK / 0 FAIL и код 0. Исходный аудит практики 7 сохранён.
UFW и конфигурация `devops-site` не изменялись. Снимки: `06-before-kr2`, `07-kr2`.

Ветка `kr2/variant-3` предназначена для открытого Pull Request в main; слияние — после защиты.
