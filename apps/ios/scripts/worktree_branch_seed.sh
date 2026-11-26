#!/bin/sh
# WorktreeBranchTests' repo, at $1/repo with a bare $1/origin.git behind it: main behind
# its remote, feature/remote-only on the remote alone, local-only here alone, shared in
# both and one behind, local-two for the checkout switch, and an untracked file.
set -eu
root=$1
rm -rf "$root/origin.git" "$root/repo" "$root/other"
mkdir -p "$root"
git init -q --bare -b main "$root/origin.git"
git clone -q "$root/origin.git" "$root/repo" 2>/dev/null
cd "$root/repo"
git commit -q --allow-empty -m one
git push -q -u origin main
git branch local-only
git branch local-two
git switch -q -c shared
git push -q -u origin shared
git switch -q main
git remote set-head origin main

# A second clone moves the remote on, so the fetch below leaves main and shared behind.
git clone -q "$root/origin.git" "$root/other"
cd "$root/other"
git commit -q --allow-empty -m two
git push -q origin main
git switch -q -c feature/remote-only
git commit -q --allow-empty -m remote
git push -q origin feature/remote-only
git switch -q shared
git commit -q --allow-empty -m ahead
git push -q origin shared
rm -rf "$root/other"

cd "$root/repo"
git fetch -q
touch untracked.txt
git status -sb
git branch -a
