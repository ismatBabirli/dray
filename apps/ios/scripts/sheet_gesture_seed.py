"""Seeds a wain-serve home for SheetGestureTests (#1415): the bot Ops, whose chat ends
on a code block wider than the screen starting `let WIDE`, and one task under it.

    python3 scripts/sheet_gesture_seed.py           # prints the token
    WAIN_HOME=/private/tmp/wain-sheet-gesture wain-serve --port <port> &

Under /private/tmp, not /tmp: the server canonicalizes paths, and a bot's path
that differs from its chat's cwd by that symlink matches no bot.
"""
import json, os, shutil, sys, uuid
from datetime import datetime, timedelta, timezone

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/wain-sheet-gesture"
TOKEN = "1415" * 16
now = datetime.now(timezone.utc)
stamp = lambda d: d.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def session(cwd, title, turns, hidden=False, parent=None):
    sid, at, seq = str(uuid.uuid4()), now - timedelta(hours=1), 0
    with open(f"{ROOT}/sessions/{sid}.jsonl", "w") as f:
        for i, (ask, answer) in enumerate(turns):
            for p in [{"type": "user_message", "text": ask, "images": [], "issues": [], "baseline": None,
                       "queued": False, "from": None, "cwd": None},
                      {"type": "assistant_text", "block": {"messageId": f"msg_{i}", "index": 0}, "text": answer},
                      {"type": "turn_completed", "status": "success", "stopReason": "end_turn", "finalText": answer}]:
                # Compact, as serde writes it: the server finds lines by byte needles like `"type":"user_message"`.
                f.write(json.dumps({"id": str(uuid.uuid4()), "sessionId": sid, "harness": "claude_code", "seq": seq,
                                    "ts": stamp(at + timedelta(seconds=seq)), "turnId": None, "subagent": None,
                                    "payload": p}, separators=(",", ":")) + "\n")
                seq += 1
    return {"sessionId": sid, "harness": "claude_code", "cwd": cwd, "projectPath": cwd, "branch": "main",
            "worktreeName": None, "worktreeRemoved": False, "title": title, "titleLocked": True,
            "model": "haiku", "effort": "low", "permissionMode": "auto", "fast": False, "status": "idle",
            "forkFrom": None, "threadId": None, "issues": [], "parentSessionId": parent,
            "created": stamp(at), "modified": stamp(at + timedelta(seconds=seq)), "archived": False,
            "pinned": False, "hidden": hidden, "aside": False, "continueOff": False}


shutil.rmtree(ROOT, ignore_errors=True)
proj = f"{ROOT}/proj"
os.makedirs(proj)
os.makedirs(f"{ROOT}/sessions")
bid = str(uuid.uuid4())
bot_path = f"{ROOT}/bots/{bid}"
os.makedirs(bot_path + "/memory")
open(bot_path + "/AGENTS.md", "w").write("# Ops\n")
bot = {"id": bid, "name": "Ops", "path": bot_path, "created": stamp(now - timedelta(days=2)),
       "avatar": {"shape": "cloud", "hue": 185.0}}

wide = ("let WIDE = [" + ", ".join(f'"column{i}"' for i in range(40)) + "]\n"
        + "\n".join(f"let row{i} = WIDE.map {{ $0 + \"{i}\" }}.joined(separator: \", \")" for i in range(6)))
# Tall enough to scroll, so a swipe up the right edge has a chat to move.
turns = [(f"Check {i}?", f"Check {i} is fine. " + "Nothing changed on the build since the last look. " * 4) for i in range(12)]
turns.append(("Show me the table code.", f"Here it is:\n\n```swift\n{wide}\n```"))
chat = session(bot_path, "Ops", turns)
task = session(proj, "Tidy the README", [("Tidy the README.", "Tidied the headings and cut the old install steps.")],
               hidden=True, parent=chat["sessionId"])
# An auto-continue a day off keeps the server's stall judge off the task (`stalls.rs`): two minutes
# idle, it would nudge the bot, whose chat no agent holds, and an error turn lands mid-test.
task["continueAt"] = stamp(now + timedelta(days=1))

open(f"{ROOT}/serve-token", "w").write(TOKEN)
os.chmod(f"{ROOT}/serve-token", 0o600)
json.dump([bot], open(f"{ROOT}/bots.json", "w"))
json.dump([chat, task], open(f"{ROOT}/sessions/index.json", "w"))
print(TOKEN)
