#!/usr/bin/env python3
"""Compact a Claude Code transcript (.jsonl) for a retro: user prompts in full,
assistant prose shortened, tool calls as one-line markers, tool output dropped.

  extract_transcript.py <transcript.jsonl> [--since ISO] [--until ISO] [--max-assistant N]
"""
import argparse
import json
import re
import sys

REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
NOISE = re.compile(r"<(local-command-stdout|command-message|command-name|command-args)>.*?</\1>", re.S)


def clean(text):
    text = REMINDER.sub("", text)
    text = NOISE.sub("", text)
    return text.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    ap.add_argument("--since", default="")
    ap.add_argument("--until", default="")
    ap.add_argument("--max-assistant", type=int, default=700)
    a = ap.parse_args()

    out = []
    with open(a.transcript, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            t, ts = d.get("type"), d.get("timestamp", "")
            if t not in ("user", "assistant") or d.get("isSidechain"):
                continue
            if (a.since and ts < a.since) or (a.until and ts > a.until):
                continue
            content = (d.get("message") or {}).get("content")
            hhmm = ts[11:16]
            if t == "user":
                if isinstance(content, str):
                    text = clean(content)
                elif isinstance(content, list):  # skip tool results, keep typed text
                    text = clean(" ".join(b.get("text", "") for b in content
                                          if isinstance(b, dict) and b.get("type") == "text"))
                else:
                    text = ""
                if text:
                    out.append(f"\n### USER {hhmm}\n{text}")
            else:
                for b in content or []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text" and b.get("text", "").strip():
                        s = b["text"].strip()
                        if len(s) > a.max_assistant:
                            s = s[: a.max_assistant] + " …"
                        out.append(f"ASSISTANT {hhmm}: {s}")
                    elif b.get("type") == "tool_use":
                        inp = b.get("input") or {}
                        hint = inp.get("description") or inp.get("file_path") or inp.get("skill") or ""
                        out.append(f"  [tool {b.get('name')}: {str(hint)[:80]}]")
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
