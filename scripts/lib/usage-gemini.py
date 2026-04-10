#!/usr/bin/env python3
"""
usage-gemini.py - Token usage report for Gemini CLI
Reads from ~/.gemini/tmp/<project_hash>/chats/*.json.
"""

import json
import os
import sys
import glob
from datetime import datetime, timedelta

GEMINI_TMP_DIR = os.path.expanduser("~/.gemini/tmp")

TIME_RANGES = {"all": None, "6months": 180, "month": 30, "week": 7, "today": 0}
RANGE_LABELS = {
    "all": "All time", "6months": "Last 6 months", "month": "Last 30 days",
    "week": "Last 7 days", "today": "Today",
}


def cutoff_ms(days_ago=None):
    if days_ago is None:
        return 0
    dt = datetime.now() - timedelta(days=days_ago)
    return int(dt.replace(hour=0, minute=0, second=0, microsecond=0).timestamp() * 1000)


def parse_sessions(max_sessions=200, days_ago=None):
    if not os.path.isdir(GEMINI_TMP_DIR):
        return []
    cutoff = cutoff_ms(days_ago) if days_ago is not None else 0
    results = []
    for project_hash in os.listdir(GEMINI_TMP_DIR):
        chats_dir = os.path.join(GEMINI_TMP_DIR, project_hash, "chats")
        if not os.path.isdir(chats_dir):
            continue
        chat_files = sorted(glob.glob(os.path.join(chats_dir, "*.json")),
                            key=os.path.getmtime, reverse=True)
        for cf in chat_files:
            try:
                data = json.load(open(cf))
            except (json.JSONDecodeError, IOError):
                continue
            messages = data.get("messages", [])
            if not messages:
                continue
            total_input = total_output = total_cached = total_thoughts = total_tool = total_tokens = session_count = 0
            for msg in messages:
                tokens = msg.get("tokens", {})
                if not tokens:
                    continue
                session_count += 1
                total_input += tokens.get("input", 0)
                total_output += tokens.get("output", 0)
                total_cached += tokens.get("cached", 0)
                total_thoughts += tokens.get("thoughts", 0)
                total_tool += tokens.get("tool", 0)
                total_tokens += tokens.get("total", 0)
            if session_count == 0:
                continue
            ts = data.get("lastUpdated", data.get("startTime", ""))
            if isinstance(ts, str):
                try:
                    ts_ms = int(datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() * 1000)
                except (ValueError, TypeError):
                    ts_ms = int(os.path.getmtime(cf) * 1000)
            elif isinstance(ts, (int, float)):
                ts_ms = int(ts)
            else:
                ts_ms = int(os.path.getmtime(cf) * 1000)
            if cutoff and ts_ms < cutoff:
                continue
            results.append({
                "project": project_hash[:16],
                "session": data.get("sessionId", os.path.basename(cf)),
                "file": os.path.basename(cf),
                "date": ts_ms,
                "input": total_input, "output": total_output,
                "cached": total_cached, "thoughts": total_thoughts,
                "tool": total_tool, "total_tokens": total_tokens,
                "turns": session_count,
            })
    results.sort(key=lambda x: x["date"], reverse=True)
    return results[:max_sessions]


def fmt(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def show_summary(data, output_json=False):
    total_input = sum(s["input"] for s in data)
    total_output = sum(s["output"] for s in data)
    total_cached = sum(s["cached"] for s in data)
    total_thoughts = sum(s["thoughts"] for s in data)
    total_tool = sum(s["tool"] for s in data)
    total_tokens = sum(s["total_tokens"] for s in data)
    total_turns = sum(s["turns"] for s in data)
    if output_json:
        print(json.dumps({
            "tool": "gemini", "sessions": len(data), "total_turns": total_turns,
            "input_tokens": total_input, "output_tokens": total_output,
            "cached_tokens": total_cached, "thought_tokens": total_thoughts,
            "tool_tokens": total_tool, "total_tokens": total_tokens,
        }, indent=2))
    else:
        print(f"  Gemini CLI Usage Summary ({len(data)} sessions, {total_turns} turns):")
        print("  " + "\u2500" * 62)
        print("  \u2502  Input:         {:>12s} tokens                      \u2502".format(fmt(total_input)))
        print("  \u2502  Output:        {:>12s} tokens                      \u2502".format(fmt(total_output)))
        print("  \u2502  Cached:        {:>12s} tokens                      \u2502".format(fmt(total_cached)))
        print("  \u2502  Thoughts:      {:>12s} tokens                      \u2502".format(fmt(total_thoughts)))
        print("  \u2502  Total:         {:>12s} tokens                      \u2502".format(fmt(total_tokens)))
        print("  " + "\u2500" * 62)


def show_by_range(output_json=False):
    ranges = [("today", 0), ("week", 7), ("month", 30), ("6months", 180), ("all", None)]
    results = []
    for label, days in ranges:
        data = parse_sessions(max_sessions=10000, days_ago=days)
        total_input = sum(s["input"] for s in data)
        total_output = sum(s["output"] for s in data)
        total_cached = sum(s["cached"] for s in data)
        total_thoughts = sum(s["thoughts"] for s in data)
        total_tokens = sum(s["total_tokens"] for s in data)
        total_turns = sum(s["turns"] for s in data)
        results.append({
            "range": label, "range_label": RANGE_LABELS[label],
            "sessions": len(data), "turns": total_turns,
            "input": total_input, "output": total_output,
            "cached": total_cached, "thoughts": total_thoughts,
            "total_tokens": total_tokens,
        })
    if output_json:
        print(json.dumps(results, indent=2))
        return
    print("  Gemini CLI Usage by Time Period:")
    print("  {:<18s} {:>8s} {:>8s} {:>10s} {:>10s} {:>10s} {:>10s}".format(
        "Period", "Sessions", "Turns", "Input", "Output", "Cached", "Total"))
    print("  " + "\u2500" * 18 + " " + "\u2500" * 8 + " " + "\u2500" * 8 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10)
    for r in results:
        print("  {:<18s} {:>8d} {:>8d} {:>10s} {:>10s} {:>10s} {:>10s}".format(
            r["range_label"], r["sessions"], r["turns"],
            fmt(r["input"]), fmt(r["output"]),
            fmt(r["cached"]), fmt(r["total_tokens"])))


def show_sessions(data, output_json=False):
    if output_json:
        print(json.dumps(data, indent=2))
        return
    if not data:
        print("  No Gemini sessions found.")
        return
    print(f"  Gemini CLI Sessions (last {len(data)}):")
    print("  {:<22s} {:<18s} {:<45s} {:>7s} {:>7s} {:>7s} {:>6s}".format(
        "Start Time", "Project", "Session", "Input", "Output", "Cached", "Turns"))
    print("  " + "\u2500" * 22 + " " + "\u2500" * 18 + " " + "\u2500" * 45 + " " + "\u2500" * 7 + " " + "\u2500" * 7 + " " + "\u2500" * 7 + " " + "\u2500" * 6)
    for s in data:
        start = str(s["date"])[:21]
        try:
            start = datetime.fromtimestamp(int(s["date"]) / 1000).strftime("%Y-%m-%d %H:%M")[:17]
        except (ValueError, TypeError):
            pass
        print("  {:<22s} {:<18s} {:<45s} {:>7s} {:>7s} {:>7s} {:>6s}".format(
            start, s["project"][:17], s["session"][:44],
            fmt(s["input"]), fmt(s["output"]), fmt(s["cached"]), str(s["turns"])))


def show_projects(data, output_json=False):
    projects = {}
    for s in data:
        p = s["project"]
        if p not in projects:
            projects[p] = {"input": 0, "output": 0, "cached": 0, "thoughts": 0, "total_tokens": 0, "sessions": 0, "turns": 0}
        projects[p]["input"] += s["input"]
        projects[p]["output"] += s["output"]
        projects[p]["cached"] += s["cached"]
        projects[p]["thoughts"] += s["thoughts"]
        projects[p]["total_tokens"] += s["total_tokens"]
        projects[p]["sessions"] += 1
        projects[p]["turns"] += s["turns"]
    if output_json:
        print(json.dumps(projects, indent=2))
        return
    sorted_p = sorted(projects.items(), key=lambda x: x[1]["total_tokens"], reverse=True)
    print("  Gemini CLI Usage by Project:")
    print("  {:<30s} {:>9s} {:>7s} {:>8s} {:>8s} {:>8s} {:>8s}".format(
        "Project", "Sessions", "Turns", "Input", "Output", "Cached", "Total"))
    print("  " + "\u2500" * 30 + " " + "\u2500" * 9 + " " + "\u2500" * 7 + " " + "\u2500" * 8 + " " + "\u2500" * 8 + " " + "\u2500" * 8 + " " + "\u2500" * 8)
    for name, p in sorted_p:
        print("  {:<30s} {:>9d} {:>7d} {:>8s} {:>8s} {:>8s} {:>8s}".format(
            name[:29], p["sessions"], p["turns"],
            fmt(p["input"]), fmt(p["output"]), fmt(p["cached"]), fmt(p["total_tokens"])))


def main():
    action = "summary"
    max_sessions = 50
    output_json = False
    days_ago = None

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--summary":
            action = "summary"; i += 1
        elif a == "--by-range":
            action = "by-range"; i += 1
        elif a == "--sessions":
            action = "sessions"; i += 1
            if i < len(args) and args[i].isdigit():
                max_sessions = int(args[i]); i += 1
        elif a == "--projects":
            action = "projects"; i += 1
        elif a == "--range":
            i += 1
            if i < len(args) and args[i] in TIME_RANGES:
                days_ago = TIME_RANGES[args[i]]; i += 1
        elif a == "--json":
            output_json = True; i += 1
        else:
            i += 1

    if action == "by-range":
        show_by_range(output_json)
    else:
        data = parse_sessions(max_sessions if action == "sessions" else 200, days_ago=days_ago)
        if action == "summary":
            show_summary(data, output_json)
        elif action == "sessions":
            show_sessions(data, output_json)
        elif action == "projects":
            show_projects(data, output_json)


if __name__ == "__main__":
    main()
