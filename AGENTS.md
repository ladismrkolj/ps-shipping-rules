# shippingrules

PrestaShop 9.x module at repo root: shipping classes, rate tables and packing rules on top of native carriers, compatible with third-party carrier (API) modules. The shop sells bulky watersports gear (surfboards, sails, booms/masts) next to parcel-sized goods (wetsuits, accessories). Research and the proposed design: `docs/design.md`. Read it before any feature work and keep it current when the design changes.

## Principles

- Native first. Zones, countries, carriers, ranges, carrier size limits, product weight/dimensions, tax rules, free-shipping settings and cart rules belong to PrestaShop. Extend them through the documented carrier-module API and hooks; don't duplicate them, don't use overrides, don't edit core tables beyond what the carrier API expects.
- Nothing shop-specific in code. Classes, rates, packing counts, size limits and volumetric divisors are configuration. Sensible starting values ship as presets the merchant applies and then edits.
- Coexist with other shipping modules. Never change another module's carrier price unless the merchant configured an adjustment for that carrier. Identify carriers by `id_reference`, never `id_carrier`.
- Fail safe. A pricing error must not break checkout: log it, then apply the configured failure behaviour (native price or carrier unavailable).
- Pricing logic is pure PHP in `src/` (no PrestaShop classes) with unit tests; PrestaShop adapters stay thin. Memoise per request: core prices each carrier twice per package.
- Follow PrestaShop escaping, validation and database conventions. Validate all BO input.
- If you didn't run something, say so. Passing unit tests is not store verification.
- In active development: no backward-compatibility code (old formats, aliases, deprecated paths) unless the user asks. Remove superseded code.
- Once released to live, database changes must migrate existing installs: every schema or data change ships `upgrade/upgrade-X.Y.Z.php`; test it by upgrading a store that has the previous version, not by reinstalling.

## Dev environment

`docs/dev-env.md`. Short version: `local-dev/env.sh start`, edit, `local-dev/env.sh sync`, `local-dev/env.sh test`, then exercise the change in the dev store (http://localhost:8081/). Production runs PHP 8.3; unit tests run on 8.4. Don't install PHP, Composer or databases globally.

## Verification

- Pricing/packing/class-resolution logic: unit tests with realistic cases (1 board, 2 boards, board + wetsuit, mixed classes, missing dimensions, out-of-range weight, zone without rates).
- Anything that changes checkout: run a real cart in the dev store and check the carrier list and prices for the scenario, with and without tax, plus the order that results.
- Never test against the live shop. The `prestashop-store` skill's live profile is for catalogue reads; ask before any write there.

## Commits

- Commit after each verified unit of work. Push and release only when the user asks.
- One logical change per commit, imperative subject (`shippingrules: …`), body says what changed and why.
- Git has no identity configured here. Use the author of the latest commit through GIT_AUTHOR_* / GIT_COMMITTER_* environment variables; don't change git config.
- Never stage with `git add -A`, `git add .` or `git commit -a`. Stage explicit paths and check `git status` for untracked files first. A file you didn't create in this change is the user's: ask before committing it.
- Never commit vendor/, .omp/, secrets, store dumps, real rate sheets or customer data (the repo may be public).

## Challenge requests

- Treat the user's requests as ideas to examine, not specs. Check them against PrestaShop conventions and how shipping is usually done (shipping classes/profiles, table rates, carrier-calculated rates).
- If a request conflicts with common practice, adds risk, or has a simpler or more native alternative, say so and ask before implementing, with the trade-off and a recommendation.
- Ask when a request is ambiguous. Don't silently pick an interpretation or reduce scope.

## Hard limits

- No `rm -rf ~/ps-shipping-env` or re-`clone` without approval; it erases the dev store.
- Don't touch `~/pi-test-env` or the productimport repo except to read; the dev store only borrows their binaries.
- Ask before changing public behaviour or database schema after the first release.

## Reporting

End with: what changed; what you ran and the result; whether the dev store was exercised (and why not); what's untested.

## Delegation

Make code changes through a worker subagent, even small ones. The orchestrator plans, dispatches, reviews and reports.
