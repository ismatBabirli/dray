#!/usr/bin/env bash
# The versions a beta from `main` ships under, and writing them into a build.
#
#   beta-version.sh next <n>
#     Prints `app=<version>` and `cli=<version>` for $GITHUB_OUTPUT: the next
#     patch of each, `-beta.<n>`, so 0.37.0 gives 0.37.1-beta.<n>. A version
#     already a prerelease keeps its own X.Y.Z, which is still ahead of it.
#     Semver puts the beta below that next release, so beta users move onto
#     the stable release once it ships.
#   beta-version.sh set-app <version>
#     Writes <version> into the app's package.json, tauri.conf.json,
#     Cargo.toml and Cargo.lock, never committed.
#   beta-version.sh set-cli <version>
#     The same for apps/cli. The lock is written too, since Windows builds
#     with --locked.
set -euo pipefail

app=apps/desktop/src-tauri
cli=apps/cli

die() { echo "::error::$*" >&2; exit 1; }

# The `version = "…"` under [package], the first one in the file.
crate_version() { sed -n 's/^version = "\(.*\)"$/\1/p' "$1/Cargo.toml" | head -n 1; }

next_of() {
  local v=$1 n=$2 base
  base=${v%%-*}
  [[ "$base" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "not a version: $v"
  if [ "$base" = "$v" ]; then
    base="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
  fi
  echo "$base-beta.$n"
}

# The root package's entry: `name = "wain"` and the version line under it.
# Both crates are named wain, and nothing they depend on is.
set_lock() {
  local lock=$1 v=$2 tmp
  tmp=$(mktemp)
  awk -v v="$v" '
    hit && /^version = / { print "version = \"" v "\""; hit = 0; done = 1; next }
    /^name = "wain"$/ { hit = 1 }
    { print }
    END { if (!done) exit 1 }
  ' "$lock" > "$tmp" || { rm -f "$tmp"; die "no wain package in $lock"; }
  mv "$tmp" "$lock"
}

set_crate() {
  local dir=$1 v=$2 tmp
  tmp=$(mktemp)
  awk -v v="$v" '
    !done && /^version = / { print "version = \"" v "\""; done = 1; next }
    { print }
  ' "$dir/Cargo.toml" > "$tmp"
  mv "$tmp" "$dir/Cargo.toml"
  set_lock "$dir/Cargo.lock" "$v"
  [ "$(crate_version "$dir")" = "$v" ] || die "$dir/Cargo.toml still says $(crate_version "$dir")"
}

set_json() {
  local file=$1 v=$2 tmp
  tmp=$(mktemp)
  jq --arg v "$v" '.version = $v' "$file" > "$tmp"
  mv "$tmp" "$file"
}

valid() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]] || die "not a beta version: $1"; }

case ${1:-} in
  next)
    n=${2:?next takes the beta number}
    [[ "$n" =~ ^[0-9]+$ ]] || die "not a number: $n"
    echo "app=$(next_of "$(jq -r .version "$app/tauri.conf.json")" "$n")"
    echo "cli=$(next_of "$(crate_version "$cli")" "$n")"
    ;;
  set-app)
    v=${2:?set-app takes a version}
    valid "$v"
    set_json "$app/tauri.conf.json" "$v"
    set_json apps/desktop/package.json "$v"
    set_crate "$app" "$v"
    echo "app version: $v"
    ;;
  set-cli)
    v=${2:?set-cli takes a version}
    valid "$v"
    set_crate "$cli" "$v"
    echo "cli version: $v"
    ;;
  *) die "usage: beta-version.sh next <n> | set-app <version> | set-cli <version>" ;;
esac
