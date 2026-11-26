"""Seeds three wain-serve homes for RedesignTests and BotSheetTests, and the
repos they attach.

    python3 scripts/redesign_seed.py <studio> <empty> <bots> <repos>   # prints the three tokens
    WAIN_HOME=<studio> wain-serve --port <p1> &
    WAIN_HOME=<empty>  wain-serve --port <p2> &
    WAIN_HOME=<bots>   wain-serve --port <p3> &
    # Real sessions, started from drafts so each runs on its own stance:
    WAIN_HOME=<studio> python3 scripts/redesign_seed.py live tighten   # before RedesignTests
    WAIN_HOME=<studio> python3 scripts/redesign_seed.py live allow question   # before testAnswerInline

studio: tasks in two projects, one settled, a draft, `thinking-orbs`, a git
repo on main with a `fix-reconnect` branch and two uncommitted files, and
`notes`, a project with no task. `live tighten` adds "Tighten session row
spacing", a real Haiku session on Bypass permissions, so a reply can run a
shell command; seeded logs have no conversation behind them to resume. `live
allow question` adds two sessions on Ask every time, one held on a shell
command's permission card and one on an AskUserQuestion card; neither card is
ever logged, so both need a live turn. testOfflineBanners has the harness stop
studio, so it runs last. empty: the same two projects and one task settled
today. bots: a bot, Ops, whose chat runs longer than the screen.

Homes and repos want short paths without a symlink in them, such as under
`~/.wain-worktrees`: the orchestration socket lives in the home, and the server
canonicalizes paths, so a bot's path through `/tmp` matches no chat.
"""
import json, os, shutil, subprocess, sys, uuid
from datetime import datetime, timedelta, timezone

now = datetime.now(timezone.utc)
stamp = lambda d: d.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def write_log(home, sid, turns, start):
    with open(f"{home}/sessions/{sid}.jsonl", "w") as f:
        seq = 0
        for i, (prompt, reply) in enumerate(turns):
            for p in ({"type": "user_message", "text": prompt, "images": [], "issues": [], "baseline": None,
                       "queued": False, "from": None, "cwd": None},
                      {"type": "assistant_text", "block": {"messageId": f"msg_{i}", "index": 0}, "text": reply},
                      {"type": "turn_completed", "status": "success", "stopReason": "end_turn", "finalText": reply}):
                # Compact, as serde writes it: the server finds lines by byte needles.
                f.write(json.dumps({"id": str(uuid.uuid4()), "sessionId": sid, "harness": "claude_code", "seq": seq,
                                    "ts": stamp(start + timedelta(minutes=i, seconds=seq)), "turnId": None,
                                    "subagent": None, "payload": p}, separators=(",", ":")) + "\n")
                seq += 1


def session(home, cwd, title, turns, ago, status="idle", archived=False):
    sid = str(uuid.uuid4())
    modified = now - ago
    write_log(home, sid, turns, modified - timedelta(minutes=len(turns)))
    return {"sessionId": sid, "harness": "claude_code", "cwd": cwd, "projectPath": cwd, "branch": "main",
            "worktreeName": None, "worktreeRemoved": False, "title": title, "titleLocked": True,
            "model": "haiku", "effort": "low", "permissionMode": "auto", "fast": False, "status": status,
            "forkFrom": None, "threadId": None, "issues": [], "parentSessionId": None,
            "created": stamp(modified - timedelta(hours=1)), "modified": stamp(modified), "archived": archived,
            "pinned": False, "hidden": False, "aside": False, "continueOff": False}


def make_home(home, token, projects=(), drafts=()):
    """An empty home; its sessions are written in after, since each one's log goes in the home."""
    shutil.rmtree(home, ignore_errors=True)
    os.makedirs(f"{home}/sessions")
    open(f"{home}/serve-token", "w").write(token)
    os.chmod(f"{home}/serve-token", 0o600)
    json.dump([{"path": p, "name": os.path.basename(p), "lastSelected": stamp(now - timedelta(minutes=i))}
               for i, p in enumerate(projects)], open(f"{home}/projects.json", "w"))
    json.dump(list(drafts), open(f"{home}/drafts.json", "w"))


def git(cwd, *args):
    subprocess.run(["git", "-c", "user.name=Wain Test", "-c", "user.email=test@example.com", *args],
                   cwd=cwd, check=True, capture_output=True)


def draft(prompt, project, mode):
    return {"id": str(uuid.uuid4()), "prompt": prompt, "projectPath": project, "harness": "claude_code",
            "model": "haiku", "effort": None, "permissionMode": mode, "fast": False, "useWorktree": False,
            "created": stamp(datetime.now(timezone.utc))}


LIVE = {
    "tighten": ("Reply with the single word: ready.", "bypassPermissions"),
    "allow": ("Run the shell command `touch allowed.txt` in this folder, then reply with the single word: done.", "manual"),
    "question": ("Call the AskUserQuestion tool once, with two questions. First: \"Which phone should I test on?\" "
                 "with the options \"iPhone SE\" and \"iPhone 17\". Second: \"Should I post screenshots on the PR?\" "
                 "with the options \"Yes\" and \"No\". Once answered, reply with the single word: thanks.", "manual"),
}

if sys.argv[1:2] == ["live"]:
    # Started through the server's own CLI, so each is a real conversation on its draft's stance.
    home = os.environ["WAIN_HOME"]
    project = next(p["path"] for p in json.load(open(f"{home}/projects.json")) if p["name"] == "wain-ios")
    held = json.load(open(f"{home}/drafts.json"))
    for name in sys.argv[2:]:
        prompt, mode = LIVE[name]
        d = draft(prompt, project, mode)
        json.dump(held + [d], open(f"{home}/drafts.json", "w"))
        out = subprocess.run(["wain", "draft", "start", d["id"]], capture_output=True, text=True, check=True).stdout
        held = json.load(open(f"{home}/drafts.json"))
        if name == "tighten":
            sid = next(w for w in out.split() if len(w) == 36 and w.count("-") == 4)
            subprocess.run(["wain", "session", "rename", sid, "Tighten session row spacing"], check=True)
        print(name, out.strip())
    sys.exit()

studio, empty, bots_home, repos = sys.argv[1:5]
shutil.rmtree(repos, ignore_errors=True)
orbs, ios = f"{repos}/thinking-orbs", f"{repos}/wain-ios"
for repo, files in ((orbs, {"README.md": "# Thinking Orbs\n", "Orb.swift": "struct Orb {}\n"}),
                    (ios, {"README.md": "# Wain for iPhone\n"})):
    os.makedirs(repo)
    git(repo, "init", "-q", "-b", "main")
    for name, text in files.items():
        open(f"{repo}/{name}", "w").write(text)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "First")
git(orbs, "checkout", "-q", "-b", "fix-reconnect")
open(f"{orbs}/Reconnect.swift", "w").write("func reconnect() {}\n")
git(orbs, "add", "-A")
git(orbs, "commit", "-q", "-m", "Reconnect")
git(orbs, "checkout", "-q", "main")
# Uncommitted on main, and in no file the branch touches, so Bring carries them across.
open(f"{orbs}/README.md", "a").write("\nSpinning orbs for a working state.\n")
open(f"{orbs}/notes.txt", "w").write("todo: backoff\n")
projects = (ios, orbs)
# A third on studio with no task in it, for "Nothing in notes": the strip needs a task elsewhere to show.
notes = f"{repos}/notes"
os.makedirs(notes)

tokens = {"studio": "0825" * 16, "empty": "0826" * 16, "bots": "1093" * 16}
make_home(studio, tokens["studio"], projects + (notes,), [draft("Add retry with backoff to the upload client", orbs, "auto")])
index = [
    session(studio, ios, "Check the Xcode version", [("Which Xcode is installed?", "Xcode 26.2, build 17C52.")],
            timedelta(minutes=4), status="completed"),
    session(studio, orbs, "Fix flaky reconnect test",
            [("The reconnect test fails one run in ten. Find out why.", "It races the backoff timer."),
             ("Fix it.", "Fixed: the test now waits on the reconnect event instead of a sleep.")], timedelta(minutes=25)),
    session(studio, ios, "Port tools.ts labels to Swift", [("Port the tool labels.", "Ported all 31 labels.")],
            timedelta(hours=1), archived=True),
]
json.dump(index, open(f"{studio}/sessions/index.json", "w"))

make_home(empty, tokens["empty"], projects)
json.dump([session(empty, ios, "Ship the release notes", [("Write the release notes.", "Written.")],
                   timedelta(minutes=5), archived=True)], open(f"{empty}/sessions/index.json", "w"))

make_home(bots_home, tokens["bots"])
bid = str(uuid.uuid4())
bot_path = f"{bots_home}/bots/{bid}"
os.makedirs(f"{bot_path}/memory")
open(f"{bot_path}/AGENTS.md", "w").write("# Ops\n")
json.dump([{"id": bid, "name": "Ops", "path": bot_path, "created": stamp(now - timedelta(days=2)),
            "avatar": {"shape": "cloud", "hue": 185.0}}], open(f"{bots_home}/bots.json", "w"))
turns = [(f"Anything on fire, check {i}?", f"Check {i}: nothing on fire. The nightly build passed and no task waits on you.")
         for i in range(40)]
json.dump([session(bots_home, bot_path, "Ops", turns, timedelta(minutes=10))], open(f"{bots_home}/sessions/index.json", "w"))

print(json.dumps(tokens))
