#!/usr/bin/env python3
"""
usage-claude.py - Token usage report for Claude Code CLI
Reads from ~/.claude/stats-cache.json (primary) and ~/.claude/conversations/*.json.
"""

import json
import os
import sys
import glob
from datetime import datetime, timedelta

CLAUDE_STATS_CACHE = os.path.expanduser("~/.claude/stats-cache.json")
CLAUDE_CONVERSATIONS_DIR = os.path.expanduser("~/.claude/conversations")

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


def parse_stats_cache(days_ago=None):
    if not os.path.isfile(CLAUDE_STATS_CACHE):
        return []
    try:
        data = json.load(open(CLAUDE_STATS_CACHE))
    except (json.JSONDecodeError, IOError):
        return []
    cutoff = cutoff_ms(days_ago) if days_ago is not None else 0
    results = []
    for project_path, stats in data.items():
        input_tokens = stats.get("input_tokens", 0)
        output_tokens = stats.get("output_tokens", 0)
        cache_creation = stats.get("cache_creation_input_tokens", 0)
        cache_read = stats.get("cache_read_input_tokens", 0)
        total_tokens = stats.get("total_tokens", input_tokens + output_tokens)
        cost = stats.get("total_cost_usd", 0)
        cost_md = cost * 1_000_000 if cost < 1000 else cost
        if total_tokens == 0 and cost_md == 0:
            continue
        results.append({
            "project": project_path,
            "input": input_tokens, "output": output_tokens,
            "cache_creation": cache_creation, "cache_read": cache_read,
            "total_tokens": total_tokens, "cost_microdollars": cost_md,
            "last_updated": stats.get("last_updated", ""),
        })
    return results


def parse_conversations(max_sessions=50, days_ago=None):
    if not os.path.isdir(CLAUDE_CONVERSATIONS_DIR):
        return []
    conv_files = sorted(
        glob.glob(os.path.join(CLAUDE_CONVERSATIONS_DIR, "*.json")),
        key=os.path.getmtime, reverse=True,
    )[:max_sessions]
    cutoff = cutoff_ms(days_ago) if days_ago is not None else 0
    results = []
    for cf in conv_files:
        try:
            data = json.load(open(cf))
        except (json.JSONDecodeError, IOError):
            continue
        usage = data.get("usage", {})
        if not usage:
            continue
        input_tokens = usage.get("input_tokens", 0)
        output_tokens = usage.get("output_tokens", 0)
        cost = usage.get("cost", 0)
        cost_md = cost * 1_000_000 if 0 < cost < 1000 else cost
        total = input_tokens + output_tokens
        if total == 0 and cost_md == 0:
            continue
        ts = data.get("timestamp", data.get("created_at", ""))
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
            "session": data.get("session_id", data.get("id", os.path.basename(cf))),
            "model": data.get("model", "unknown"),
            "input": input_tokens, "output": output_tokens,
            "cost_microdollars": cost_md,
            "timestamp": ts, "file": os.path.basename(cf),
        })
    return results


def fmt(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def show_summary(data, output_json=False):
    total_input = sum(p["input"] for p in data)
    total_output = sum(p["output"] for p in data)
    total_cr = sum(p["cache_read"] for p in data)
    total_cc = sum(p["cache_creation"] for p in data)
    total_tokens = sum(p["total_tokens"] for p in data)
    total_cost = sum(p["cost_microdollars"] for p in data)
    if output_json:
        print(json.dumps({
            "tool": "claude", "projects": len(data),
            "input_tokens": total_input, "output_tokens": total_output,
            "cache_read": total_cr, "cache_creation": total_cc,
            "total_tokens": total_tokens,
            "estimated_cost_usd": round(total_cost / 1_000_000, 4),
        }, indent=2))
    else:
        print(f"  Claude Code Usage Summary ({len(data)} projects):")
        print("  " + "\u2500" * 62)
        print("  \u2502  Input:           {:>12s} tokens                    \u2502".format(fmt(total_input)))
        print("  \u2502  Output:          {:>12s} tokens                    \u2502".format(fmt(total_output)))
        print("  \u2502  Cache Read:      {:>12s} tokens                    \u2502".format(fmt(total_cr)))
        print("  \u2502  Cache Creation:  {:>12s} tokens                    \u2502".format(fmt(total_cc)))
        print("  \u2502  Total:           {:>12s} tokens                    \u2502".format(fmt(total_tokens)))
        print("  \u2502  Est. Cost:       ${:.4f}                        \u2502".format(total_cost / 1_000_000))
        print("  " + "\u2500" * 62)


def show_by_range(output_json=False):
    ranges = [("today", 0), ("week", 7), ("month", 30), ("6months", 180), ("all", None)]
    results = []
    for label, days in ranges:
        data = parse_stats_cache(days_ago=days)
        if not data:
            data = parse_conversations(max_sessions=10000, days_ago=days)
        total_input = sum(p["input"] for p in data)
        total_output = sum(p["output"] for p in data)
        total_cr = sum(p.get("cache_read", 0) for p in data)
        total_cc = sum(p.get("cache_creation", 0) for p in data)
        total_cost = sum(p.get("cost_microdollars", 0) for p in data)
        total_tokens = sum(p.get("total_tokens", p.get("input", 0) + p.get("output", 0)) for p in data)
        results.append({
            "range": label, "range_label": RANGE_LABELS[label],
            "entries": len(data),
            "input": total_input, "output": total_output,
            "cache_read": total_cr, "cache_creation": total_cc,
            "total_tokens": total_tokens,
            "cost_usd": round(total_cost / 1_000_000, 4),
        })
    if output_json:
        print(json.dumps(results, indent=2))
        return
    print("  Claude Code Usage by Time Period:")
    print("  {:<18s} {:>8s} {:>10s} {:>10s} {:>10s} {:>10s}".format(
        "Period", "Entries", "Input", "Output", "Cache", "Est. Cost"))
    print("  " + "\u2500" * 18 + " " + "\u2500" * 8 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10)
    for r in results:
        print("  {:<18s} {:>8d} {:>10s} {:>10s} {:>10s} ${:>9.4f}".format(
            r["range_label"], r["entries"],
            fmt(r["input"]), fmt(r["output"]),
            fmt(r["cache_read"] + r["cache_creation"]), r["cost_usd"]))


def show_sessions(data, output_json=False):
    if output_json:
        print(json.dumps(data, indent=2))
        return
    if not data:
        print("  No Claude sessions found.")
        return
    print(f"  Claude Code Sessions (last {len(data)}):")
    print("  {:<22s} {:<40s} {:<35s} {:>7s} {:>7s} {:>9s}".format(
        "Time", "Session", "Model", "Input", "Output", "Cost"))
    print("  " + "\u2500" * 22 + " " + "\u2500" * 40 + " " + "\u2500" * 35 + " " + "\u2500" * 7 + " " + "\u2500" * 7 + " " + "\u2500" * 9)
    for s in data:
        ts = str(s.get("timestamp", ""))[:21]
        print("  {:<22s} {:<40s} {:<35s} {:>7s} {:>7s} {:>9s}".format(
            ts, s["session"][:39], s["model"][:34],
            fmt(s["input"]), fmt(s["output"]),
            "${:.4f}".format(s["cost_microdollars"] / 1_000_000)))


def show_projects(data, output_json=False):
    if output_json:
        print(json.dumps(data, indent=2))
        return
    if not data:
        print("  No Claude project data found.")
        return
    data.sort(key=lambda x: x["total_tokens"], reverse=True)
    print("  Claude Code Usage by Project:")
    print("  {:<50s} {:>8s} {:>8s} {:>8s} {:>8s} {:>10s}".format(
        "Project", "Input", "Output", "Cache", "Total", "Cost"))
    print("  " + "\u2500" * 50 + " " + "\u2500" * 8 + " " + "\u2500" * 8 + " " + "\u2500" * 8 + " " + "\u2500" * 8 + " " + "\u2500" * 10)
    for p in data:
        project = p["project"]
        if len(project) > 49:
            project = "..." + project[-46:]
        cache = p["cache_read"] + p["cache_creation"]
        print("  {:<50s} {:>8s} {:>8s} {:>8s} {:>8s} ${:>9.4f}".format(
            project, fmt(p["input"]), fmt(p["output"]), fmt(cache),
            fmt(p["total_tokens"]), p["cost_microdollars"] / 1_000_000))


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
        data = parse_stats_cache(days_ago=days_ago)
        if not data and action in ("sessions",):
            data = parse_conversations(max_sessions, days_ago=days_ago)
        if action == "summary":
            show_summary(data, output_json)
        elif action == "sessions":
            show_sessions(data, output_json)
        elif action == "projects":
            show_projects(data, output_json)


if __name__ == "__main__":
    main()
