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
- **Logo:** every asset is built by `python3 brand/build.py --install` from `brand/wain-brand-sheet.png`, then `apps/desktop/scripts/icons.sh`. Don't edit the generated files by hand. That includes the iPhone app's icon (all three appearances) and launch mark, and Android's launcher, splash and notification glyph. All are the desktop's dark tile with a white W, so Android lost upstream's soft shadow bitmaps and `scripts/launcher_icon.sh`. On a sync conflict there, keep Wain's files and rerun the script.
- **Pictures upstream made with Dray in them are retaken from Wain's own code** (26 Nov 2026). On a sync conflict over one, keep Wain's file and retake it if upstream's change is wanted:
  - The docs' server-setup screenshots: `node scripts/docs-screenshots.mjs` against the desktop's dev server (the script says how).
  - The homepage's phone stills (`hero-mobile*.webp`) are the live app window captured at 1x (dark) and 1.2x (light), and its bot scene's video (`bots/changelog-0.42.mp4`) is `/changelog` with the story's made-up 0.42 release added on top, scrolling. The bots-video demo's `homepage.jpg` and `changelog.mp4` are the same captures.
  - The What's New iPhone pictures and the site's `changelog/iphone.png` come from `demo/whats-new-illustrations.html?art=…`; their QR code (`src/demo/appStoreQr.ts`) is Wain's App Store link, made with the `qrcode` crate.
  - `brand/build.py` also draws the red profile picture, and the brand video's `src/marks.js` carries Wain's mark and lockup from `brand/`.
- **The App Store link** goes to Wain's listing, by a `rebrand.mjs` rule (upstream's `id6824145317` becomes `id6839484995`). It stays dead until App Review approves the app. Upstream also links it from `apps/web/src/lib/links.ts` and `public/llms.txt`, lines Wain removed. The rule makes the next sync conflict there once: keep them removed until the listing is live.
- **No Greptile colour** (`pluginBrand.ts`), no upstream PostHog key (the docs read `DOCS_POSTHOG_KEY`), and the updater trusts only Wain's key; its private half is in `~/projects/infra/services/wain/.env`, encrypted.
- **No onboarding song.** Upstream's sings "Welcome to Dray", so Wain deleted the mp3 and made `startOnboardingMusic` do nothing (`welcomeSounds.ts`). A sync that changes the song conflicts there; keep Wain's side.
- **Apple team `FBH9JL8MB9`** (Ismat's) replaces upstream's by a `rebrand.mjs` rule.
- **The iPhone app is `com.plorigo.wain.ios`**, Plorigo's namespace on that same team, by a `rebrand.mjs` rule ahead of the general one. The site's push relay pins pushes to it. The Mac app and its server stay `com.wainhq.wain`.
- **`IslandView.composerCard` is split in four** (`cardContent`, `cardFill`, `cardFace`, `composerCard`). GitHub's Xcode 26 gave up type-checking it whole, which stopped the release; upstream builds on a newer Xcode and never sees it. On a sync conflict there, keep the split and carry upstream's change into it.
- **`wain upload` posts to Wain's own Worker** at `upload.wainhq.com`, its files served from `img.wainhq.com` (set up 26 Nov 2026). Nothing deploys it on push: after a change to `apps/upload-worker`, or a sync that brings one, run infra's `scripts/upload-wain.sh --apply`. Its GitHub lookup token expires 26 Nov 2027, and uploads answer 503 until a new one goes in through `--token`.
- **The `Claude Code Review` Action and `claude.yml` are disabled** (`gh workflow disable`), and their secret, `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`), is not set. Until both change, review in the session (`/code-review`) before asking for a merge. Both are pinned, and `claude.yml` runs only for the owner's own `@claude`, so setting the secret and enabling them is all that is left.

## Repo safety

The repo is public, so these hold on purpose (set 26 Nov 2026):

- **Every outside pull request's workflows wait for Ismat's approval** (`fork-pr-contributor-approval: all_external_contributors`), not only a first-timer's.
- **Ruleset "main stays":** `main` cannot be deleted or force-pushed, by anyone. Ordinary pushes, the upstream sync's merges included, go through.
- **Ruleset "release tags: admin only":** only a repo admin creates, moves or deletes `v*` and `cli-v*`, so no token or app can start a release.
- **Every action is pinned to a full commit SHA, and GitHub refuses one that isn't** (`sha_pinning_required`). Pages' own build of the updater feed still runs under it. The sync warns when upstream brings in an unpinned one: pin it the way the others are, the version in a trailing comment.
- **Dependabot alerts and private vulnerability reporting are on**, so a security report arrives under Security → Advisories, not as a public issue. Dependabot opens no pull requests.
- **Interaction limits are off on purpose**: the site's Feedback link sends people to issues, and a limit would block new accounts there.
- **GitHub Apps that reach this repo:** Claude (the review workflows) and coolify-self-hosted-ismat (site deploys). Xcode Cloud's access is left from the dropped Xcode Cloud setup and can go. Showing or changing an app's access asks for Ismat's password.
- Nothing deploys on push: Coolify's auto-deploy is off and the repo has no webhooks or deploy keys. Ismat is the only collaborator, and the Actions token defaults to read and cannot approve pull requests.
- **The `caveman-commit` skill isn't installed.** Write commit messages by hand: a short plain subject, then why.

## Releases

- **Versions follow upstream's**: Wain's `vX.Y.Z` and `cli-vX.Y.Z` are upstream's numbers on Wain's code, so a version bump never conflicts on a sync. Tag Wain's own commit, never upstream's tag of the same name: the `upstream` remote is set to `--no-tags` so its tags stay out of this clone.
- **The first releases** are `cli-v0.18.2` and `v0.34.3` (25 Nov 2026). `CLI_PUBLISH_GATE=off` let the CLI publish before any app release existed; it was deleted once `v0.34.3` shipped, so the gate guards later releases again. Setting it back to `off` is the way out when the gate waits on an app release that will not come.
- **A release, start to end, took 34 minutes** on Intel Macs with a warm cache (Mac builds 24). `warm-cache.yml` must have finished on the commit's `Cargo.lock` first, or the Mac builds go cold and take ~36.
- **The dmg is signed but not notarized; the app inside is, ticket stapled.** Upstream ships the same way, and Gatekeeper judges the app when it opens. Notarizing the dmg too would quiet `spctl` on the dmg itself.
- **Downloads** go to the R2 bucket `wain-downloads`, served at `downloads.wainhq.com`. Infra's `scripts/r2-wain.sh` made it and the upload key behind the `R2_*` secrets. **Update manifests** live on the `updates` branch, served by Pages at `ismatbabirli.github.io/wain`. Only the release writes them.
- **Windows ships unsigned** (`RELEASE_WINDOWS=true`, no `WINDOWS_SIGN_COMMAND`) until there is a certificate, so SmartScreen warns on first run.
- **Mac jobs run on GitHub's Intel Macs** (`MAC_RUNNER=macos-15-intel`): its arm64 pool cancelled four CLI builds in a row in Nov 2026, and Ismat's own Mac is not a runner. `pick-mac.yml` passes any label through, and `release.yml` carries the host's Tauri CLI binary rather than assuming arm64. Delete the variable to go back to `macos-latest`. `warm-cache.yml` warms on the same picked Mac, and the desktop cache key carries the host arch, since an arm64 cache restored on Intel rebuilt every crate. The Windows job's limit is 60 minutes, not upstream's 35.
- **The iPhone app goes to TestFlight from `release-ios.yml`**, which runs only when Ismat starts it (`gh workflow run release-ios.yml`), on GitHub's `xcode-27` image: Xcode 26, all the release's Intel Macs carry, fails to compile the app. App Store Connect lists it as "Wain: AI Coding Agents" (Apple ID 6839484995), since "Wain" was taken; the home screen still reads Wain. It signs with a CI-only iOS Distribution certificate (`2V33924974`, expires 26 Nov 2027; Apple Distribution was at its limit) and two App Store profiles, "Wain iOS App Store" and "Wain Notify App Store", which the job reads by name from App Store Connect with the "Wain CI" API key (App Manager, `7UT75UX8N3`). The key and certificate are kept in infra's `services/wain/.env` too. When the certificate is renewed, regenerate both profiles under the same names. Xcode Cloud was the first plan; its setup needs clicks in Xcode, so it was dropped.
- **The Android app goes to Google Play's internal testing track from `release-android.yml`**, started by hand like the iPhone's. It is `com.plorigo.wain` (upstream's `com.dray.app`, by a `rebrand.mjs` rule) in Plorigo's Play Console. The bundle is signed with the upload key from `ANDROID_UPLOAD_KEYSTORE` (alias `upload`, valid to 2056, kept in infra too); Play App Signing holds the app key, and a lost upload key is reset in Play Console. The run number is the versionCode. The package was claimed when the app was created in Play Console, so even the first upload went through the API; `upload: false` only builds. The workflow writes `google-services.json` from the `GOOGLE_SERVICES_JSON` secret, from Wain's own Firebase project `wain-ad8d4` (on i.babirli@gmail.com, Analytics and Gemini off), and uploads with the `PLAY_SERVICE_ACCOUNT` key: `play-publisher@wain-ad8d4`, a service account with no Cloud roles, invited to PLORIGO's Play Console for this app alone (view, release to testing tracks, edit draft apps). Until the app has passed review, Play takes only draft releases, so the repo variable `PLAY_RELEASE_STATUS` is `draft` and each upload is rolled out by hand in Play Console; delete the variable once Play allows more. The site sends Android pushes with that project's Admin SDK key (`FCM_SERVICE_ACCOUNT`, from infra's `deploy-wain.sh`).
- **Signing** uses a Developer ID certificate made for CI alone (`824HZ7NR89`, expires 25 Dec 2027). It, its password and the "Wain notarize" app-specific password are kept encrypted in infra's `services/wain/.env`.

## The site

- wainhq.com runs on Ismat's Coolify, node 2: project `wainhq.com`, `wain-web` and `wain-postgres`. The runbook is `~/projects/infra/services/wain/README.md`, the scripts `deploy-wain.sh` and `dns-wain.sh`. That repo's `AGENTS.md` rules apply there: ask before anything that changes production.
