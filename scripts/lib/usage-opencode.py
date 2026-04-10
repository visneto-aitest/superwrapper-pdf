#!/usr/bin/env python3
"""
usage-opencode.py - Token usage report for OpenCode CLI
Reads from ~/.local/share/opencode/opencode.db (SQLite).
"""

import sqlite3
import json
import os
import sys
import glob
from datetime import datetime, timedelta

OPENCODE_DB = os.path.expanduser("~/.local/share/opencode/opencode.db")
OPENCODE_SESSION_DIR = os.path.expanduser("~/.local/share/opencode/sessions")

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


def parse_db(db_path, max_sessions=200, days_ago=None):
    if not os.path.isfile(db_path):
        return []
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cutoff = cutoff_ms(days_ago)
    where = "WHERE s.time_created >= ?" if cutoff else ""
    params = (cutoff,) if cutoff else ()
    sessions = conn.execute(
        f"""SELECT s.id, s.title, s.directory, s.time_created, s.time_updated,
                   p.name as project_name, p.worktree
            FROM session s
            LEFT JOIN project p ON s.project_id = p.id
            {where}
            ORDER BY s.time_created DESC
            LIMIT ?""",
        (*params, max_sessions),
    ).fetchall()

    results = []
    for sess in sessions:
        sid = sess["id"]
        directory = sess["directory"] or ""
        project = (sess["project_name"] or sess["worktree"]
                   or (os.path.basename(directory) if directory else "unknown"))
        total_input = total_output = total_cache_read = total_cache_write = total_reasoning = total_cost = 0
        model = "unknown"
        msg_count = 0
        messages = conn.execute(
            "SELECT data FROM message WHERE session_id = ? ORDER BY time_created", (sid,)
        ).fetchall()
        for msg_row in messages:
            try:
                data = json.loads(msg_row[0])
            except (json.JSONDecodeError, TypeError):
                continue
            msg_count += 1
            m = data.get("model")
            if isinstance(m, str):
                model = m
            if "tokens" in data:
                t = data["tokens"]
                total_input += t.get("input", 0)
                total_output += t.get("output", 0)
                total_reasoning += t.get("reasoning", 0)
                cache = t.get("cache", {})
                total_cache_read += cache.get("read", 0)
                total_cache_write += cache.get("write", 0)
            total_cost += data.get("cost", 0)
        total_all = total_input + total_output + total_cache_read + total_cache_write
        if total_all == 0 and total_cost == 0:
            continue
        results.append({
            "date": sess["time_created"], "project": project, "session": sess["title"],
            "model": model, "input": total_input, "output": total_output,
            "cache_read": total_cache_read, "cache_write": total_cache_write,
            "reasoning": total_reasoning, "cost": total_cost,
            "duration_ms": sess["time_updated"] - sess["time_created"],
            "messages": msg_count,
        })
    conn.close()
    return results


def parse_json_sessions(session_dir, max_sessions=50, days_ago=None):
    if not os.path.isdir(session_dir):
        return []
    files = sorted(glob.glob(os.path.join(session_dir, "*.json")),
                   key=os.path.getmtime, reverse=True)[:max_sessions]
    cutoff = cutoff_ms(days_ago) if days_ago is not None else 0
    results = []
    for sf in files:
        try:
            data = json.load(open(sf))
        except (json.JSONDecodeError, IOError):
            continue
        usage = data.get("usage", {})
        if not usage:
            continue
        ts = data.get("timestamp", data.get("created_at", ""))
        if isinstance(ts, str):
            try:
                ts_ms = int(datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() * 1000)
            except (ValueError, TypeError):
                ts_ms = int(os.path.getmtime(sf) * 1000)
        elif isinstance(ts, (int, float)):
            ts_ms = int(ts)
        else:
            ts_ms = int(os.path.getmtime(sf) * 1000)
        if cutoff and ts_ms < cutoff:
            continue
        cost = usage.get("cost_microdollars", usage.get("cost", 0))
        if 0 < cost < 1000:
            cost = cost * 1_000_000
        total = usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
        if total == 0 and cost == 0:
            continue
        results.append({
            "date": ts_ms, "session": os.path.basename(sf), "model": data.get("model", "unknown"),
            "input": usage.get("input_tokens", 0), "output": usage.get("output_tokens", 0),
            "cache_read": usage.get("cache_read_tokens", usage.get("cache_hit_tokens", 0)),
            "cache_write": usage.get("cache_write_tokens", 0), "reasoning": 0, "cost": cost,
            "messages": 1,
        })
    return results


def fmt(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def fmt_date(ms):
    try:
        return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError, OverflowError):
        return "unknown"


def show_summary(data, output_json=False):
    total_input = sum(s["input"] for s in data)
    total_output = sum(s["output"] for s in data)
    total_cr = sum(s["cache_read"] for s in data)
    total_cw = sum(s["cache_write"] for s in data)
    total_reasoning = sum(s["reasoning"] for s in data)
    total_cost = sum(s["cost"] for s in data)
    total_all = total_input + total_output + total_cr + total_cw
    cache_hit_rate = f"{(total_cr / max(total_all, 1) * 100):.1f}%"
    if output_json:
        print(json.dumps({
            "tool": "opencode", "sessions": len(data),
            "input_tokens": total_input, "output_tokens": total_output,
            "cache_read": total_cr, "cache_write": total_cw,
            "reasoning": total_reasoning, "total_tokens": total_all,
            "cache_hit_rate": cache_hit_rate,
            "estimated_cost_usd": round(total_cost / 1_000_000, 4),
        }, indent=2))
    else:
        print(f"  OpenCode Usage Summary ({len(data)} sessions):")
        print("  " + "\u2500" * 62)
        print("  \u2502  Input:         {:>12s} tokens                      \u2502".format(fmt(total_input)))
        print("  \u2502  Output:        {:>12s} tokens                      \u2502".format(fmt(total_output)))
        print("  \u2502  Cache Read:    {:>12s} tokens                      \u2502".format(fmt(total_cr)))
        print("  \u2502  Cache Write:   {:>12s} tokens                      \u2502".format(fmt(total_cw)))
        print("  \u2502  Reasoning:     {:>12s} tokens                      \u2502".format(fmt(total_reasoning)))
        print("  \u2502  Cache Hit Rate: {:>11s}                            \u2502".format(cache_hit_rate))
        print("  \u2502  Est. Cost:     ${:.4f}                          \u2502".format(total_cost / 1_000_000))
        print("  " + "\u2500" * 62)


def show_by_range(output_json=False):
    ranges = [("today", 0), ("week", 7), ("month", 30), ("6months", 180), ("all", None)]
    results = []
    for label, days in ranges:
        data = parse_db(OPENCODE_DB, max_sessions=10000, days_ago=days)
        if not data:
            data = parse_json_sessions(OPENCODE_SESSION_DIR, max_sessions=10000, days_ago=days)
        total_input = sum(s["input"] for s in data)
        total_output = sum(s["output"] for s in data)
        total_cr = sum(s["cache_read"] for s in data)
        total_cw = sum(s["cache_write"] for s in data)
        total_reasoning = sum(s["reasoning"] for s in data)
        total_cost = sum(s["cost"] for s in data)
        results.append({
            "range": label, "range_label": RANGE_LABELS[label],
            "sessions": len(data), "input": total_input, "output": total_output,
            "cache_read": total_cr, "cache_write": total_cw,
            "reasoning": total_reasoning,
            "total_tokens": total_input + total_output + total_cr + total_cw,
            "cost_usd": round(total_cost / 1_000_000, 4),
        })
    if output_json:
        print(json.dumps(results, indent=2))
        return
    print("  OpenCode Usage by Time Period:")
    print("  {:<18s} {:>8s} {:>10s} {:>10s} {:>10s} {:>10s} {:>10s}".format(
        "Period", "Sessions", "Input", "Output", "Cache", "Reasoning", "Est. Cost"))
    print("  " + "\u2500" * 18 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10)
    for r in results:
        print("  {:<18s} {:>8d} {:>10s} {:>10s} {:>10s} {:>10s} ${:>9.4f}".format(
            r["range_label"], r["sessions"], fmt(r["input"]), fmt(r["output"]),
            fmt(r["cache_read"] + r["cache_write"]), fmt(r["reasoning"]), r["cost_usd"]))


def show_sessions(data, output_json=False):
    if output_json:
        print(json.dumps(data, indent=2))
        return
    if not data:
        print("  No OpenCode sessions found.")
        return
    print("  OpenCode Sessions (last {}):".format(len(data)))
    print("  {:<18s} {:<22s} {:<32s} {:<30s} {:>7s} {:>7s} {:>7s} {:>9s}".format(
        "Date", "Project", "Session", "Model", "Input", "Output", "Cache", "Cost"))
    print("  " + "\u2500" * 18 + " " + "\u2500" * 22 + " " + "\u2500" * 32 + " " + "\u2500" * 30 + " " + "\u2500" * 7 + " " + "\u2500" * 7 + " " + "\u2500" * 7 + " " + "\u2500" * 9)
    for s in data:
        date = fmt_date(s["date"])[:17]
        print("  {:<18s} {:<22s} {:<32s} {:<30s} {:>7s} {:>7s} {:>7s} {:>9s}".format(
            date, s["project"][:21], s["session"][:31], s["model"][:29],
            fmt(s["input"]), fmt(s["output"]),
            fmt(s["cache_read"] + s["cache_write"]),
            "${:.4f}".format(s["cost"] / 1_000_000)))


def show_projects(data, output_json=False):
    projects = {}
    for s in data:
        p = s["project"]
        if p not in projects:
            projects[p] = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "cost": 0, "sessions": 0}
        projects[p]["input"] += s["input"]
        projects[p]["output"] += s["output"]
        projects[p]["cache_read"] += s["cache_read"]
        projects[p]["cache_write"] += s["cache_write"]
        projects[p]["cost"] += s["cost"]
        projects[p]["sessions"] += 1
    if output_json:
        print(json.dumps(projects, indent=2))
        return
    sorted_p = sorted(projects.items(), key=lambda x: x[1]["input"] + x[1]["output"], reverse=True)
    print("  OpenCode Usage by Project:")
    print("  {:<30s} {:>9s} {:>8s} {:>8s} {:>8s} {:>10s}".format(
        "Project", "Sessions", "Input", "Output", "Cache", "Cost"))
    print("  " + "\u2500" * 30 + " " + "\u2500" * 9 + " " + "\u2500" * 8 + " " + "\u2500" * 8 + " " + "\u2500" * 8 + " " + "\u2500" * 10)
    for name, p in sorted_p:
        print("  {:<30s} {:>9d} {:>8s} {:>8s} {:>8s} ${:>9.4f}".format(
            name[:29], p["sessions"], fmt(p["input"]), fmt(p["output"]),
            fmt(p["cache_read"] + p["cache_write"]), p["cost"] / 1_000_000))


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
        data = parse_db(OPENCODE_DB, max_sessions if action == "sessions" else 200, days_ago=days_ago)
        if not data:
            data = parse_json_sessions(OPENCODE_SESSION_DIR, max_sessions, days_ago=days_ago)
        if action == "summary":
            show_summary(data, output_json)
        elif action == "sessions":
            show_sessions(data, output_json)
        elif action == "projects":
            show_projects(data, output_json)


if __name__ == "__main__":
    main()
