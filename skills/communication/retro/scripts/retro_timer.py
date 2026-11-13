#!/usr/bin/env python3
"""Claude Code hook: trigger a retro every RETRO_INTERVAL_HOURS of session time.

Wire it to three events (user settings):
  SessionStart      -> picks up retros left pending by sessions that ended early
  UserPromptSubmit  -> starts the clock at the first prompt; when the interval has
                       passed, injects an instruction to run the `retro` skill
  SessionEnd        -> if the un-reviewed stretch is long enough, leaves a pending
                       marker for the next session in the same directory

State lives in ~/.claude/retro-state/. Never blocks: any error exits 0 silently.
Env: RETRO_INTERVAL_HOURS (default 4), RETRO_MIN_PROMPTS (default 8),
     RETRO_MIN_MINUTES (default 30), RETRO_DISABLE=1 to turn it off.
"""
import json
import os
import sys
import time
from datetime import datetime, timezone

STATE_DIR = os.path.expanduser("~/.claude/retro-state")
PENDING_DIR = os.path.join(STATE_DIR, "pending")
INTERVAL = float(os.environ.get("RETRO_INTERVAL_HOURS", "4")) * 3600
MIN_PROMPTS = int(os.environ.get("RETRO_MIN_PROMPTS", "8"))
MIN_SECONDS = float(os.environ.get("RETRO_MIN_MINUTES", "30")) * 60


def iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def local(ts):
    return datetime.fromtimestamp(ts).strftime("%H:%M")


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def emit(event, context, user_note=None):
    out = {"hookSpecificOutput": {"hookEventName": event, "additionalContext": context}}
    if user_note:
        out["systemMessage"] = user_note
    print(json.dumps(out))


def instruction(transcript, since_ts, until_ts, why):
    return (
        f"[retro] {why} Do this AFTER fully answering the user's current message, "
        f"as the last part of this reply: run the `retro` skill on transcript {transcript} "
        f"for the window {iso(since_ts)} .. {iso(until_ts)} "
        f"(python3 ~/.claude/skills/retro/scripts/extract_transcript.py \"{transcript}\" "
        f"--since {iso(since_ts)} --until {iso(until_ts)}). Keep the retro report short."
    )


def on_prompt(p):
    sid, now = p.get("session_id"), time.time()
    path = os.path.join(STATE_DIR, f"{sid}.json")
    st = load(path, None)
    if st is None:  # first prompt of the session starts the clock
        st = {"start": now, "mark": now, "prompts_since_mark": 0,
              "transcript": p.get("transcript_path"), "cwd": p.get("cwd")}
    st["prompts_since_mark"] += 1
    st["transcript"] = p.get("transcript_path") or st.get("transcript")
    if now - st["mark"] >= INTERVAL:
        emit("UserPromptSubmit",
             instruction(st["transcript"], st["mark"], now,
                         f"{(now - st['mark']) / 3600:.1f} h since the last retro."),
             f"Retro tự động ({local(st['mark'])}–{local(now)}) sẽ chạy ở cuối câu trả lời này.")
        st["mark"], st["prompts_since_mark"] = now, 0
    save(path, st)


def on_end(p):
    sid, now = p.get("session_id"), time.time()
    path = os.path.join(STATE_DIR, f"{sid}.json")
    st = load(path, None)
    if st is None:
        return
    if st["prompts_since_mark"] >= MIN_PROMPTS and now - st["mark"] >= MIN_SECONDS:
        save(os.path.join(PENDING_DIR, f"{sid}.json"),
             {"transcript": st.get("transcript") or p.get("transcript_path"),
              "since": st["mark"], "until": now, "cwd": st.get("cwd") or p.get("cwd"),
              "prompts": st["prompts_since_mark"]})
    try:
        os.remove(path)
    except OSError:
        pass


def on_start(p):
    cwd = p.get("cwd")
    if not os.path.isdir(PENDING_DIR):
        return
    found = []
    for name in sorted(os.listdir(PENDING_DIR)):
        mpath = os.path.join(PENDING_DIR, name)
        m = load(mpath, None)
        if not m:
            continue
        if m.get("cwd") == cwd and m.get("transcript") and os.path.exists(m["transcript"]):
            found.append(m)
            os.remove(mpath)
        elif time.time() - m.get("until", 0) > 30 * 86400:  # stale markers expire
            os.remove(mpath)
    if found:
        parts = [instruction(m["transcript"], m["since"], m["until"],
                             f"A previous session here ended with {m['prompts']} un-reviewed prompts.")
                 for m in found]
        emit("SessionStart", " ".join(parts),
             f"Có {len(found)} phiên trước chưa retro — sẽ chạy sau câu trả lời đầu tiên.")


def main():
    if os.environ.get("RETRO_DISABLE") == "1":
        return
    p = json.load(sys.stdin)
    ev = p.get("hook_event_name") or (sys.argv[1] if len(sys.argv) > 1 else "")
    {"UserPromptSubmit": on_prompt, "SessionEnd": on_end, "SessionStart": on_start}.get(ev, lambda _: None)(p)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
