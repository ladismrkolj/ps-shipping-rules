#!/bin/sh
# Self-contained PrestaShop 9.1 test store for shippingrules, separate from productimport's store.
# Reuses the static PHP / MySQL / Caddy binaries of ~/pi-test-env read-only; all state lives in
# $PSS_ENV (default ~/ps-shipping-env). Stop it and delete that directory to remove the store.
# No root, nothing system-wide.
#   local-dev/env.sh clone|start|stop|status|sync|test|php ...|mysql ...|console ...
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
E=${PSS_ENV:-$HOME/ps-shipping-env}
T=${PSS_TOOLS:-$HOME/pi-test-env}
PS=$E/www/prestashop
MODULE=shippingrules
DB_PASS=prestashop
# Ports differ from pi-test-env (8080/3307/9083/2099) so both stores run side by side.
export PSS_ENV="$E" PSS_PORT=8081 PSS_DB_PORT=3308 PSS_FPM_PORT=9084 PSS_ADMIN_PORT=2100
export LD_LIBRARY_PATH=$T/lib
export PATH=$T/bin:$T/mysql/bin:$PATH
# Keep tool state (caddy autosave, composer cache) inside the env directory.
export XDG_DATA_HOME=$E/run/xdg-data XDG_CONFIG_HOME=$E/run/xdg-config COMPOSER_HOME=$E/run/composer

running() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
php83() { php -c "$REPO/local-dev/php.ini" "$@"; }
db() { mysql --socket="$E/run/mysql.sock" -uroot -p"$DB_PASS" "$@" 2>/dev/null; }

start() {
  mkdir -p "$E/run" "$E/log" "$E/tmp"
  if ! running "$E/run/mysqld.pid"; then
    mysqld --no-defaults --basedir="$T/mysql" --datadir="$E/data" --socket="$E/run/mysql.sock" --port="$PSS_DB_PORT" \
      --bind-address=127.0.0.1 --mysqlx=OFF --pid-file="$E/run/mysqld.pid" --log-error="$E/log/mysql.err" --tmpdir="$E/tmp" --daemonize >/dev/null
  fi
  running "$E/run/php-fpm.pid" || php-fpm -y "$REPO/local-dev/php-fpm.conf" -c "$REPO/local-dev/php.ini"
  running "$E/run/caddy.pid" || caddy start --config "$REPO/local-dev/Caddyfile" --adapter caddyfile --pidfile "$E/run/caddy.pid" >"$E/log/caddy-start.log" 2>&1
  echo "store: http://localhost:$PSS_PORT/  back office: http://localhost:$PSS_PORT/admin-dev/"
}

case "${1:-status}" in
  clone)
    # One-time: copy productimport's test store (files + database) into a fresh, independent store.
    [ ! -e "$E/data" ] || { echo "$E/data exists: the store is already cloned" >&2; exit 1; }
    [ -f "$T/run/mysqld.pid" ] && kill -0 "$(cat "$T/run/mysqld.pid")" 2>/dev/null || { echo "start the source store first: $T/env.sh start" >&2; exit 1; }
    mkdir -p "$E/run" "$E/log" "$E/tmp" "$E/www"
    rsync -a --exclude var/cache --exclude var/logs "$T/www/prestashop/" "$PS/"
    mkdir -p "$PS/var/cache" "$PS/var/logs"
    sed -i "s/'database_port' => '[0-9]*'/'database_port' => '$PSS_DB_PORT'/" "$PS/app/config/parameters.php"
    mysqld --no-defaults --initialize-insecure --basedir="$T/mysql" --datadir="$E/data" --user="$(id -un)" >"$E/log/mysql-init.log" 2>&1
    start >/dev/null
    i=0; until mysqladmin --socket="$E/run/mysql.sock" -uroot ping >/dev/null 2>&1; do i=$((i + 1)); [ $i -lt 60 ] || exit 1; sleep 1; done
    mysql --socket="$E/run/mysql.sock" -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_PASS'; CREATE USER 'root'@'127.0.0.1' IDENTIFIED BY '$DB_PASS'; GRANT ALL ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION; CREATE DATABASE prestashop;"
    mysqldump --socket="$T/run/mysql.sock" -uroot -p"$DB_PASS" --single-transaction --routines prestashop 2>/dev/null | db prestashop
    db prestashop -e "UPDATE ps_shop_url SET domain='localhost:$PSS_PORT', domain_ssl='localhost:$PSS_PORT'; UPDATE ps_configuration SET value='localhost:$PSS_PORT' WHERE name IN ('PS_SHOP_DOMAIN','PS_SHOP_DOMAIN_SSL');"
    echo "cloned. Back office login is the same as in $T (see productimport's local-dev/.env)."
    start
    ;;
  start) start ;;
  stop)
    running "$E/run/caddy.pid" && kill "$(cat "$E/run/caddy.pid")" || true
    running "$E/run/php-fpm.pid" && kill "$(cat "$E/run/php-fpm.pid")" || true
    running "$E/run/mysqld.pid" && mysqladmin --socket="$E/run/mysql.sock" -uroot -p"$DB_PASS" shutdown 2>/dev/null || true
    ;;
  status)
    for p in mysqld php-fpm caddy; do running "$E/run/$p.pid" && echo "$p running" || echo "$p stopped"; done
    ;;
  sync)
    # Copy the checkout into the store (like a bind mount) with a production-only vendor/, built on the store's PHP 8.3.
    rsync -a --delete --exclude .git --exclude .omp --exclude local-dev --exclude tests --exclude vendor --exclude docs \
      --exclude .phpunit.cache --exclude .php-cs-fixer.cache "$REPO/" "$PS/modules/$MODULE/"
    (cd "$PS/modules/$MODULE" && php83 "$T/bin/composer.phar" install --no-dev --optimize-autoloader --no-interaction -q)
    ;;
  test)
    # Unit tests + formatting on PHP 8.4 in a scratch copy (dev vendor never reaches the store), then php -l on PHP 8.3.
    U=$E/unit
    mkdir -p "$U"
    rsync -a --delete --exclude .git --exclude .omp --exclude vendor --exclude .phpunit.cache "$REPO/" "$U/"
    (cd "$U" && "$T/php84/php" "$T/bin/composer.phar" install --no-interaction -q \
      && { [ ! -d tests ] || "$T/php84/php" vendor/bin/phpunit; } \
      && "$T/php84/php" vendor/bin/php-cs-fixer check --show-progress=none)
    find "$REPO" -name '*.php' -not -path '*/vendor/*' -not -path '*/.git/*' -print0 | xargs -0 -n1 php -c "$REPO/local-dev/php.ini" -l >/dev/null
    echo "php -l (8.3): ok"
    ;;
  php) shift; exec php -c "$REPO/local-dev/php.ini" "$@" ;;
  mysql) shift; exec mysql --socket="$E/run/mysql.sock" -uroot -p"$DB_PASS" prestashop "$@" ;;
  console) shift; cd "$PS" && exec php -c "$REPO/local-dev/php.ini" bin/console "$@" ;;
  *) echo "Usage: $0 clone|start|stop|status|sync|test|php|mysql|console"; exit 2 ;;
esac
