# Stage 2: installing Wain on a VPS

ismatbabirli/wain#415, flow A. The user SSHes into a fresh Linux box and pastes
the line that already installs the CLI:

```bash
curl -fsSL https://www.wainhq.com/install.sh | sh
```

On Linux that line now leaves a whole Wain behind: `wain`, `wain-serve`, the
tools the reader ticked, a server running in the background, and the line to
paste into the app.

## Release

**One archive per target, one tag.** `release-cli.yml` already builds `wain`
for both Linux arches. The Linux legs also build `wain-serve` from
`apps/desktop/src-tauri` (`--no-default-features --features serve`) and pack it
into the same `wain-<target>.tar.gz`. One download, one checksum, so the two
binaries can only ever arrive at one version. The macOS legs build it too
(#470), for a Mac with no app; on a Mac with the app it sits unused.

**Linux legs move to `ubuntu-22.04` / `ubuntu-22.04-arm`.** A binary needs the
glibc it was linked against or newer; `ubuntu-latest` is 24.04 (glibc 2.39), so
today's Linux `wain` refuses to run on Ubuntu 22.04 and Debian 12. Building on
22.04 sets the floor at glibc 2.35. musl was the other route and is not worth
it for the core's C dependencies.

Nothing else moves: `cli-v*` tags, `prerelease: false`, the resolver, the
tag-matches-crate check.

## install.sh

After the binaries land, not under `wain update` and not on a Mac with the Wain
app, it runs `wain setup`. Whatever is in the archive is installed, so the script stays one
code path for both platforms.

`wain update` sets `WAIN_UPDATING=1` so the installer neither runs setup nor
restarts the server. Restarting kills every running agent, and the usual caller
of `wain update` is an agent inside that server. It prints the restart command
instead when a service is installed.

`wain setup` gets `/dev/null` as stdin. Under `curl | sh` stdin is the rest of
the script, and a child reading it eats the installer.

## The `wain` binary

Three new subcommands. None talks to the app socket and none changes the wire,
so no protocol bump.

- **`wain serve [args]`** execs `wain-serve` beside itself.
- **`wain setup [--install <names>]`**:
  1. Lists what is present: `git`, `gh`, `claude`, `codex`, `pi`, `fx`, `grok`.
     Found = on `PATH` or in `~/.local/bin` and the few dirs vendor installers
     use.
  2. Offers what is missing as a multi-select in the `npx skills` style, read
     from `/dev/tty`. Arrow keys, space, enter; `git` preselected because Wain
     needs it. No terminal: installs only what `--install` names.
  3. Agents: the vendor's own script, off `wain_proto::AGENTS`, which a test
     in `harness.rs` holds equal to `Harness::install_command` and
     `login_command` (the CLI cannot link the app). `gh`: its release tarball
     into `~/.local/bin`, checksum verified.
     `git`: the package manager when root or `sudo -n` works, else print the
     command and move on.
  4. Prints the logins still to do: `gh auth login` when `gh auth status`
     fails, and each installed agent's login command.
  5. Runs `wain service start`.
  6. Prints `ssh user@address`, read off `SSH_CONNECTION` (the address the
     reader actually connected to; `-p` when not 22), falling back to the
     hostname.
- **`wain service start | status | uninstall`**: a systemd user unit
  `wain.service` plus `loginctl enable-linger`, so it survives logout and
  reboot. `PATH` is captured at start into the unit, with `wain`'s own dir
  first, so agents find what the reader's shell finds. No systemd: say so and
  name `wain serve` under tmux as the fallback.

## Not here

Stage 4's side: the app reading `serve-token` over SSH, port forwarding, starting
a stopped server.

## A Mac with no app (#470)

`wain setup`, `wain serve` and `wain service` run on a Mac too, gated on the
app being absent rather than on the OS: its login agent
(`com.wainhq.wain.server.plist`) or `Wain.app` in either Applications folder
means "the Wain app runs this Mac's server", and all three refuse. Setup still
offers the tools there and stops. A `WAIN_HOME` of its own lets them through,
the same way round `serve.lock` names. `wain service uninstall` is never
refused, since it is how a server set up before the app arrived hands over.

- **`wain service`** is a LaunchAgent, `com.wainhq.wain-serve` in the `gui`
  domain, modelled on the app's launchd.rs: `KeepAlive` on a failed exit
  (systemd's `Restart=on-failure`), `PATH` and `WAIN_HOME` in the plist, log in
  `<home>/server.log`. Restart is `bootout` then `bootstrap`, never
  `kickstart -k`, which reruns the job as loaded and misses a rewritten plist.
  `service tunnel` is Linux only; `wain tunnel` runs in the foreground.
- **`wain-serve` writes `serve-port`**, so an app installed later connects to
  it as This Mac, and answers `live_state`, which the app re-asks This Mac on
  startup. Remote access stays the app's server's alone. It answers the app's
  `restart_when_idle` with "unknown command" and stays up, and the app's own
  agent fails on `serve.lock` and retries every 10s until `wain service
  uninstall` lets it take over.

Tested on a Mac logged in at the GUI, with the app installed and a scratch
`WAIN_HOME`: start, status, a Claude Code turn, launchd restarting a killed
server, a second start leaving it running, uninstall, and a client admitted the
way the app's This Mac is, off `serve-port`. Not tested, beyond the app itself
meeting a `wain-serve`:

1. **No GUI login, by design.** A `gui` domain job runs only while its user
   is logged in at the Mac: it stops at logout and starts again at login. A
   server while nobody is logged in is deliberately out of scope, so no
   LaunchDaemon. Over SSH with nobody logged in, bootstrap fails and setup
   says to log in or turn on automatic login.
2. **Keychain.** Claude Code's login, in the Keychain, worked from the job here
   because the login keychain was unlocked by the GUI login. Expect auth to
   fail from a job with the keychain locked, which points at automatic login
   as the answer to 1 too.
3. **TCC.** `ls ~/Documents` from an agent under the job answered with no
   prompt on this Mac, which may hold grants a fresh one does not. On a fresh
   Mac keep repos out of `~/Documents`, `~/Desktop` and `~/Downloads`. The
   binaries are ad-hoc signed, so each `wain update` is a new TCC identity
   until they carry the Developer ID.

## What testing found

- **Grok's installer is bash.** `curl … | sh` fails under dash, Ubuntu's
  `/bin/sh`, so both tables now say `| bash`. The app's missing-CLI notice was
  handing Linux readers the broken line too.
- **pi and Grok land outside `~/.local/bin`** (`~/.pi/agent/bin`,
  `~/.grok/bin`), reaching `PATH` only through `.bashrc`, which a
  non-interactive login shell never reads. So the unit's `PATH` names every
  agent dir whether it exists yet or not, and the server found all five.
- **Vendor installers ask their own questions.** Codex offers to start itself
  (default No). pi offers to install Node, then to start pi (default Yes), so a
  reader pressing Enter lands in pi's TUI and setup carries on when they leave
  it. Left as the vendors wrote them.
- **One server per machine.** `wain-serve` binds `127.0.0.1:7417`, so a second
  user's server cannot start. Setup now checks the service stayed up and says
  so rather than claiming it runs. Stage 4 can read a port if this matters.
- **Linger without sudo is refused** on Ubuntu 24.04; setup then prints the
  `sudo loginctl enable-linger` line.
- **A NAT'd VM** sees its private address in `SSH_CONNECTION`, so the Add server
  line carries a note to use the address the reader actually typed.

## Testing

OrbStack machines (systemd inside): Ubuntu 24.04 on arm64 and amd64. The
installer run end to end from a copy pointed at local archives, a reboot of the
machine, the server answering afterwards. Then the real VPS.
