# Dev environment

Docker is not available on this machine. The dev store is a self-contained PrestaShop 9.1.5 / PHP 8.3 / MySQL 8 install in `~/ps-shipping-env`, cloned from productimport's test store (`~/pi-test-env`) and running next to it. It reuses that directory's static binaries (`bin/php`, `bin/php-fpm`, `bin/caddy`, `bin/composer.phar`, `mysql/`, `php84/php`) read-only; all state (database, store files, logs) lives in `~/ps-shipping-env`. Override paths with `PSS_ENV` / `PSS_TOOLS`.

| | dev store | productimport store |
|---|---|---|
| Storefront | http://localhost:8081/ | http://localhost:8080/ |
| Back office | http://localhost:8081/admin-dev/ | http://localhost:8080/admin-dev/ |
| MySQL | 127.0.0.1:3308 | 127.0.0.1:3307 |

Back-office login: same as the productimport store (cloned database).

## Commands (`local-dev/env.sh`)

```sh
local-dev/env.sh clone      # one-time: copy ~/pi-test-env store (files + DB) into ~/ps-shipping-env (source store must be running)
local-dev/env.sh start|stop|status
local-dev/env.sh sync       # copy the checkout to modules/shippingrules with a --no-dev vendor built on PHP 8.3
local-dev/env.sh test       # PHPUnit + php-cs-fixer on PHP 8.4 in ~/ps-shipping-env/unit, then php -l on PHP 8.3
local-dev/env.sh console prestashop:module install|upgrade|uninstall shippingrules
local-dev/env.sh mysql -e "SELECT ..."
local-dev/env.sh php -r '...'
```

Edit in the repo, then `sync` (the store holds a copy, not a mount). After `sync`, clear the cache if templates or services changed: `local-dev/env.sh console cache:clear`.

Production runs PHP 8.3; PHPUnit 13 needs 8.4, hence the split. `composer.lock` is committed; `sync` installs production packages only.

Remove the store completely: `local-dev/env.sh stop && rm -rf ~/ps-shipping-env` (ask first; it erases test data). Re-create with `clone`.

## Test data

The cloned store has 6 products (productimport's examples) and the demo carriers (Click and collect, My carrier, My cheap carrier, My light carrier); default country Slovenia. Shipping scenarios (boards, sails, wetsuits with real weights and dimensions) still need fixture products; create them in the dev store, never on live.
