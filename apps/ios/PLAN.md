# Wain for iPhone

A native SwiftUI client for `wain-serve`. It runs no core and no agent: every
session lives on a server — This Mac through Remote access, or a VPS — and the
phone reads and drives it over the same WebSocket the desktop uses
([SERVE-PLAN.md](../desktop/SERVE-PLAN.md)).

## What v1 does

- **Four tabs: Home, Bots, Tasks, Routines** (#27, Paper's "iPhone — tabs"),
  always all four and in that order, a tab never an action. The rules both
  phone apps follow are restated in `TabsLogic.swift` and held by
  `TabsLogicTests`. Home answers what wants the reader across every bot and
  task on the shown machines: usage chips, then **Waiting on you** (cards
  answered in place, PRs ready to merge with Merge on the card, a bot's task
  gone quiet), **Working**, and **New since you looked**, each hidden when
  empty; all empty is All clear. Its badge (yellow) counts what waits. Bots is
  the roster (waiting, unread, working, the rest, newest first), its badge
  (red) the bots with unread replies. Routines lists every bot's routines,
  soonest next run first and paused ones last; the switch pauses one, a long
  press deletes it, a tap opens its bot, and making one is asked of a bot. The
  tab bar hides inside a chat (`setTabBarHidden`, driven from the root: the
  adaptable tab view read SwiftUI's per-view setting from tabs not on screen).
- **Machines** leads every tab's bar, its dot the worst state of the shown
  machines: green all fine, yellow one needs the reader, grey one out of
  reach. Its sheet shows all machines or one (kept on the phone, cleared when
  that machine is removed), each with its health and Retry, then Usage, Pair
  a machine and Settings. The filter is the phone's alone.
- **Usage** (#26): `live_state.usage` and `usage_changed` carry one reading per
  agent per server. Home's chips take each agent's worst five-hour reading
  across the shown machines, red with "back HH:MM" once at its limit; the
  Usage sheet draws every window by machine; the composer's model chip rings
  the session's own machine's reading; Machines counts how many are at their
  limit.
- **Tasks is the desktop sidebar's live list**, bots left out: stages workspace-wide with a gap between runs and no headings, PR marks
  read through `pr_marks` once per repo, and a strip of project names under
  the bar to narrow it. Drafts (`list_drafts`) and settled sessions are two
  more views of the same list. A session's card is answered under its row.
  Pins are not drawn apart.
- **Transcript**, live, shaped like the desktop's: finished turns fold to
  prompt, summary line and answer; runs of one tool group into a row; a
  running turn keeps its newest five rows on screen. No diffs, no
  highlighting. A tapped picture opens full screen among the rest of its
  turn's: swipe or the strip to page, pinch to zoom, drag down to close.
- **Reply** from the composer at the session's foot (`Composer.swift`): a
  field with the mic at its trailing edge, Send once there are words, and
  Stop beside it while a turn runs, when it reads "Queue a message". A tap on
  the mic dictates hands-free: the field grows, a level meter, the time so
  far, Cancel and Done; holding it talks while held. The words land in the
  field to edit. Words come back once the recording is read, not as they are
  spoken, since neither engine streams. Where nothing can transcribe the mic
  is hidden. In a
  bot's chat a swipe in from the right edge opens its Tasks sheet, the button
  being a reach to the top of the screen. The model chip and
  "···" open **This task**: the session's model, effort, fast mode and
  stance for the next reply, each locked mid-turn where the harness can't
  carry it onto a queued prompt (`liveControls.ts`, restated in
  `Picks.lockedMidTurn`). Nothing there reaches the session until a reply
  goes out, since `send_msg` is what carries it. Its agent row moves the
  session to another agent at that send (#1439), as the desktop does: a task
  calls `switch_agent` first and continues in place, so a server from before
  it refuses and nothing goes out; a bot chat starts a new session in its
  folder. Neither draws a line in the chat, and `agent_switched` moves the
  picker when the switch was made elsewhere. **Stop** sits at the end of
  the picks while a turn runs. The top bar names the project and machine,
  never the branch.
- **Permission and question cards**, answered in place. A hidden task's card,
  a bot's above all, draws at the foot of the chat that started it under the
  task's title, on whichever machine the task runs, and lights the bot's face.
- **Reactions in a bot's chat** (#1416), never a task's: a long press on the
  bot's message opens the seven emoji and nothing else, so its words cannot be
  copied there while the chat is open (`react_to_message`). The pick is a badge
  beside the bubble's bottom corner; the bot's own sits beside the top corner
  of the reader's. Both are overlays, so neither moves a row.
- **New task** from the compose button at the top right of Home and Tasks:
  a sheet with the composer's field and mic, then Run by (Me, or a bot, whose
  folder the words go to), Project, Agent, Machine and Worktree, and Start
  task. Save keeps it as a draft (`create_draft`); Cancel with words offers
  Save draft, Discard or Keep editing. The Agent row opens **Run with**: server (where two hold the
  project), project with Attach inside its menu, worktree, the agent and its
  model as chips, effort, fast mode and stance. Double-tapping a model stars
  it, on this phone, per agent; starred ones lead. With the worktree off a
  Branch row switches the checkout at once (`checkout_branch`), asking
  Bring or Stash first where files are uncommitted, as the desktop does.
  On an iPad or an unfolded Duo the tabs become a sidebar
  (`.sidebarAdaptable`, iOS 18): Home, each bot under Bots, All tasks and each
  project, Routines, with the chosen one beside it.
- **Open bot at launch** (Settings, Off by default): a cold launch opens the
  picked bot's chat on the Bots tab as its first screen, read off the cached
  list before the first frame, so the list never shows first; Back is the roster. A bot with no
  chat cached waits on its server's index and bots, then opens its own page.
  Coming back from the background, a link, a tap first or ten seconds and the
  list stays. Nothing opens by itself with it Off, one bot or not.
- **Pairing** by paste or by QR, and every server's name, token and removal
  in one Settings screen.
- **Shared machines** (#847): a paired server that shares its list
  (`share_machines`, `machines_shared`) adds each machine as a server of its
  own, never saved, with a hello naming `via` its id and `/file`/`/upload`
  carrying `via=`, under the paired server's token. Its id is hashed from the
  pair, so transcripts survive a reconnect. The Island skips this: it follows
  the app's links, which already name those machines. **A machine the phone
  also pairs directly is shown once, the direct way** (#1404): every welcome
  carries `identity`, a hash of the server's token that a relay passes
  through untouched, so a relayed copy whose `identity` hashes a token the
  phone holds gives way to the direct pairing **while that one works**
  (#1466): a copy on screen goes once its twin connects, never before, so a
  reconnect takes no open chat away; a copy not on screen stays off while its
  twin is coming up, and comes back once the twin is lost or turned off.
  Identities are kept across launches, so a launch draws no duplicate even
  for a moment. An alert tagged by a copy that gave way opens and answers on
  its twin (`reachable`). A server from before `identity` is still shown twice. Never `id` in a welcome:
  `Head` reads every frame's `id` as a call's, and fails on a string.
- **Pull request** sheet from the session view: readiness in the desktop's
  order with checks speaking first, checks failing-first, comments; every
  check and comment opens on GitHub. Merge is the desktop's split button —
  the chevron picks the method, kept on the phone, and a confirm runs before
  it lands; it stays shut while checks run or fail. Mark ready, reopen.
  Hidden when the branch has none. Reads and merges only: no comment, reply
  or close.
- **Changes** (#1326), a button in the session's top bar pushing its own
  screen: uncommitted work against HEAD, a tab only while `work_status`
  counts some and then the one it opens on, the whole branch from the parent
  of its oldest own commit (`log_branch_commits`) to its tip, and the
  history, a commit opening its own files. No last turn: the desktop's
  Changes panel is where that lives. Files group under their folder,
  each with the desktop's Material glyph (`scripts/file_icons.py` copies the
  set and its lookup from `apps/desktop`). Every file opens a unified diff
  built on the phone from `file_change`'s two sides, lines wrapping. Only
  calls `wain-serve` has had from the start. Reads only, like the repo view.
- **Dictation**, transcribed on the Mac or on the phone: the phone records a
  16kHz mono WAV, then either uploads it through `POST /upload` and calls
  `transcribe_upload` — only the Mac's server has that command, and its
  welcome frame says `dictation: true` — or, from iOS 26, reads it with
  Apple's `SpeechAnalyzer` (#1261). Settings › Dictation picks one; with no
  pick a server that can goes first, then Apple. Below iOS 26 Apple shows
  disabled. Apple asks no speech recognition permission: that prompt is the
  old `SFSpeechRecognizer`'s and says speech goes to Apple. The simulator's
  analyzer offers no audio format, so a read there fails; test it on a phone.
  Where nothing can transcribe, every composer hides its mic. The Island's
  `VoiceOrb.swift` is still compiled in for the `Dictation` states it defines.
- **Pull requests and Issues** (#1361), the desktop's two pages, each a
  button at the top right of Tasks opening a sheet with its own stack.
  GitHub's search and the trackers are asked through `trackerServer`: the
  Mac app's server where one is connected, else the first. Both keep their
  last answers on disk, per server; a server switched off loses its kept
  answers and their freshness at once, so none draws and it is read afresh
  once back on (#1547). A GitHub repository picked through one server is no
  pick on another that does not hold it.
  - Pull requests (`Pulls.swift`, `PullDetail.swift`, rules from
    `prInbox.ts` restated and tested in `PullsTests`): All reads each
    project's `pr_marks` with `listing`, plus bot tasks' repos; the other
    three filters are one `pr_search`, each row read through a checkout
    `repo_checkouts` finds, else its `github:` slug. Spaces, Owner and
    Repository sit behind the filter button. The phone has no active space,
    so Spaces starts on All. A PR opens the PR sheet's rows, a comment
    opening in place on a tap, and its tasks newest first (a settled one
    opens with no dock). The top bar holds Share (the system sheet) and play,
    which opens the start sheet (`StartTask.swift`): the reader's words, a
    bot's task or the reader's own on a machine, agent, model, effort and
    fast mode, always Auto. A checkout is attached or cloned
    (`clone_github_repo`) only on Start, then `start_pr_session`.
  - Issues (`Issues.swift`): GitHub and Linear, the desktop's scopes,
    Open/Closed, search, repository, type and label or team and project;
    Linear grouped by state with Done and Cancelled read on opening. An
    issue moves its status and priority (`update_issue`). Its play opens
    the same start sheet: sent to a bot (`send_issue_to_bot`), or a task
    right there (`send_msg` with `issueIds`) on a checkout of the issue's
    repo, cloned if none, any project for Linear's; the task then opens.
    Linear connects by pasting a key.

Left out: push, attachments, the Diff/Files/Browser views,
forks, settle/pin, the settled list, spaces.

## Stack

SwiftUI, iOS 17 (`@Observable`), iPhone and iPad from one `TabView`:
`Tab`, `TabSection` and `.sidebarAdaptable` from iOS 18, a plain tab bar on
17. Each tab owns a `NavigationStack` whose path lives in `Nav` (`Tabs.swift`).
**One dependency**, [Thinking Orbs](https://github.com/yogesharc/thinking-orbs)
for the working orb, pinned to a revision in `project.yml`. Everything else is the
platform's: `URLSessionWebSocketTask` for the socket, `AttributedString(markdown:)`
for text, VisionKit's `DataScannerViewController` for QR, Keychain for tokens.

The Xcode project is generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`; the `.xcodeproj` is not committed, since a hand-merged
`project.pbxproj` is the one file in an iOS repo nobody can review.

```bash
cd apps/ios && xcodegen && open Wain.xcodeproj
```

Bundle id `com.plorigo.wain.ios`, team `FBH9JL8MB9`.

**To TestFlight** — with Xcode signed in to the team's Apple ID and the app
record made in App Store Connect:

```bash
cd apps/ios && xcodegen
xcodebuild -project Wain.xcodeproj -scheme Wain -destination generic/platform=iOS \
  -archivePath build/Wain.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Wain.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build -allowProvisioningUpdates
```

`ExportOptions.plist` uploads as it exports and lets App Store Connect number
the build, so `CURRENT_PROJECT_VERSION` never needs bumping by hand.

## Design

Follows the system's appearance: the desktop's dark tokens, and Paper's
`--color-phone-light-*` for light; yellow fills keep `--color-phone-accent`
(`Theme.accentFill`), small yellow marks and words take the light accent.
Its one yellow and its radius scale. **Every colour, size, radius, font and
haptic is in [Theme.swift](Wain/Theme.swift)** and nowhere else; a view naming a hex or a
point size is a bug. Yellow means *needs you* — a card, a refused token, an
app to update — and nothing else, so the global tint is the page's ink.
Rationale and the screens it was judged on are in #631.

- **Each tab's bar leads with Machines and its title beside it.** Tasks'
  title is the Live / Drafts / Settled menu, Pull requests and Issues share
  one glass pill on its right, then New task; the project strip of chips sits
  under the bar once there are two projects. Rows are one line; a child hangs off its parent on a solid elbow,
  and a waiting card sits under its row, a fill and no border.
- **An empty list is the whole screen** ([EmptyArt.swift](Wain/EmptyArt.swift)),
  drawn in the middle, on every tab while nothing shown answers: pair a
  machine, connecting, can't reach with its countdown. Then each tab's own:
  Home's All clear, No bots yet, No routines yet with Ask a bot, and Tasks'
  no tasks yet or all clear with the last task settled today.
- **One type scale** in `Theme.Font`, five rungs, SF Pro only, regular and
  semibold only. Buttons are semibold: Headline full-width, `pill` compact;
  a text-only action stays regular.
- **Each server reports its own trouble**, written by `Store.health`
  ([ConnectionStatus.swift](Wain/ConnectionStatus.swift)): reconnecting,
  can't reach with a visible countdown, token refused, protocol behind in
  either direction, a list that failed to load. Each carries Retry or Fix, and
  none holds up another server. In the list it is a card at the top and that
  server's tasks dim; in a session it floats under the title bar and the dock
  dims, still usable. Offline is one banner, not one per server.
- **A failure stays where it happened.** A failed send keeps the draft and
  offers Retry under it; a failed transcript read is the screen's own empty
  state with Try again; an action with nowhere of its own is a toast, never an
  alert.
- **Orbs.** [Orb.swift](Wain/Orb.swift) is the one place app states map to
  the package's: working, delegating (gyro), background (spiral), reconnecting
  (lighthouse, fast), loading. Dictation draws no orb: the composer's strip
  shows the recorder's meter.

**Screens are checked by `DesignTests`**, which walks every screen and failure
state and attaches a screenshot of each. Two stand-ins answer the failure
states a real server cannot be made to show (`/tmp/wain631-fake.py` in #631).

## The wire, as the phone speaks it

One socket per server. Address is the `wss://…` Remote access shows, or any
`ws://host:port`.

```text
→ {"v":1,"token":"…"}
← {"v":1,"version":…,"release":…,"stale":…}   or {"err":"…"}
← {"event":"live_state","payload":{"asks":[…],"tasks":[…],"usage":[…]}}
→ {"id":n,"cmd":"…","args":{…}}               camelCase args, as invoke sends
← {"id":n,"ok":…} | {"id":n,"err":…}
← {"event":"agent_event"|"session_status"|"session_created"|"session_title"|…,"payload":…}
```

No `Origin` header is sent, so the server's browser check does not apply; the
token answers for the connection.

Commands used: `list_session_index_items`, `get_session_by_id`,
`get_session_page`, `get_session_calls`, `send_msg`, `interrupt_session`, `respond_permission`,
`answer_questions`, `list_projects`, `agent_availability`, `list_models`,
`list_branches`, `checkout_branch`, `mark_session_read`, `work_status`,
`prs_for_branch`, `merge_pr`, `mark_pr_ready`, `reopen_pr`, `set_last_selected_project`,
`add_project`, `github_repos`, `clone_github_repo`, `recheck_gh`, `pr_marks`,
`transcribe_upload`, `create_draft`, `delete_draft`, `list_bots`,
`list_routines`, `set_routine_paused`, `delete_routine`. Events read beyond
the session ones: `usage_changed`, whose payload is the server's whole list.

**A new task restates the desktop composer's rules** (`Picks` in
`Picks.swift`): which stances each harness honours (`permission.ts`),
fast mode only where the harness has a route and the model a faster tier
(`fastMode.ts`), the effort ladder per model and the model fallback
(`model.ts`). Change one there, change it here.

**Types are hand-written `Codable`, and every decode is lenient.** An unknown
event `type` decodes as `.unrecognized`, an unknown enum value as its raw
string — the rule `Harness::Other` already follows, since a newer server must
never take the list down.

## Identity

A session is `(serverId, sessionId)`. The server id is a UUID the phone mints
when a server is added. Nothing on the wire carries it; the connection a frame
arrived on is the answer.

**A server can be switched off on the phone alone** (`Server.on`, saved with
the list and read as on where absent). Off drops its connection and everything
held of it, so its tasks, cards, banners and Run with rows go; nothing is sent,
and its tasks keep running there. Everything the list reasons about reads
`store.live`, never `store.servers`, or an off server comes back as a stuck
"Connecting".

## Transcript

Built from the events, the desktop's rules cut down:

- events carrying a `subagent` are not drawn — the desktop filters them too;
- `tool_call_started` and `tool_call_completed` join on `callId`; a call with
  no result is pending only while the session is `in_progress`;
- deltas are dropped; the orb and a word stand in while a turn runs;
- a failed turn draws its `finalText` as a red row; a user's Stop draws none.

The shape is `buildTranscript` and `TurnBlock`'s, ported in `Transcript.swift`:
a finished turn of three rows or more folds behind "N tool calls · M messages"
with its last message below; consecutive calls to one tool group ("Read 3
files", "Edited Store.swift +12 -3"); a queued prompt cuts the work so it stays
where it was typed; a running turn draws its newest five rows and slides older
ones up under the summary line. Labels follow `tools.ts` (`Tools.swift`) —
keep the two in step.

The orb is the package's own, mapped in `Orb.swift`: the working state while a
turn runs, gyro for a subagent, spiral for background tasks.

Opens on the newest turns (`turns: 8`), pages older ones in on scroll to top.
A reconnect re-reads the open session's tail and appends what it does not hold,
matched on event id, never `seq`.

The view holds the end only while the reader is within 40pt of it, the
desktop's pin: a scroll up leaves them where they are, coming back or sending
follows again (`FollowsBottom`, iOS 18; iOS 17 follows new rows only, always).
The pin answers the content's height and the room it shows in, not new rows:
a picture's placeholder is 10pt tall and a video's is a guess, so a chat grew
by hundreds of points after it opened and the newest message sat behind the
dock (#1104). The stack is a `VStack`, not lazy: a lazy one's height estimates
left a chat opened from the cache scrolled past its end, blank, once the read
drew less.

`OpenAtBottomTests` checks all of it against a scratch server behind
`scripts/late_turns_proxy.py`, which holds media back and lands turns on
demand. A Mac serves a picture before the first frame, so without the proxy
every one of these passes on a build that fails on a phone.

## Pairing

A connect line is `<address> <64-hex token>`, what `wain server tunnel on`
already prints. The QR encodes `wain://connect?url=<address>&token=<token>&name=<name>`,
which the phone registers as a URL scheme, so the system Camera opens it too.

- **The Mac app** draws the QR on This Mac's Remote access row, beside the
  address, once the address is up.
- **`wain server pair`** prints it in the terminal, for a VPS with no app.

## PRs

1. The app: connect by paste, list, transcript, reply, cards.
2. New session.
3. QR: the desktop row, `wain server pair`, the phone's scanner.
