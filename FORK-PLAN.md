# Fork plan

Goal: ship Dray as **Wain** (an old English word for a farm wagon) for other people to use, add our own features, and keep pulling upstream (`monorepo-labs/dray`).

License: Apache-2.0, reviewed 2026-11-25. A renamed, modified and redistributed fork is allowed. It has to keep the license and notices and must not use the Dray name or marks (§6).

## 1. How a full rename and upstream syncing fit together

Renaming by hand puts a conflict on every line upstream later touches: about 8,100 lines and 1,469 paths. Instead, the rename is a script, and upstream is renamed *before* we merge it.

```
upstream/main ──A──────B──────C            (his repo, untouched)
                │      │      │   rebrand script
upstream-renamed A'─────B'─────C'          (one commit per sync)
                 \       \      \
wain              A'──x──y──B'merge──z──C'merge   (our product + features)
```

- **`upstream-renamed`**: each sync takes upstream's tree, runs `scripts/rebrand.mjs` over it, and commits the result. Parents: the previous sync and the upstream tip, with an `Upstream: <sha>` trailer, so history still says which upstream commit each sync came from.
- **`wain`**: our product, and what becomes the fork's `main` on GitHub once pushed. It merges `upstream-renamed`. Our features land here, written with the new name. The local `main` stays a mirror of upstream, as before.
- The merge base is the previous renamed sync, so a merge only sees upstream's new changes, already renamed. Conflicts happen only where we and upstream edited the same lines, as in any fork.
- **`scripts/sync-upstream.sh`** does the whole sync: fetch, rebrand a temp worktree, commit to `upstream-renamed`, merge into `wain` when that is checked out and clean. **It stops if upstream's `LICENSE` changed.** Code we already have stays Apache-2.0, but a relicense needs a human decision before we take more. Run the tests after it.

The scripts live on `wain` only. They must be deterministic: same input, same output. A later rule change is safe; it lands as one large sync commit. First sync: `89f46a0` from upstream `fbc913d`, 25 Nov 2026 (3,571 files, 858 edited, 1,502 renamed, in half a second).

## 2. The rebrand script

Applied in this order, so the specific rules run before the generic ones:

| From | To | Note |
|---|---|---|
| `monorepo-labs.github.io/dray` | `ismatbabirli.github.io/wain` | updater manifests |
| `monorepo-labs` | `ismatBabirli` | his org, alone too: `owner: "monorepo-labs", repo: "dray"` in the docs config |
| `com.yogesh.dray` (and `com/yogesh/dray` paths) | `com.wainhq.dray`, then the generic rule | bundle IDs, launchd label, Kotlin package. Exactly this string |
| `DRAY` / `Dray` / `dray` | `WAIN` / `Wain` / `wain` | substring, the only three casings in the repo |
| every tracked path and symlink target | the same rules | moved inside the temp worktree |

- **The generic rule is safe today.** Every word in the repo containing "dray" is a brand compound: `DrayError`, `drayhq`, `useDrayAccount`, `\ndray`. Every rule but the two `monorepo-labs` ones keeps the length, so offsets in fixtures survive.
- **The script warns and the sync stops** when "dray" survives in another casing, or sits inside a long base64-like run (likely data, not a name). Neither happens today.
- **The domain needs no rule.** The generic rule already turns `drayhq.com` into `wainhq.com`, and `downloads.drayhq.com` into `downloads.wainhq.com`.
- **Never rename `yogesharc`.** `@yogesharc/thinking-orbs` (npm) and `com.github.yogesharc:thinking-orbs` (JitPack) are his MIT library, a real dependency. No rule matches it, and the self-test pins that. Recorded `/Users/yogesh/…` paths and `yogesh.co` in fixtures are data and stay as they are.
- **Never touched:** `LICENSE`, plus the *contents* of binary files. `CLAUDE.md` and `THIRD-PARTY-LICENSES.md` are renamed like everything else (renaming them keeps upstream's edits merging cleanly); our own changes to them are ordinary commits on `wain`. `NOTICE`, `FORK-PLAN.md` and the scripts exist only on `wain`, so the script never sees them.
- **Lockfiles** (`pnpm-lock.yaml`, `Cargo.lock`) are renamed like everything else. `pnpm install --frozen-lockfile` passed on the first renamed tree.
- `node scripts/rebrand.mjs --self-test` checks the rules.
- **"wain" works glued into identifiers** (`WainError`, `useWainAccount`, `~/.wain`, `WAIN_HOME`) and appears nowhere in the repo today (checked 2026-11-25), so the rename collides with no existing word.
- **Done when:** on a renamed tree, `pnpm test:affected --full`, the headless `cargo check` and `pnpm tauri dev` all pass, and the dev app opens as `Wain-dev` with its data in `~/.wain-dev`.

## 3. Cut ties with upstream's services

A release build calls his services. Each one needs our own, or has to be turned off.

| Service | Upstream | Ours |
|---|---|---|
| App updater | `monorepo-labs.github.io/dray/{stable,beta}.json`, his minisign key (`tauri.conf.json:68`) | new key pair (`pnpm tauri signer generate`), manifests on our GitHub Pages, `TAURI_SIGNING_PRIVATE_KEY*` secrets |
| Downloads | `downloads.drayhq.com` (R2) | our R2 bucket (`R2_*` secrets), or GitHub Releases |
| Server updates | `api.github.com/repos/monorepo-labs/dray/releases` (`servers.rs:367`) | our repo's `cli-v*` releases (script handles the URL) |
| CLI install | `www.drayhq.com/install.sh`, `REPO="monorepo-labs/dray"` | our site (script handles it) |
| Accounts + sign-in gate | `www.drayhq.com` (`org_link.rs:24`). Release builds always gate (`signInGate.ts`) **infra ready, not deployed** (25 Nov 2026): Coolify node 2, project `wainhq.com`, `wain-postgres` + `wain-web` (auto-deploy off), DNS proxied to node 2. Google client "Wain web" (Cloud project `wainhq`, consent screen in Testing) and GitHub OAuth App "Wain". All secrets in `~/projects/infra/services/wain/.env`, encrypted; runbook `services/wain/README.md`. Email sign-in off. **Blocked on:** the rebrand and `apps/web/Dockerfile` |
| Dray Cloud | `www.drayhq.com/api/cloud`, his hosted machines | off/hidden until we run our own |
| Changelog feed | `drayhq.com/changelog.json` | our site |
| Analytics | `POSTHOG_KEY` secret. Docs has his key hardcoded in `apps/docs/blume.config.ts` | our PostHog project, or none. Remove his key |
| Docs | Vercel, served at `/docs` via `DOCS_ORIGIN` | a second Coolify app beside `wain-web` (not set up yet) |
| Mac signing | his Apple Developer ID (`APPLE_*` secrets) | our Developer ID (we have one): certificate, team ID and notarization login go into the `APPLE_*` secrets |
| Release Mac | self-hosted `dray-mac` runner | `macos-latest`. `pick-mac.yml` falls back on its own when `RUNNER_STATUS_TOKEN` is unset |
| Greptile green | used "with their permission", given to Dray | drop it |

Separate bundle IDs, launchd label, home dir and CLI name mean `Wain` and Dray can be installed side by side.

## 4. License chores

- Keep `LICENSE` unchanged.
- Add `NOTICE`: "Wain is based on Dray by Yogesh Dhakal (github.com/monorepo-labs/dray), licensed under Apache-2.0. Modified by Ismat Babirli." Add our own copyright line for our changes.
- §4b (modified files carry a notice): the `NOTICE` statement plus the git history. Per-file headers are optional.
- Keep `THIRD-PARTY-LICENSES.md` and add entries for any dependencies we add. Add `thinking-orbs` (MIT, © yogesharc) now: it's his own package, so upstream lists no notice for it, but for us it's third-party code.
- "Based on Dray" is fine in docs and on the site. Dray's name and logo as our brand is not.

## 5. Brand assets (not scriptable)

The script renames paths, not pixels. New artwork is needed for: the desktop icons (`apps/desktop/src-tauri/icons`), the iOS AppIcon, Android mipmaps, Dray Island, web favicons and OG images, and the docs logo. Also any SVG that draws the word "Dray".

**Words about real people are not scriptable either, and the rename makes them false.** Found on the first renamed tree (25 Nov 2026). Until these change, nothing deploys or ships:

- **Founder and contact:** onboarding says "Yogesh, Founder of Wain" (`apps/desktop/src/components/onboarding/Onboarding.tsx`). Settings, the site's help and support pages, and `apps/web/src/lib/links.ts` point at `x.com/yogesharc` and ask for support "so Yogesh can keep building".
- **Sponsors:** Guillermo Rauch / Vercel OSS Grants are credited as sponsors (`README.md`, `SettingsPage.tsx`, `home/Hero.tsx`, `home/Support.tsx`, `SponsorLink.tsx`). They sponsor Dray, not Wain.
- **Testimonials and proof:** real people's quotes and avatars about Dray (`apps/web/src/lib/testimonials.ts`, `public/avatars/`), and Yogesh's own numbers (`home/Proof.tsx`).
- **Accounts:** `x.com/wain_hq` (`app/page.tsx`, `links.ts`) is not ours.
- **Legal:** `apps/docs/content/reference/privacy.mdx` and `terms.mdx` name upstream's operator. Wain needs its own, written for its own data and services.
- Also check `apps/web/public/llms.txt`, `home/SiteNav.tsx`, `home/Closing.tsx`, `home/MiniHome.tsx` and the docs' settings page.

`git grep -i -E 'yogesh|rauchg|guillermo|sponsor|x\.com/|wain_hq|founder'` finds them (leave `@yogesharc/thinking-orbs` alone). These are ordinary commits on `wain`, so an upstream edit to the same lines conflicts and needs a look, which is the point.

## 6. Our workflow

`CLAUDE.md` describes upstream's process. Rewrite it on `main`:

- Issues and PRs go to `ismatBabirli/wain`. Drop `yogesharc`, `monorepo-labs`, and Greptile unless we set it up.
- **A GitHub fork's PRs target the parent repo by default.** Run `gh repo set-default ismatBabirli/wain`, or ask GitHub to detach the fork, so nothing lands on his repo by accident.

## 7. Order of work

1. **Claim the name (you).** ~~Register `wainhq.com`~~ (done 25 Nov 2026, on Cloudflare); `wain.dev` as a guard. Rename the GitHub repo to `ismatBabirli/wain` and run `gh repo set-default`.
2. **Rebrand and sync scripts.** Rename current upstream, all tests pass, the dev app runs under the new name. Create `upstream-renamed` and `main` from it. Add `apps/web/Dockerfile` (root build context, `ARG NEXT_PUBLIC_SITE_URL`, `pnpm db:migrate` before `next start`, port 3000).
3. **Service ties.** Updater key, URLs, analytics, Cloud off.
4. **Account site live at `wainhq.com`.** Infra, DNS and both OAuth clients are done. Left: the words-about-real-people pass (section 5), then the first `deploy-wain.sh` run, turn auto-deploy on, publish Google's consent screen. Release builds stop at sign-in, so this comes before any release.
5. **First release: desktop and CLI.** Secrets, Apple signing, a `v0.1.0-beta.1` on our repo. Install it, publish `beta.2`, and confirm it updates itself.
6. **Brand assets, site and docs.**
7. **Rewrite `CLAUDE.md`.**
8. Our own features, on `main`.

iOS and Android are renamed with everything else so they keep building, and ship in a later release.

**Still to set up:** Cloudflare R2 (downloads), PostHog (optional), the Apple certificate exported into the `APPLE_*` secrets. Hosting is your own Coolify (node 2), so no Vercel or Railway.

## Decisions (all settled 2026-11-25)

- [x] Name: **Wain** (picked from 93 screened). No command clash on macOS, Homebrew or Debian. `wain.dev` and `wainhq.com` were unregistered that day. The only US "WAIN" trademark covers electric connectors (reg. 6914978). A paid trademark search in target countries is still to do.
- [x] Domain: **`wainhq.com`**. Bundle-ID prefix `com.wainhq.wain`.
- [x] Sign-in: **host our own** account site (section 3).
- [x] iOS and Android: **later**.
- [x] Apple Developer account: **have one**.
