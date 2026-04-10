#!/usr/bin/env python3
"""
clear-sessions.py - Clear session data for AI CLI tools

Supports: kilo, opencode, qwen, gemini, claude (or "all")
Time ranges: today, week, month, 6months, all

Usage:
    clear-sessions.py --tool kilo --range today
    clear-sessions.py --tool all --range month --dry-run
    clear-sessions.py --tool gemini,claude --range week
    clear-sessions.py --list  # Show what would be deleted without running
"""

import json
import os
import sys
import glob
import shutil
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

# ─── Paths ────────────────────────────────────────────────────────────────────

HOME = os.path.expanduser("~")

TOOLS = {
    "kilo": {
        "label": "Kilo CLI",
        "sqlite": os.path.join(HOME, ".local", "share", "kilo", "kilo.db"),
        "sqlite_type": "kilo",
    },
    "opencode": {
        "label": "OpenCode CLI",
        "sqlite": os.path.join(HOME, ".local", "share", "opencode", "opencode.db"),
        "sqlite_type": "opencode",
    },
    "qwen": {
        "label": "Qwen Code CLI",
        "sessions_dir": os.path.join(HOME, ".local", "share", "qwen", "sessions"),
        "file_type": "qwen",
    },
    "gemini": {
        "label": "Gemini CLI",
        "chats_root": os.path.join(HOME, ".gemini", "tmp"),
        "file_type": "gemini",
    },
    "claude": {
        "label": "Claude Code CLI",
        "conversations_dir": os.path.join(HOME, ".claude", "conversations"),
        "projects_dir": os.path.join(HOME, ".claude", "projects"),
        "stats_cache": os.path.join(HOME, ".claude", "stats-cache.json"),
        "file_type": "claude",
    },
}

# ─── Time ranges ──────────────────────────────────────────────────────────────

TIME_RANGES = {
    "today": lambda: datetime.now().replace(hour=0, minute=0, second=0, microsecond=0),
    "week": lambda: datetime.now() - timedelta(days=7),
    "month": lambda: datetime.now() - timedelta(days=30),
    "6months": lambda: datetime.now() - timedelta(days=180),
    "all": lambda: datetime.min,
}

RANGE_LABELS = {
    "today": "today",
    "week": "last 7 days",
    "month": "last 30 days",
    "6months": "last 6 months",
    "all": "all",
}


# ─── Helpers ──────────────────────────────────────────────────────────────────

def fmt_size(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}MB"
    if n >= 1_000:
        return f"{n / 1_000:.1f}KB"
    return f"{n}B"


def file_age_ms(filepath):
    """Get file modification time as epoch milliseconds."""
    try:
        return int(os.path.getmtime(filepath) * 1000)
    except OSError:
        return 0


def cutoff_ms(time_range):
    """Get cutoff time in epoch milliseconds."""
    if time_range == "all":
        return 0
    dt = TIME_RANGES[time_range]()
    return int(dt.timestamp() * 1000)


def cutoff_ms_str(time_range):
    """Human-readable cutoff description."""
    if time_range == "all":
        return "all sessions"
    dt = TIME_RANGES[time_range]()
    return dt.strftime("%Y-%m-%d %H:%M:%S")


# ─── Kilo / OpenCode (SQLite) ─────────────────────────────────────────────────

def clear_sqlite(tool_name, tool_cfg, time_range, dry_run=False):
    """Clear sessions from SQLite database by date."""
    db_path = tool_cfg["sqlite"]
    label = tool_cfg["label"]
    cutoff = cutoff_ms(time_range)

    if not os.path.isfile(db_path):
        return {"tool": tool_name, "label": label, "status": "db_not_found", "deleted": 0}

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # For "all" range, delete all sessions; otherwise filter by cutoff
    if time_range == "all":
        rows = cur.execute(
            "SELECT id, title, time_created, time_updated FROM session ORDER BY time_created"
        ).fetchall()
    else:
        # Get sessions older than cutoff
        rows = cur.execute(
            "SELECT id, title, time_created, time_updated FROM session WHERE time_created < ? ORDER BY time_created",
            (cutoff,),
        ).fetchall()

    session_ids = [r[0] for r in rows]
    session_count = len(session_ids)

    if session_count == 0:
        conn.close()
        return {"tool": tool_name, "label": label, "status": "nothing_to_delete", "deleted": 0, "time_range": time_range}

    if dry_run:
        # Report what would be deleted
        oldest = rows[-1][2] if rows else 0
        newest = rows[0][2] if rows else 0
        conn.close()
        return {
            "tool": tool_name,
            "label": label,
            "status": "would_delete",
            "session_count": session_count,
            "oldest": oldest,
            "newest": newest,
            "cutoff": cutoff,
        }

    # Delete messages first (FK constraint), then sessions
    if session_ids:
        placeholders = ",".join("?" for _ in session_ids)
        cur.execute(f"DELETE FROM message WHERE session_id IN ({placeholders})", session_ids)
        cur.execute(f"DELETE FROM session WHERE id IN ({placeholders})", session_ids)
        conn.commit()

    conn.close()
    return {
        "tool": tool_name,
        "label": label,
        "status": "deleted",
        "session_count": session_count,
        "cutoff": cutoff,
    }


# ─── Qwen (JSON session files) ────────────────────────────────────────────────

def clear_qwen(tool_name, tool_cfg, time_range, dry_run=False):
    """Clear Qwen session JSON files by date."""
    sessions_dir = tool_cfg.get("sessions_dir")
    label = tool_cfg["label"]
    cutoff = cutoff_ms(time_range)

    if not os.path.isdir(sessions_dir):
        return {"tool": tool_name, "label": label, "status": "dir_not_found", "deleted": 0}

    files = glob.glob(os.path.join(sessions_dir, "*.json"))
    deleted = 0
    matched = []

    for fp in files:
        try:
            data = json.load(open(fp))
        except (json.JSONDecodeError, IOError):
            continue

        ts = data.get("timestamp", data.get("created_at", ""))
        file_ts = int(os.path.getmtime(fp) * 1000)

        # Try to parse timestamp
        if ts:
            try:
                # Handle various timestamp formats
                if isinstance(ts, (int, float)):
                    ts_ms = int(ts)
                elif isinstance(ts, str):
                    # ISO format
                    ts_dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    ts_ms = int(ts_dt.timestamp() * 1000)
                else:
                    ts_ms = file_ts
            except (ValueError, TypeError):
                ts_ms = file_ts
        else:
            ts_ms = file_ts

        # For "all" range, delete everything; otherwise use cutoff
        if time_range == "all" or ts_ms < cutoff:
            matched.append({"file": os.path.basename(fp), "timestamp": ts_ms})
            deleted += 1
            if not dry_run:
                os.remove(fp)

    if deleted == 0:
        return {"tool": tool_name, "label": label, "status": "nothing_to_delete", "deleted": 0, "time_range": time_range}

    return {
        "tool": tool_name,
        "label": label,
        "status": "would_delete" if dry_run else "deleted",
        "session_count": deleted,
        "files": matched[:5],  # First 5 for display
    }


# ─── Gemini (JSON chat files) ────────────────────────────────────────────────

def clear_gemini(tool_name, tool_cfg, time_range, dry_run=False):
    """Clear Gemini session JSON files by date."""
    chats_root = tool_cfg.get("chats_root")
    label = tool_cfg["label"]
    cutoff = cutoff_ms(time_range)

    if not os.path.isdir(chats_root):
        return {"tool": tool_name, "label": label, "status": "dir_not_found", "deleted": 0}

    deleted = 0
    matched = []

    for project_hash in os.listdir(chats_root):
        chats_dir = os.path.join(chats_root, project_hash, "chats")
        if not os.path.isdir(chats_dir):
            continue

        for cf in os.listdir(chats_dir):
            fp = os.path.join(chats_dir, cf)
            if not os.path.isfile(fp):
                continue

            file_ts = int(os.path.getmtime(fp) * 1000)

            # Try to extract timestamp from filename: session-YYYY-MM-DDTHH-MM-<id>.json
            ts_ms = file_ts
            try:
                # Parse filename pattern
                base = os.path.splitext(cf)[0]
                # session-2025-11-08T02-38-b156cf6f
                parts = base.split("T")
                if len(parts) == 2:
                    date_part = parts[0].replace("session-", "")
                    time_part = parts[1].rsplit("-", 1)[0]  # Remove trailing hash
                    dt = datetime.strptime(f"{date_part}T{time_part.replace('-', ':')}", "%Y-%m-%dT%H:%M")
                    ts_ms = int(dt.timestamp() * 1000)
            except (ValueError, IndexError):
                pass

            # For "all" range, delete everything; otherwise use cutoff
            if time_range == "all" or ts_ms < cutoff:
                matched.append({"file": cf, "project": project_hash[:16], "timestamp": ts_ms})
                deleted += 1
                if not dry_run:
                    os.remove(fp)

        # Clean up empty project dirs
        if not dry_run and not os.listdir(chats_dir):
            project_dir = os.path.dirname(chats_dir)
            if not os.listdir(project_dir):
                os.rmdir(project_dir)

    if deleted == 0:
        return {"tool": tool_name, "label": label, "status": "nothing_to_delete", "deleted": 0, "time_range": time_range}

    return {
        "tool": tool_name,
        "label": label,
        "status": "would_delete" if dry_run else "deleted",
        "session_count": deleted,
        "files": matched[:5],
    }


# ─── Claude (JSON conversations + JSONL projects) ────────────────────────────

def clear_claude(tool_name, tool_cfg, time_range, dry_run=False):
    """Clear Claude session data by date."""
    conv_dir = tool_cfg.get("conversations_dir")
    projects_dir = tool_cfg.get("projects_dir")
    stats_cache = tool_cfg.get("stats_cache")
    label = tool_cfg["label"]
    cutoff = cutoff_ms(time_range)

    total_deleted = 0
    results = []

    # 1. Clear conversation JSON files
    if os.path.isdir(conv_dir):
        for cf in os.listdir(conv_dir):
            fp = os.path.join(conv_dir, cf)
            if not os.path.isfile(fp) or not cf.endswith(".json"):
                continue

            file_ts = int(os.path.getmtime(fp) * 1000)
            try:
                data = json.load(open(fp))
                ts = data.get("timestamp", data.get("created_at", ""))
                if ts:
                    if isinstance(ts, str):
                        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                        file_ts = int(dt.timestamp() * 1000)
            except (json.JSONDecodeError, ValueError, TypeError):
                pass

            # For "all" range, delete everything; otherwise use cutoff
            if time_range == "all" or file_ts < cutoff:
                total_deleted += 1
                if not dry_run:
                    os.remove(fp)

    # 2. Clear project session JSONL files
    if os.path.isdir(projects_dir):
        for proj_hash in os.listdir(projects_dir):
            sessions_dir = os.path.join(projects_dir, proj_hash, "sessions")
            if not os.path.isdir(sessions_dir):
                continue

            for sf in os.listdir(sessions_dir):
                fp = os.path.join(sessions_dir, sf)
                if not os.path.isfile(fp):
                    continue

                file_ts = int(os.path.getmtime(fp) * 1000)
                # For "all" range, delete everything; otherwise use cutoff
                if time_range == "all" or file_ts < cutoff:
                    total_deleted += 1
                    if not dry_run:
                        os.remove(fp)

            # Clean empty session dirs
            if not dry_run and not os.listdir(sessions_dir):
                os.rmdir(sessions_dir)

    # 3. Optionally clear stats-cache.json
    if os.path.isfile(stats_cache) and time_range == "all":
        if not dry_run:
            os.remove(stats_cache)
        total_deleted += 1

    if total_deleted == 0:
        return {"tool": tool_name, "label": label, "status": "nothing_to_delete", "deleted": 0, "time_range": time_range}

    return {
        "tool": tool_name,
        "label": label,
        "status": "would_delete" if dry_run else "deleted",
        "session_count": total_deleted,
        "cutoff": cutoff,
    }


# ─── Dispatcher ───────────────────────────────────────────────────────────────

def clear_tool(tool_name, time_range, dry_run=False):
    """Clear sessions for a single tool."""
    if tool_name not in TOOLS:
        return {"tool": tool_name, "status": "unknown_tool", "deleted": 0}

    cfg = TOOLS[tool_name]

    if "sqlite" in cfg:
        return clear_sqlite(tool_name, cfg, time_range, dry_run)
    elif cfg.get("file_type") == "qwen":
        return clear_qwen(tool_name, cfg, time_range, dry_run)
    elif cfg.get("file_type") == "gemini":
        return clear_gemini(tool_name, cfg, time_range, dry_run)
    elif cfg.get("file_type") == "claude":
        return clear_claude(tool_name, cfg, time_range, dry_run)

    return {"tool": tool_name, "status": "no_handler", "deleted": 0}


def format_timestamp(ms):
    """Format epoch ms to readable date."""
    try:
        return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError, OverflowError):
        return "unknown"


def print_report(results, dry_run=False, time_range=""):
    """Print a summary report."""
    action = "Would delete" if dry_run else "Deleted"
    print("  Session Cleanup Report ({}):".format(RANGE_LABELS.get(time_range, time_range)))
    print("  " + "─" * 62)

    total = 0
    for r in results:
        tool = r["tool"]
        label = r.get("label", tool)
        status = r.get("status", "unknown")
        count = r.get("session_count", r.get("deleted", 0))

        if status in ("db_not_found", "dir_not_found", "nothing_to_delete"):
            print("  {:<20s} {}".format(label, "─" * 42))
            continue

        total += count
        verb = "would clear" if dry_run else "cleared"
        print("  {:<20s} {} {:>5d} sessions {}".format(label, action, count, verb))

        # Show oldest/newest if available
        if "oldest" in r and "newest" in r:
            oldest = format_timestamp(r["oldest"])
            newest = format_timestamp(r["newest"])
            print("    Range: {} \u2192 {}".format(oldest, newest))

    print("  " + "─" * 62)
    print("  {:<20s} {} {:>5d} sessions".format("Total", action, total))
    if dry_run:
        print("  (Dry run \u2014 nothing was deleted)")
    print()


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    tools = []
    time_range = ""
    dry_run = False
    list_mode = False

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--tool":
            i += 1
            if i < len(args):
                tools = [t.strip() for t in args[i].split(",")]
                i += 1
            else:
                print("❌ --tool requires a value")
                sys.exit(1)
        elif a == "--range":
            i += 1
            if i < len(args):
                time_range = args[i]
                i += 1
            else:
                print("❌ --range requires a value")
                sys.exit(1)
        elif a == "--dry-run":
            dry_run = True
            i += 1
        elif a == "--list":
            list_mode = True
            i += 1
        elif a in ("--all", "-a"):
            tools = list(TOOLS.keys())
            i += 1
        elif a == "--help":
            print(__doc__)
            sys.exit(0)
        else:
            # Positional arg: could be tool name or time range
            # Check tool names FIRST (since "all" is also a time range)
            if a == "all":
                tools = list(TOOLS.keys())
            elif a in TOOLS:
                if a not in tools:
                    tools.append(a)
            elif a in TIME_RANGES and not time_range:
                time_range = a
            i += 1

    if list_mode:
        # Just list what exists
        print("  Available Tools:")
        for name, cfg in TOOLS.items():
            label = cfg.get("label", name)
            exists = False
            if "sqlite" in cfg:
                exists = os.path.isfile(cfg["sqlite"])
            elif "sessions_dir" in cfg:
                exists = os.path.isdir(cfg["sessions_dir"])
            elif "chats_root" in cfg:
                exists = os.path.isdir(cfg["chats_root"])
            elif "conversations_dir" in cfg:
                exists = os.path.isdir(cfg["conversations_dir"])
            status = "✅" if exists else "⚠ no data"
            print(f"    {name:<12s} {status}  {label}")
        print()
        print("  Time Ranges:")
        for name, desc in [("today", "Delete sessions from today"),
                           ("week", "Delete sessions older than 7 days"),
                           ("month", "Delete sessions older than 30 days"),
                           ("6months", "Delete sessions older than 6 months"),
                           ("all", "Delete all sessions")]:
            print(f"    {name:<12s} {desc}")
        return

    if not tools:
        print("❌ No tools specified. Use --tool <name> or --all")
        print(f"   Available: {', '.join(TOOLS.keys())}")
        sys.exit(1)

    if not time_range:
        print("❌ No time range specified. Use --range <range>")
        print(f"   Available: {', '.join(TIME_RANGES.keys())}")
        sys.exit(1)

    if time_range not in TIME_RANGES:
        print(f"❌ Unknown time range: {time_range}")
        print(f"   Available: {', '.join(TIME_RANGES.keys())}")
        sys.exit(1)

    # Validate tools
    valid_tools = []
    for t in tools:
        if t in TOOLS:
            valid_tools.append(t)
        else:
            print(f"  ⚠ Unknown tool: {t}")

    if not valid_tools:
        print("❌ No valid tools specified.")
        sys.exit(1)

    results = []
    for t in valid_tools:
        results.append(clear_tool(t, time_range, dry_run))

    print_report(results, dry_run, time_range)


if __name__ == "__main__":
    main()
