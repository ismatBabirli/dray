# Wain for Android

A native Kotlin + Jetpack Compose client of `wain-serve`, ported from the iOS
app's first App Store version (0.1.0, `apps/ios` before its 0.2.0 additions).
It runs no core and no agent: every session lives on a server, and the phone
reads and drives it over the same WebSocket the desktop and iOS use
([SERVE-PLAN.md](../desktop/SERVE-PLAN.md)). #1379.

## What this foundation does

- **Pairing**: a `wain://connect?url=…&token=…&name=…` link (the pairing QR,
  which the system camera opens too) fills Add server but never adds unasked;
  the in-app scanner reads the same QR (CameraX + ML Kit); or paste the
  address and token, where a whole connect line fills both. Tokens are sealed
  with an Android Keystore key, never stored plain.
- **Four tabs** (#28, Paper's "Android — tabs"; the rules both phones share
  are in its Notes board): Home, Bots, Tasks and Routines on a Material 3
  navigation bar, switched by hand on window width (`Tabs.kt`): at 600dp and
  wider a navigation rail with New task at its top, and a chat opens beside
  the tab's list instead of over it (`Route.inPane`). The bar hides in a chat
  and under a sheet. Home is what waits on the reader, what works and what is
  new (`model/Home.kt`, `store/StoreTabs.kt`); Bots is the roster, waiting
  first; Tasks is the list below; Routines is every bot's routines
  (`list_routines`, pause, delete), soonest first. Home's yellow badge counts
  what waits; Bots' red one counts bots with unread replies.
- **Machines**, where the gear was: the button leading every top bar, its dot
  the worst of the shown machines, opening a sheet that shows every machine or
  exactly one (`Store.machine`, kept per device), each with its health and
  Retry, then Usage, Pair a machine and Settings.
- **New task** is an extended FAB on Home and Tasks (the rail's button on a
  tablet), opening a sheet over `NewTask`: the prompt and its mic, Run by (Me
  or a bot, the aim-at-bot path), project, agent, machine, worktree, Save draft.
- **Usage** (`wire/Usage.kt`, `model/Usage.kt`): `live_state.usage` and
  `usage_changed`, one reading per agent per server. Home's chips show each
  agent's worst five-hour window, a sheet every window by machine, and the
  composer's model chip a ring with its own machine's figure.
- **Every saved server at once, one merged list**: the desktop sidebar's
  stage runs, a child hanging off its parent on an elbow, PR marks from
  `pr_marks`, a project strip, the settled view, a waiting card under its
  row, and each server's trouble as a card with Retry or Fix. Shared machines
  (`share_machines`) join as servers of their own. The list draws from the
  last read's cache before any socket is up.
- **A machine the phone also pairs directly shows once** (#1404, Store.swift's
  rule with the iOS review applied). Every welcome carries `identity`, a hash
  of the server's token a relay passes through; a shared machine's is learnt
  on its first connect and kept (`copyIds`), so later launches hold the copy
  back before it ever connects. It is held back only while the direct one is
  on and not failing: refused, or down past `LOST_AFTER_MS`, brings the copy
  back and hides the direct one's stale rows instead (`covered`). Removing a
  server lets back only copies held for it. A dropped copy never unregisters
  push — the server keeps one tag per handle, so its twin re-registers — and
  an alert tagged with either id opens through `shownAs`.
- **Transcript**, live: finished turns fold to prompt, summary and answer;
  runs of one tool group; a running turn keeps its newest five rows; `lite`
  reads with a call's body read whole on demand (`get_session_calls`);
  pictures inline and full screen (pager, pinch, double-tap, drag down);
  browser recordings play in place (Media3, token in `/file`'s query).
- **Composer** (`Composer.kt`), in every chat: the field with the mic at its
  end, which turns to Send once there are words; Stop beside it mid-turn, the
  field then queueing. Tap the mic for hands-free dictation, hold it to talk
  while held: the field grows into the strip (the words as they come, Cancel,
  the level, the time, Done) and the words land in the field to edit. Under it
  the session's model and stance open **This task** (model, effort, fast mode,
  stance, each locked mid-turn per `Picks.lockedMidTurn`).
- **Permission and question cards**, answered in place, in the transcript and
  under the row in the list.
- **Servers** in Settings: state, on/off, Fix, remove, add.
- **Open bot at launch** in Settings (#1517), Off unless a bot is picked: the
  app opens on that bot's chat at launch (the first bot where the picked one
  is gone), over the list so back lands there. Read off the cached list, the
  chat is the launch's first frame; only a launch with no cache waits for the
  server. An alert, a link or any move off the list first spends it. Nothing
  else opens a bot unasked (`OpenIntoBot`).

- **Dictation** (`voice/`, Dictation.swift): per draft, outliving the screen
  that started it. Two engines: Android's `SpeechRecognizer` on the phone
  (on-device where it has one, AppleSpeech.swift's place), listening live and
  restarting across pauses; or a server's model, a 16 kHz WAV through `/upload`
  and `transcribe_upload`, kept for Retry where the server never answered.
  Settings → Dictation picks one. The phone's engine shows its words live
  (`Dictations.heard`). **The voice orb** (VoiceOrb.metal's `prism` as AGSL)
  is drawn nowhere since the composer replaced the docks; debug builds keep
  it in `OrbDemoActivity`.
- **Push** (`push/`, Push.swift on FCM): the FCM token is sealed by the relay
  (`/api/push/register` with `platform: "android"`) into a handle each server
  gets with `push_register`, exactly as iOS hands its APNs handle over; the
  server needs no change. Alerts are FCM data messages drawn by the app: a
  channel per kind, Allow and Deny, a question's options (three at most, or
  none and the tap opens the app) and Reply, answered on the store's socket or
  one of its own, with no app coming forward. A tap opens the chat (`open`
  where a bot's task alerts). Settings → Notifications holds the switches.

- **Pull requests and Issues pages** (Pulls.swift, PullDetail.swift,
  Issues.swift): in the Tasks tab's top bar. Each draws its last read at
  once, from `page-pulls.json` and `page-issues.json` in the cache dir on a
  fresh launch, and reads behind it (`store/Pulls.kt`, `store/Issues.kt`).
  The PR list's search box narrows by title, number, author or branch on the
  phone; the issues one asks the tracker. A PR's page reads it through
  `prs_for_branch` and its description, labels and reviewers through
  `pr_detail` (#1511), and reuses the PR sheet's readiness, checks and
  comments. A comment opens whole in place, replies and threads with it.
  **Play and Share sit at the right of both detail pages' bars** (#1534):
  Play opens a sheet holding the start box (`StartSheet.kt`), a bot or the
  reader's own task, its place, agent, model, effort and fast mode. A PR's task
  goes through `start_pr_session` on the PR's branch; an issue's through
  `send_msg` with its tag, link and body and `issueIds`, or
  `send_issue_to_bot`, so nothing goes through New task. Share is the
  system share sheet with the title and link; neither page opens a browser.

Left for the tasks building on this: creating, editing or running a routine
from the phone (the wire has list, pause and delete), the rest of Settings,
the PR sheet, Share in the image viewer.

## Push setup

**Push is off until the Firebase project's files are in.** Without
`app/google-services.json` the app builds, `FirebaseApp` never starts, and
Settings → Notifications says push isn't set up. To light it up:

1. The Firebase project is `wain-hq`, its Android app `com.plorigo.wain` (the
   Play Store id; the Kotlin namespace stays `com.wainhq.wain`). The
   google-services plugin fails the build when the file names no client for
   that id, so a file downloaded for an older id must be replaced.
   Its `google-services.json` goes at `apps/android/app/google-services.json`
   and is **kept out of git** (gitignored). Download it from the Firebase
   console (Project settings → Your apps). A release build gets it the same
   way: by hand today, and from a CI secret written to that path before
   `assembleRelease` once an Android release workflow exists.
2. The project's service account key is `FCM_SERVICE_ACCOUNT` on the site
   (Vercel production), base64 of the key file. FCM's HTTP v1 API; the
   legacy "server key" is retired and not used.
3. `PUSH_HANDLE_SECRET` is the one iOS already uses.

**FCM on a sandbox emulator**: Play services' FCM socket sits idle up to two
minutes between heartbeats, and a boat sandbox's network drops it well before,
so a message sent then is lost. Measured, a message sent onto a fresh
connection lands in milliseconds; a test run there restarts Play services
every few seconds (`am force-stop com.google.android.gms`) to keep it fresh.
A phone on a real network needs none of this.

**Testing without FCM**: a debug build takes `--es pushRelay <url>` (seal at a
local relay) and `--es pushPayload '<data JSON>'` (an FCM message's `data`,
drawn in 3s as `PushService` would). Run the site with `FCM_ORIGIN` pointing
at a stand-in and `token_uri` in the key file at one too, and every message the
relay sends lands there to replay into the app.

## Release signing

**A Play bundle is `./gradlew :app:bundleRelease`, signed with the upload
key.** The key's four values come from `apps/android/keystore.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; a relative
`storeFile` resolves against `apps/android/`) or from the env vars
`WAIN_ANDROID_STORE_FILE`, `WAIN_ANDROID_STORE_PASSWORD`,
`WAIN_ANDROID_KEY_ALIAS` and `WAIN_ANDROID_KEY_PASSWORD`. With neither, the
release build still configures and comes out unsigned, so CI needs nothing.
The properties file, `*.jks` and `*.keystore` are gitignored. Play App Signing
holds the real app key; a lost upload key is reset from Play Console, not
fatal. Bump `versionCode` for every upload.

## Layout

```
app/src/main/java/com/wainhq/wain/
  wire/    JSON helpers and the wire types (Wire.swift)
  net/     Connection: one OkHttp WebSocket per server, reconnecting (Connection.swift)
  push/    FCM token, the relay's handle, alerts and their buttons (Push.swift)
  voice/   dictation: the phone's recognizer, a server's model (Dictation.swift)
  model/   pure logic: buildTurns, stageRuns, tool labels, markdown blocks, Picks
  store/   Store (Store.swift) and the Keystore-sealed tokens
  ui/      Compose screens; Theme.kt holds every colour, size and font
```

**Port by file, keep the names.** Each Kotlin file says which Swift file it
restates; a rule changed in one belongs in the other, and in the desktop file
both restate (`tools.ts`, `permission.ts`, `liveControls.ts`, `model.ts`).

**Every colour, size, radius and font is in [Theme.kt](app/src/main/java/com/wainhq/wain/ui/Theme.kt)**:
the iOS app's dark tokens, and Paper's `--color-phone-light-*` for light mode,
which follows the system (read once in `MainActivity`; a theme change
recreates the activity). Yellow is for *needs you* alone: `accent` fills,
`mark` for a small dot or word. The splash stays dark in both modes, since
brand/build.py writes its mark white. Roboto
stands in for SF Pro; Material is used where Android readers expect it
(back arrow, bottom sheet, pull to refresh, switches).

**The orbs are the [Thinking Orbs](https://github.com/yogesharc/thinking-orbs)
library**, its Compose port from JitPack, pinned to a tag in
`app/build.gradle.kts` as iOS pins the Swift package. `Orb.kt` only maps an
`OrbKind` to its state and variant. Change the drawing there, not here.

**The launcher icon is the iOS icon's layout as vectors**: `res/drawable/ic_launcher_*`
hold the mark, tile and themed (monochrome) layer. The splash is the mark
alone, white and 40dp wide (`splash_mark.xml`), with no tile. The mark carries no shadow, and the legacy
`ic_launcher.png`s come from `python3 brand/build.py --install` with the rest
(MAINTAINING.md); rerun it after moving the mark.

## Build and test

JDK 17 and the Android SDK (platform `android-37.2`, which AndroidX needs to compile against; the app targets 36, what Play requires). AGP 9 compiles Kotlin itself, so there is no `kotlin-android` plugin: the compose plugin's version in `build.gradle.kts` is the Kotlin in use. From `apps/android`:

```bash
./gradlew assembleDebug        # app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest    # the pure logic: turns, runs, markdown, labels
./gradlew installDebug         # onto a running emulator or phone
```

`pnpm test:affected` does not reach this app (no `Cargo.toml` or
`package.json`); run the unit tests above.

**Against a real server on this box**: start a `wain-serve` on its own home
and port, `adb reverse tcp:<port> tcp:<port>`, then open the pairing link:

```bash
WAIN_HOME=~/.wain-android-test wain-serve --port 7419 &
adb reverse tcp:7419 tcp:7419
adb shell am start -a android.intent.action.VIEW \
  -d "'wain://connect?url=ws://127.0.0.1:7419&token=<serve-token>&name=Test'"
```

A `wain` command meant for that server needs `WAIN_HOME` set and
`WAIN_ENDPOINT` unset, or it lands on the box's own server.
