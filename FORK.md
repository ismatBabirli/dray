# Wain fork rules

Wain is a renamed fork of Dray (`monorepo-labs/dray`). `CLAUDE.md` below is upstream's, renamed by `scripts/rebrand.mjs`. **Where this file and `CLAUDE.md` disagree, this file wins.** The plan behind all of it is [FORK-PLAN.md](FORK-PLAN.md).

## Who and where

- **The maintainer is Ismat** (`ismatBabirli` on GitHub). Where `CLAUDE.md` says "he", "his feedback" or "his go", read Ismat. Assign issues to `ismatBabirli`, not `yogesharc`.
- **One repo, `ismatbabirli/wain`.** Never open an issue, PR or comment on `monorepo-labs/dray`. A GitHub fork's PRs target the parent by default, so check `gh repo set-default --view` says `ismatbabirli/wain` before any `gh pr create`.
- **`main` is Wain**, the product branch, cloned in `~/projects/wain`. Upstream is the `upstream` remote (`monorepo-labs/dray`); its renamed copy is the `upstream-renamed` branch. Nothing tracks upstream's `main` locally.

## Syncing upstream

- `scripts/sync-upstream.sh` brings upstream in, already renamed, onto `upstream-renamed`, and merges it into `main` when that is checked out and clean. Run the tests after (`pnpm test:affected --full`).
- **It stops if upstream's `LICENSE` changed.** Stop too, and ask Ismat.
- **Never rename by hand what the script renames.** Change `scripts/rebrand.mjs` and re-sync instead, or the next sync conflicts on every line touched.
- A conflict on a file Wain changed on purpose (the copy below, the logo, `pluginBrand.ts`) is expected: keep Wain's version unless upstream's change is one Wain wants.

## Things that differ from upstream

- **Upstream's people and money are not Wain's.** No founder quotes, sponsors, testimonials, author numbers, upstream social accounts or upstream payment links. They were removed in Wain; a sync must not bring them back. `FORK-PLAN.md` §5 lists them.
- **Logo:** every asset is built by `python3 brand/build.py --install` from `brand/wain-brand-sheet.png`, then `apps/desktop/scripts/icons.sh`. Don't edit the generated files by hand.
- **No Greptile colour** (`pluginBrand.ts`), no upstream PostHog key (the docs read `DOCS_POSTHOG_KEY`), and the updater trusts only Wain's key; its private half is in `~/projects/infra/services/wain/.env`, encrypted.
- **`wain upload` doesn't work yet**: it posts to upstream's upload worker. Attach screenshots to the PR through GitHub instead.
- **The `Claude Code Review` Action runs only once its secret is set on `ismatbabirli/wain`.** Until then, review in the session (`/code-review`) before asking for a merge.
- **The `caveman-commit` skill isn't installed.** Write commit messages by hand: a short plain subject, then why.

## The site

- wainhq.com runs on Ismat's Coolify, node 2: project `wainhq.com`, `wain-web` and `wain-postgres`. The runbook is `~/projects/infra/services/wain/README.md`, the scripts `deploy-wain.sh` and `dns-wain.sh`. That repo's `AGENTS.md` rules apply there: ask before anything that changes production.
