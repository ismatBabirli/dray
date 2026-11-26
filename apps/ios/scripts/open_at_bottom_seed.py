"""Fixture for OpenAtBottomTests: home A (bot Ops with tasks, bot Runner with no chat,
"Media check" and "Scroll check" tasks) and home B (one task under Ops' chat, for the shared machine).

    open_at_bottom_seed.py <home A> <home B>
"""
import json, os, shutil, struct, subprocess, sys, uuid, zlib
from datetime import datetime, timedelta, timezone

A, B = sys.argv[1], sys.argv[2]
now = datetime.now(timezone.utc)
stamp = lambda d: d.isoformat(timespec="milliseconds").replace("+00:00", "Z")
LONG = "It runs long enough to wrap over a few lines on a phone, which is the point of it. "


def png(w, h, rgb):
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    rows = b"".join(b"\0" + bytes(rgb) * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def media(home, sid):
    rec = f"{home}/browser/recordings/{sid}"
    os.makedirs(rec)
    open(f"{rec}/shot.png", "wb").write(png(900, 1600, (250, 204, 21)))
    subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=640x360:rate=30", "-t", "3",
                    "-pix_fmt", "yuv420p", f"{rec}/clip.mp4"], check=True)
    return rec


def session(home, cwd, title, turns, hidden=False, parent=None, sid=None, minutes_ago=30):
    sid = sid or str(uuid.uuid4())
    at, seq = now - timedelta(minutes=minutes_ago), 0
    with open(f"{home}/sessions/{sid}.jsonl", "w") as f:
        for i, (ask, answer) in enumerate(turns):
            for p in [{"type": "user_message", "text": ask, "images": [], "issues": [], "baseline": None,
                       "queued": False, "from": None, "cwd": None},
                      {"type": "assistant_text", "block": {"messageId": f"msg_{i}", "index": 0}, "text": answer},
                      {"type": "turn_completed", "status": "success", "stopReason": "end_turn", "finalText": answer}]:
                f.write(json.dumps({"id": str(uuid.uuid4()), "sessionId": sid, "harness": "claude_code", "seq": seq,
                                    "ts": stamp(at + timedelta(seconds=seq)), "turnId": None, "subagent": None,
                                    "payload": p}, separators=(",", ":")) + "\n")
                seq += 1
    item = {"sessionId": sid, "harness": "claude_code", "cwd": cwd, "projectPath": cwd, "branch": "main",
            "worktreeName": None, "worktreeRemoved": False, "title": title, "titleLocked": True,
            "model": "haiku", "effort": "low", "permissionMode": "auto", "fast": False, "status": "idle",
            "forkFrom": None, "threadId": None, "issues": [], "parentSessionId": parent,
            "created": stamp(at), "modified": stamp(at + timedelta(seconds=seq)), "archived": False,
            "pinned": False, "hidden": hidden, "aside": False, "continueOff": False}
    if parent:
        # Off the stall judge, whose nudge would run a turn in a chat no agent holds.
        item["continueAt"] = stamp(now + timedelta(days=1))
    return item


def bot(home, name, hue):
    bid = str(uuid.uuid4())
    path = f"{home}/bots/{bid}"
    os.makedirs(path + "/memory")
    open(path + "/AGENTS.md", "w").write(f"# {name}\n")
    return {"id": bid, "name": name, "path": path, "created": stamp(now - timedelta(days=2)),
            "avatar": {"shape": "cloud", "hue": hue}}


def tall(i, n=6):
    return "\n\n".join(f"Paragraph {j} of answer {i}. " + LONG * 3 for j in range(1, n + 1))


for h in (A, B):
    shutil.rmtree(h, ignore_errors=True)
    os.makedirs(f"{h}/sessions")
    os.makedirs(f"{h}/proj")

ops, runner = bot(A, "Ops", 185.0), bot(A, "Runner", 40.0)
chat_id = str(uuid.uuid4())
rec = media(A, chat_id)
turns = [(f"Check {i}?", tall(i, 2 if i % 3 else 4)) for i in range(30)]
turns[27] = ("Show me the board.", f"The board as it stands:\n\n{rec}/shot.png\n\nAnd the run:\n\n{rec}/clip.mp4")
chat = session(A, ops["path"], "Ops", turns, sid=chat_id)

media_id = str(uuid.uuid4())
rec = media(A, media_id)
turns = [(f"Step {i}?", tall(i)) for i in range(10)]
turns[8] = ("Screenshot it.", f"Here:\n\n{rec}/shot.png")
# Ends as a late turn does: a picture last, whose button is an element before it loads; a video's placeholder is none.
turns[9] = ("Record it.", f"{tall(9, 3)}\n\nScreenshot: {rec}/shot.png\n\nRecording: {rec}/clip.mp4\n\nThat is the run, end to end.")
items = [
    chat,
    session(A, f"{A}/proj", "Fix login redirect", [("Fix the login redirect.", tall(1)), ("Go on.", tall(2))],
            hidden=True, parent=chat_id, minutes_ago=20),
    session(A, f"{A}/proj", "Bump deps", [("Bump the deps.", tall(3, 2))], hidden=True, parent=chat_id, minutes_ago=25),
    session(A, f"{A}/proj", "Media check", turns, sid=media_id, minutes_ago=15),
    session(A, f"{A}/proj", "Scroll check", [(f"Tall {i}?", tall(i, 12)) for i in range(12)], minutes_ago=10),
]
json.dump([ops, runner], open(f"{A}/bots.json", "w"))
json.dump(items, open(f"{A}/sessions/index.json", "w"))
json.dump([session(B, f"{B}/proj", "Sandbox task", [("Check the sandbox.", tall(4, 3))], hidden=True, parent=chat_id)],
          open(f"{B}/sessions/index.json", "w"))
for h, token in ((A, "b0a1" * 16), (B, "b0b2" * 16)):
    open(f"{h}/serve-token", "w").write(token)
    os.chmod(f"{h}/serve-token", 0o600)
print(chat_id)
