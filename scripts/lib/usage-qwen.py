#!/usr/bin/env python3
"""
usage-qwen.py - Token usage report for Qwen Code CLI
Reads from ~/.local/share/qwen/sessions/*.json.
"""

import json
import os
import sys
import glob
from datetime import datetime, timedelta

QWEN_SESSION_DIR = os.path.expanduser("~/.local/share/qwen/sessions")

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
    if not os.path.isdir(QWEN_SESSION_DIR):
        return []
    files = sorted(glob.glob(os.path.join(QWEN_SESSION_DIR, "*.json")),
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
        cost = usage.get("cost_microdollars", usage.get("cost", 0))
        if 0 < cost < 1000:
            cost = cost * 1_000_000
        total = usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
        if total == 0 and cost == 0:
            continue
        results.append({
            "date": data.get("timestamp", data.get("created_at", "")),
            "session": data.get("sessionId", data.get("id", os.path.basename(sf))),
            "model": data.get("model", "unknown"),
            "input": usage.get("input_tokens", 0), "output": usage.get("output_tokens", 0),
            "cache_read": usage.get("cache_read_tokens", usage.get("cache_hit_tokens", 0)),
            "cache_write": usage.get("cache_write_tokens", 0), "cost": cost,
            "file": os.path.basename(sf),
        })
    return results


def fmt(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def show_summary(data, output_json=False):
    total_input = sum(s["input"] for s in data)
    total_output = sum(s["output"] for s in data)
    total_cr = sum(s["cache_read"] for s in data)
    total_cw = sum(s["cache_write"] for s in data)
    total_cost = sum(s["cost"] for s in data)
    if output_json:
        print(json.dumps({
            "tool": "qwen", "sessions": len(data),
            "input_tokens": total_input, "output_tokens": total_output,
            "cache_read": total_cr, "cache_write": total_cw,
            "estimated_cost_usd": round(total_cost / 1_000_000, 4),
        }, indent=2))
    else:
        print(f"  Qwen Code Usage Summary ({len(data)} sessions):")
        print("  " + "\u2500" * 62)
        print("  \u2502  Input:       {:>12s} tokens                      \u2502".format(fmt(total_input)))
        print("  \u2502  Output:      {:>12s} tokens                      \u2502".format(fmt(total_output)))
        print("  \u2502  Cache Read:  {:>12s} tokens                      \u2502".format(fmt(total_cr)))
        print("  \u2502  Cache Write: {:>12s} tokens                      \u2502".format(fmt(total_cw)))
        print("  \u2502  Est. Cost:   ${:.4f}                          \u2502".format(total_cost / 1_000_000))
        print("  " + "\u2500" * 62)


def show_by_range(output_json=False):
    ranges = [("today", 0), ("week", 7), ("month", 30), ("6months", 180), ("all", None)]
    results = []
    for label, days in ranges:
        data = parse_sessions(max_sessions=10000, days_ago=days)
        total_input = sum(s["input"] for s in data)
        total_output = sum(s["output"] for s in data)
        total_cr = sum(s["cache_read"] for s in data)
        total_cw = sum(s["cache_write"] for s in data)
        total_cost = sum(s["cost"] for s in data)
        results.append({
            "range": label, "range_label": RANGE_LABELS[label],
            "sessions": len(data),
            "input": total_input, "output": total_output,
            "cache_read": total_cr, "cache_write": total_cw,
            "total_tokens": total_input + total_output + total_cr + total_cw,
            "cost_usd": round(total_cost / 1_000_000, 4),
        })
    if output_json:
        print(json.dumps(results, indent=2))
        return
    print("  Qwen Code Usage by Time Period:")
    print("  {:<18s} {:>8s} {:>10s} {:>10s} {:>10s} {:>10s}".format(
        "Period", "Sessions", "Input", "Output", "Cache", "Est. Cost"))
    print("  " + "\u2500" * 18 + " " + "\u2500" * 8 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10)
    for r in results:
        print("  {:<18s} {:>8d} {:>10s} {:>10s} {:>10s} ${:>9.4f}".format(
            r["range_label"], r["sessions"],
            fmt(r["input"]), fmt(r["output"]),
            fmt(r["cache_read"] + r["cache_write"]), r["cost_usd"]))


def show_sessions(data, output_json=False):
    if output_json:
        print(json.dumps(data, indent=2))
        return
    if not data:
        print("  No Qwen sessions found.")
        return
    print(f"  Qwen Code Sessions (last {len(data)}):")
    print("  {:<22s} {:<45s} {:<30s} {:>7s} {:>7s} {:>9s}".format(
        "Date", "Session", "Model", "Input", "Output", "Cost"))
    print("  " + "\u2500" * 22 + " " + "\u2500" * 45 + " " + "\u2500" * 30 + " " + "\u2500" * 7 + " " + "\u2500" * 7 + " " + "\u2500" * 9)
    for s in data:
        print("  {:<22s} {:<45s} {:<30s} {:>7s} {:>7s} {:>9s}".format(
            str(s.get("date", ""))[:21],
            s.get("session", s.get("file", ""))[:44],
            s["model"][:29],
            fmt(s["input"]), fmt(s["output"]),
            "${:.4f}".format(s["cost"] / 1_000_000)))


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


if __name__ == "__main__":
    main()
