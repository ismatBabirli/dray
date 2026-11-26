<!--
Rules for the AI reviewer: .github/workflows/claude-review.yml reads this file
from each pull request's BASE commit and puts it in the review prompt, so a
change here takes effect from the pull request after the one that merges it.
-->

The root CLAUDE.md imports MAINTAINING.md; read both. Before judging a change to
a subsystem, read its note under `apps/desktop/docs/` (CLAUDE.md's "Subsystem
notes" lists them) and the PLAN.md of any app the pull request touches
(`apps/ios`, `apps/android`, `apps/island`, `apps/island-linux`; README.md for
`apps/gpui`).
Around each change, open the callers, the `serve.rs` command table, the
generated `apps/desktop/src/types/events.ts`, the clients that read the event or
command, and the fixtures and tests that cover it.

Look hardest for:
- the wire: a serve command, event or field renamed, removed or newly required
  without the matching change in the iOS `Codable` types, Android's
  `wire/Wire.kt` and the files Wain Island compiles by path; a new core command
  missing its line in `serve.rs`'s table, or an app-only one missing from
  `transport.ts`'s `APP_COMMANDS`;
- the headless build: core code naming Tauri outside the `desktop` feature;
  the frontend importing `invoke` or `listen` from `@tauri-apps/api` instead of
  `@/lib/transport`, or using `convertFileSrc`;
- the CLI wire: a `parser.rs` field the CLI may omit or send as `null` without
  `default` and `null_as_default`; a stream enum without its `#[serde(other)]`
  arm; a permission or control reply in a new shape, which the CLI ignores
  silently and so hangs the turn; a `result` line that can fail to close the
  turn;
- spawning: `Command::new("claude")` or another agent by bare name instead of
  through `binpath`; a permission request, question or decision persisted to
  the log;
- persistence: `index.json`, `settings.json`, `credentials.json`,
  `projects.json` or `drafts.json` written without its lock or without
  write-temp + rename; `seq` taken from the last line instead of `max_seq`;
- `src/types/events.ts` edited by hand, or committed with types a filtered or
  Linux `cargo test` dropped;
- git: a `git diff` without a trailing `--`; anything that runs `git checkout`
  under a live session;
- GitHub API cost: a new or widened GraphQL query or poll whose `rateLimit
  {cost}` was not measured;
- privacy: a prompt, reply, path, file content, email or token in a log line,
  an error report or a PostHog event;
- release and repo safety: an action pinned to a tag instead of a full SHA; a
  new secret reaching a workflow that runs on outside pull requests; a change
  to signing, notarization or the updater's trusted key;
- a dependency in the root `package.json`, a lockfile other than
  `pnpm-lock.yaml`, or a new dependency where an installed one does the job;
- docs and site copy promising something the code does not do;
- a test weakened, skipped or deleted, or a fixture edited to make one pass;
- plain bugs: wrong logic, unhandled error paths, races, a React state update
  per streaming delta, a loop or poll that never ends.

High severity here: a shipped client broken (the desktop app, a phone app, Wain
Island or an older `wain-serve`), a turn that hangs, data lost or written to the
wrong session, a security or privacy hole, a crash.

Never quote a token, credential, signing secret, email or a user's prompt from
the code, fixtures or captured logs; refer to the file and line.

Not available to you: Linear issues (DRA-…) named in the pull request, the
Paper design file, the infra repository and its runbooks, and the running app.
Judge against CLAUDE.md, MAINTAINING.md, the docs and the code.
