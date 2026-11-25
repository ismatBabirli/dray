#!/usr/bin/env bash
# Builds the `wain-cloud` saved snapshot every Wain Cloud machine is created
# from (#857): a boat sandbox with `wain` and `wain-serve` installed, agents
# installed but signed in nowhere, and the server enabled as a systemd user
# service that starts on its own after create and resume.
#
# Run it on a machine where `boat login` is done, with the Wain Cloud org:
#
#   BOAT_ORG=<org> apps/desktop/scripts/cloud-snapshot.sh
#
# Honours:
#   BOAT_ORG          the org the snapshot is saved in; the control plane's key
#                     must be in the same one (default: the active org)
#   WAIN_VERSION      a cli-v* release to install (default: the newest)
#   WAIN_REF          a git ref to build wain and wain-serve from instead, on
#                     the sandbox. Use this until a release carries #857.
#   WAIN_CLOUD_TOOLS  what `wain setup` installs (default below)
#   BOAT_TYPE         the build sandbox's size (default: boat's default)
#   KEEP=1            leave the build sandbox afterwards, for a look inside
#
# Each step follows docs.boat.dev: `boat new --json` prints JSON Lines ending
# in a `ready` event; `boat ssh ID -- bash -s` runs a script with no tty;
# `boat snapshot ID NAME` saves the disk and polls until the save is ready;
# saving the same name again replaces it, and machines already made keep theirs.

set -euo pipefail

NAME=wain-cloud
TOOLS="${WAIN_CLOUD_TOOLS:-git,gh,claude_code,codex,browser,ffmpeg}"

die() { printf 'cloud-snapshot: %s\n' "$*" >&2; exit 1; }
say() { printf '\033[36m●\033[0m  %s\n' "$*"; }

command -v boat >/dev/null || die "the boat CLI is not installed"
command -v jq >/dev/null || die "jq is not installed"

b() { boat ${BOAT_ORG:+--org "$BOAT_ORG"} "$@"; }

say "Creating the build sandbox"
# No env, as every Wain Cloud create is: nothing of the account's lands on the
# disk the snapshot keeps.
id=$(b new --json --no-env --ttl 7200 --name "wain-cloud build" ${BOAT_TYPE:+--type "$BOAT_TYPE"} \
  | jq -r 'select(.event == "ready") | .id' | tail -n1)
[ -n "$id" ] && [ "$id" != null ] || die "boat new reported no ready sandbox"
say "Build sandbox $id"

cleanup() {
  if [ "${KEEP:-}" = 1 ]; then
    say "Kept $id. Delete it with: boat delete $id --yes"
  else
    b delete "$id" --yes >/dev/null || printf 'could not delete %s; delete it by hand\n' "$id" >&2
  fi
}
trap cleanup EXIT

b ssh "$id" -- env \
  WAIN_VERSION="${WAIN_VERSION:-}" WAIN_REF="${WAIN_REF:-}" TOOLS="$TOOLS" \
  bash -s <<'REMOTE'
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
step() { printf '\033[36m●\033[0m  [sandbox] %s\n' "$*"; }

# The release install first even when building from source: it also puts the
# skill in place and `~/.local/bin` on PATH. No setup questions here.
step "Installing wain ${WAIN_VERSION:-(newest release)}"
curl -fsSL https://www.wainhq.com/install.sh | WAIN_UPDATING=1 WAIN_VERSION="$WAIN_VERSION" sh

if [ -n "$WAIN_REF" ]; then
  step "Building wain and wain-serve at $WAIN_REF"
  sudo -n apt-get update -qq
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential pkg-config git curl
  command -v cargo >/dev/null || curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
  src=$(mktemp -d)
  git clone -q https://github.com/ismatbabirli/wain "$src"
  git -C "$src" checkout -q "$WAIN_REF"
  (cd "$src/apps/cli" && cargo build -q --release)
  # The server's own profile, as release-cli.yml builds it; a ref from before
  # it existed has only `release`.
  profile=release
  grep -q '^\[profile\.serve\]' "$src/apps/desktop/src-tauri/Cargo.toml" && profile=serve
  (cd "$src/apps/desktop/src-tauri" && cargo build -q --profile "$profile" --no-default-features --features serve --bin wain-serve)
  install -m 755 "$src/apps/cli/target/release/wain" "$src/apps/desktop/src-tauri/target/$profile/wain-serve" "$HOME/.local/bin/"
  rm -rf "$src"
fi

# Without linger systemd starts no user service at boot, and a machine made
# from this snapshot would come up with no server on it.
step "Turning on linger"
sudo -n loginctl enable-linger "$(id -un)"
[ "$(loginctl show-user "$(id -un)" --property=Linger --value)" = yes ] || { echo "linger is off" >&2; exit 1; }

step "Installing $TOOLS and starting the server"
wain setup --tools "$TOOLS" </dev/null

# setup warns on a tool that failed and starts the server anyway. Run again
# with nothing named and no terminal, it lists what is still missing, judged
# by its own test — the browser's is a set of libraries, not a binary.
missing=$(wain setup </dev/null 2>&1 | sed -n 's/.*Not installed: //p' | tr -d ' ')
failed=
for tool in ${TOOLS//,/ }; do
  case ",$missing," in *",$tool,"*) failed="$failed $tool" ;; esac
done
[ -z "$failed" ] || { echo "did not install:$failed" >&2; exit 1; }

[ "$(systemctl --user show wain --property=OOMPolicy --value)" = continue ] \
  || { echo "the unit has no OOMPolicy=continue; this wain predates #708's fix" >&2; exit 1; }
for _ in $(seq 30); do [ -s "$HOME/.wain/serve-token" ] && break; sleep 1; done
[ -s "$HOME/.wain/serve-token" ] || { echo "the server never wrote its token" >&2; exit 1; }

step "Stopping the server and clearing what is this sandbox's own"
systemctl --user stop wain
# The control plane writes serve-token and cloud.json into every create; the
# rest is this build sandbox's, and every task's machine would start with it.
rm -rf "$HOME/.wain/sessions" "$HOME/.wain/serve-token" "$HOME/.wain/cloud.json" \
  "$HOME/.wain/serve-port" "$HOME/.wain/tunnel-url"

# boat writes a create's files before it reports ready, but nothing says
# before a lingering user service starts. A server up first mints a token of
# its own and never reads the one written over it, so it waits — a minute at
# most, then starts regardless. A resume has both and waits for nothing.
mkdir -p "$HOME/.config/systemd/user/wain.service.d"
cat > "$HOME/.config/systemd/user/wain.service.d/cloud.conf" <<'UNIT'
[Service]
ExecStartPre=/bin/sh -c 'for i in $$(seq 60); do [ -f %h/.wain/cloud.json ] && [ -f %h/.wain/serve-token ] && exit 0; sleep 1; done'
UNIT
systemctl --user daemon-reload
systemctl --user is-enabled --quiet wain || { echo "the server is not enabled" >&2; exit 1; }
step "Ready: $(wain-serve --version)"
REMOTE

say "Saving the disk as $NAME"
b snapshot "$id" "$NAME"
say "Saved. New Wain Cloud machines start from it; machines already made keep theirs."
