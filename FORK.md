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
- **No onboarding song.** Upstream's sings "Welcome to Dray", so Wain deleted the mp3 and made `startOnboardingMusic` do nothing (`welcomeSounds.ts`). A sync that changes the song conflicts there; keep Wain's side.
- **Apple team `FBH9JL8MB9`** (Ismat's) replaces upstream's by a `rebrand.mjs` rule.
- **`IslandView.composerCard` is split in four** (`cardContent`, `cardFill`, `cardFace`, `composerCard`). GitHub's Xcode 26 gave up type-checking it whole, which stopped the release; upstream builds on a newer Xcode and never sees it. On a sync conflict there, keep the split and carry upstream's change into it.
- **`wain upload` doesn't work yet**: it posts to upstream's upload worker. Attach screenshots to the PR through GitHub instead.
- **The `Claude Code Review` Action runs only once its secret is set on `ismatbabirli/wain`.** Until then, review in the session (`/code-review`) before asking for a merge.
- **The `caveman-commit` skill isn't installed.** Write commit messages by hand: a short plain subject, then why.

## Releases

- **Versions follow upstream's**: Wain's `vX.Y.Z` and `cli-vX.Y.Z` are upstream's numbers on Wain's code, so a version bump never conflicts on a sync. Tag Wain's own commit, never upstream's tag of the same name: the `upstream` remote is set to `--no-tags` so its tags stay out of this clone.
- **`CLI_PUBLISH_GATE=off`** (a repo variable) lets a CLI release publish without waiting for the app release that speaks its protocol. It was set for the first CLI release, before any app release existed. Delete it (`gh variable delete CLI_PUBLISH_GATE`) once the app has shipped, so the gate guards later releases again.
- **Downloads** go to the R2 bucket `wain-downloads`, served at `downloads.wainhq.com`. Infra's `scripts/r2-wain.sh` made it and the upload key behind the `R2_*` secrets. **Update manifests** live on the `updates` branch, served by Pages at `ismatbabirli.github.io/wain`. Only the release writes them.
- **Windows ships unsigned** (`RELEASE_WINDOWS=true`, no `WINDOWS_SIGN_COMMAND`) until there is a certificate, so SmartScreen warns on first run.
- **Mac jobs run on GitHub's Intel Macs** (`MAC_RUNNER=macos-15-intel`): its arm64 pool cancelled four CLI builds in a row in Nov 2026, and Ismat's own Mac is not a runner. `pick-mac.yml` passes any label through, and `release.yml` carries the host's Tauri CLI binary rather than assuming arm64. Delete the variable to go back to `macos-latest`. `warm-cache.yml` warms on the same picked Mac, and the desktop cache key carries the host arch, since an arm64 cache restored on Intel rebuilt every crate. The Windows job's limit is 60 minutes, not upstream's 35.
- **Signing** uses a Developer ID certificate made for CI alone (`824HZ7NR89`, expires 25 Dec 2027). It, its password and the "Wain notarize" app-specific password are kept encrypted in infra's `services/wain/.env`.

## The site

- wainhq.com runs on Ismat's Coolify, node 2: project `wainhq.com`, `wain-web` and `wain-postgres`. The runbook is `~/projects/infra/services/wain/README.md`, the scripts `deploy-wain.sh` and `dns-wain.sh`. That repo's `AGENTS.md` rules apply there: ask before anything that changes production.
