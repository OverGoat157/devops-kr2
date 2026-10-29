#!/usr/bin/env bash
# Запускать внутри учебной Ubuntu VM от пользователя devops с правом sudo.
set -uo pipefail
export LC_ALL=C

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf ' [OK]   %s\n' "$desc"
        ((PASS+=1))
    else
        printf " [FAIL] %s (ожидалось: '%s', получено: '%s')\n" "$desc" "$expected" "$actual"
        ((FAIL+=1))
    fi
}

if ! sudo -v; then
    printf 'Не удалось получить права sudo.\n' >&2
    exit 1
fi
if ! SSH_CONFIG=$(sudo /usr/sbin/sshd -T); then
    printf 'Не удалось прочитать действующую конфигурацию sshd.\n' >&2
    exit 1
fi

printf 'Аудит конфигурации: %s, %s\n' "$(hostname -f)" "$(date '+%Y-%m-%d %H:%M')"

printf '[1] Служба SSH\n'
check 'Вход от имени root запрещён' 'no' "$(awk '$1=="permitrootlogin" {print $2}' <<< "$SSH_CONFIG")"
check 'Парольная аутентификация отключена' 'no' "$(awk '$1=="passwordauthentication" {print $2}' <<< "$SSH_CONFIG")"
# Проверка 1: каждый настроенный порт SSH должен отличаться от 22.
PORT_CHECK=$(awk '$1=="port" {found=1; if ($2==22) bad=1} END {print (found && !bad) ? "yes" : "no"}' <<< "$SSH_CONFIG")
check 'Все порты SSH отличаются от 22' 'yes' "$PORT_CHECK"
# Проверка 2: проверка MaxAuthTries.
check 'MaxAuthTries равен 3' '3' "$(awk '$1=="maxauthtries" {print $2}' <<< "$SSH_CONFIG")"

printf '[2] Межсетевой экран\n'
if ! UFW_STATUS=$(sudo env LC_ALL=C ufw status verbose); then
    printf 'Не удалось получить состояние UFW.\n' >&2
    exit 1
fi
check 'Межсетевой экран активен' 'active' "$(awk '/^Status:/ {print $2}' <<< "$UFW_STATUS")"
# Проверка 3: политика по умолчанию для входящего трафика.
check 'Политика входящего трафика — deny' 'deny' "$(sed -nE 's/^Default: ([^ ]+) \(incoming\).*/\1/p' <<< "$UFW_STATUS")"

printf '[3] Учётные записи\n'
awk -F: '$3>=1000 && $3<65534 {printf "        %s (uid=%s)\n", $1, $3}' /etc/passwd

printf '[4] Веб-сервер\n'
check 'Nginx активен' 'active' "$(systemctl is-active nginx 2>/dev/null || true)"
if sudo nginx -t >/dev/null 2>&1; then NGINX_VALID=yes; else NGINX_VALID=no; fi
check 'Конфигурация Nginx корректна' 'yes' "$NGINX_VALID"
CERT_MIN_SECONDS=${CERT_MIN_SECONDS:-2592000}
if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "$CERT_MIN_SECONDS" >/dev/null 2>&1; then CERT_VALID=yes; else CERT_VALID=no; fi
check 'Сертификат действует ещё минимум 30 дней' 'yes' "$CERT_VALID"
if WRITABLE=$(sudo find /var/www/devops-site -perm -o+w -print 2>/dev/null) && [[ -z "$WRITABLE" ]] && [[ "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)" == 600 ]]; then WEB_PERMISSIONS=yes; else WEB_PERMISSIONS=no; fi
check 'Нет записи для всех; права TLS-ключа 600' 'yes' "$WEB_PERMISSIONS"

printf '[5] Контейнеризация\n'
check 'Docker активен' 'active' "$(systemctl is-active docker 2>/dev/null || true)"
DB_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || true)
check 'PostgreSQL healthy' 'healthy' "$DB_HEALTH"
PORT_ISOLATION=$(ss -H -tln | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:(5000|5432)$/ {bad=1} END {print bad ? "no" : "yes"}')
check '5000/5432 недоступны на внешних адресах' 'yes' "$PORT_ISOLATION"
check 'Права серверного .env равны 600' '600' "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null || true)"

printf '[6] Контрольная работа № 2\n'
KR2_DIR="$HOME/kr2"
REDIS_ID=$(docker compose --project-directory "$KR2_DIR" ps -q redis 2>/dev/null || true)
REDIS_HEALTH='missing'
if [[ -n "$REDIS_ID" ]]; then
    REDIS_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$REDIS_ID" 2>/dev/null || true)
fi
check 'Redis КР2 healthy (по сервису)' 'healthy' "$REDIS_HEALTH"
KR2_PORT=$(docker compose --project-directory "$KR2_DIR" port app 8003 2>/dev/null || true)
check 'Порт КР2 опубликован только на 127.0.0.1' '127.0.0.1:8003' "$KR2_PORT"
check 'Права .env КР2 равны 600' '600' "$(stat -c '%a' "$KR2_DIR/.env" 2>/dev/null || true)"
if openssl x509 -in /etc/ssl/certs/kr2.crt -noout -checkend 2592000 >/dev/null 2>&1; then KR2_CERT=yes; else KR2_CERT=no; fi
check 'Сертификат КР2 годен ещё 30 дней' 'yes' "$KR2_CERT"
if [[ -L /etc/nginx/sites-enabled/kr2 ]] && [[ "$(readlink -f /etc/nginx/sites-enabled/kr2)" == /etc/nginx/sites-available/kr2 ]]; then KR2_LINK=yes; else KR2_LINK=no; fi
check 'Ресурс Nginx kr2 активирован ссылкой' 'yes' "$KR2_LINK"

printf 'Пройдено: %s, не пройдено: %s\n' "$PASS" "$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
    exit 0
fi
exit 1
