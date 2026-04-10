#!/usr/bin/env python3
"""
usage-ollama.py - Token usage report for Ollama
Since Ollama doesn't persist sessions, this script:
  1. Parses server logs for token metrics (if logging enabled)
  2. Reads from a local usage log (if user sets up request logging)
  3. Queries /api/ps for currently loaded models

Usage:
    usage-ollama.py --summary                    # Summary from available data
    usage-ollama.py --by-range                   # Not applicable (no timestamps in logs)
    usage-ollama.py --models                     # Model inventory with sizes
    usage-ollama.py --loaded                     # Currently loaded models
    usage-ollama.py --range <period>             # Filter by time (if log data exists)
    usage-ollama.py --json                       # JSON output
"""

import json
import os
import sys
import subprocess
import urllib.request
from datetime import datetime, timedelta

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")
OLLAMA_LOG_FILE = os.path.expanduser("~/.ollama/logs/server.log")
OLLAMA_USAGE_LOG = os.path.expanduser("~/.config/ollama/usage.log")

TIME_RANGES = {"all": None, "6months": 180, "month": 30, "week": 7, "today": 0}
RANGE_LABELS = {
    "all": "All time", "6months": "Last 6 months", "month": "Last 30 days",
    "week": "Last 7 days", "today": "Today",
}


def fmt_bytes(n):
    if n >= 1_073_741_824:
        return f"{n / 1_073_741_824:.1f} GB"
    if n >= 1_048_576:
        return f"{n / 1_048_576:.1f} MB"
    return f"{n} B"


def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def parse_server_logs():
    """Parse Ollama server logs for token usage metrics."""
    if not os.path.isfile(OLLAMA_LOG_FILE):
        return []

    results = []
    try:
        with open(OLLAMA_LOG_FILE, "r", errors="replace") as f:
            lines = f.readlines()
    except IOError:
        return []

    for line in lines:
        # Look for lines with prompt_eval_count or eval_count
        if "prompt_eval_count" not in line and "eval_count" not in line:
            continue

        try:
            # Try to parse as JSON fragment
            # Logs often contain: {"model":"...","prompt_eval_count":N,"eval_count":N,...}
            data = json.loads(line.strip())
            prompt_count = data.get("prompt_eval_count", 0)
            eval_count = data.get("eval_count", 0)
            if prompt_count == 0 and eval_count == 0:
                continue

            results.append({
                "model": data.get("model", "unknown"),
                "prompt_eval_count": prompt_count,
                "eval_count": eval_count,
                "prompt_eval_duration": data.get("prompt_eval_duration", 0),
                "eval_duration": data.get("eval_duration", 0),
                "total_duration": data.get("total_duration", 0),
            })
        except (json.JSONDecodeError, ValueError):
            # Try regex extraction from log line
            import re
            model_match = re.search(r'"model"\s*:\s*"([^"]+)"', line)
            prompt_match = re.search(r'"prompt_eval_count"\s*:\s*(\d+)', line)
            eval_match = re.search(r'"eval_count"\s*:\s*(\d+)', line)

            prompt_count = int(prompt_match.group(1)) if prompt_match else 0
            eval_count = int(eval_match.group(1)) if eval_match else 0

            if prompt_count == 0 and eval_count == 0:
                continue

            results.append({
                "model": model_match.group(1) if model_match else "unknown",
                "prompt_eval_count": prompt_count,
                "eval_count": eval_count,
                "prompt_eval_duration": 0,
                "eval_duration": 0,
                "total_duration": 0,
            })

    return results


def parse_usage_log():
    """Parse custom usage log if user set up request logging."""
    if not os.path.isfile(OLLAMA_USAGE_LOG):
        return []

    results = []
    try:
        with open(OLLAMA_USAGE_LOG, "r") as f:
            for line in f:
                try:
                    data = json.loads(line.strip())
                    results.append({
                        "model": data.get("model", "unknown"),
                        "prompt_eval_count": data.get("prompt_eval_count", 0),
                        "eval_count": data.get("eval_count", 0),
                        "prompt_eval_duration": data.get("prompt_eval_duration", 0),
                        "eval_duration": data.get("eval_duration", 0),
                        "total_duration": data.get("total_duration", 0),
                        "timestamp": data.get("timestamp", ""),
                    })
                except (json.JSONDecodeError, ValueError):
                    continue
    except IOError:
        pass

    return results


def get_model_list():
    """Get list of downloaded models via API."""
    try:
        r = urllib.request.urlopen(f"http://{OLLAMA_HOST}/api/tags", timeout=5)
        data = json.loads(r.read().decode())
        return data.get("models", [])
    except Exception:
        return []


def get_loaded_models():
    """Get currently loaded models via API."""
    try:
        r = urllib.request.urlopen(f"http://{OLLAMA_HOST}/api/ps", timeout=5)
        data = json.loads(r.read().decode())
        return data.get("models", [])
    except Exception:
        return []


def show_summary(usage_data, output_json=False):
    """Show usage summary from parsed data."""
    if not usage_data:
        models = get_model_list()
        loaded = get_loaded_models()

        if output_json:
            print(json.dumps({
                "tool": "ollama",
                "server_running": bool(models or loaded),
                "models_downloaded": len(models),
                "models_loaded": len(loaded),
                "total_prompt_tokens": 0,
                "total_output_tokens": 0,
                "note": "Ollama does not persist token usage. Enable request logging to track.",
            }, indent=2))
        else:
            print("  Ollama Usage Summary:")
            print("  " + "\u2500" * 62)
            print("  \u2502  Models downloaded: {:>6d}                              \u2502".format(len(models)))
            print("  \u2502  Models loaded:     {:>6d}                              \u2502".format(len(loaded)))
            print("  \u2502  Token usage:       Not tracked (local, stateless)      \u2502")
            print("  " + "\u2500" * 62)
            if not models and not loaded:
                print("  Note: Server may not be running. Check: ollama-status.sh")
        return

    total_prompt = sum(d["prompt_eval_count"] for d in usage_data)
    total_output = sum(d["eval_count"] for d in usage_data)
    total_prompt_dur = sum(d.get("prompt_eval_duration", 0) for d in usage_data)
    total_eval_dur = sum(d.get("eval_duration", 0) for d in usage_data)

    # Calculate tokens/sec
    total_gen_sec = total_output / (total_eval_dur / 1_000_000_000) if total_eval_dur > 0 else 0

    if output_json:
        print(json.dumps({
            "tool": "ollama",
            "requests": len(usage_data),
            "prompt_tokens": total_prompt,
            "output_tokens": total_output,
            "total_tokens": total_prompt + total_output,
            "avg_tokens_per_sec": round(total_gen_sec, 1),
            "note": "Parsed from server logs or usage.log",
        }, indent=2))
    else:
        print(f"  Ollama Usage Summary ({len(usage_data)} requests):")
        print("  " + "\u2500" * 62)
        print("  \u2502  Prompt Tokens:   {:>12s} tokens                      \u2502".format(fmt_tokens(total_prompt)))
        print("  \u2502  Output Tokens:   {:>12s} tokens                      \u2502".format(fmt_tokens(total_output)))
        print("  \u2502  Total Tokens:    {:>12s} tokens                      \u2502".format(fmt_tokens(total_prompt + total_output)))
        print("  \u2502  Generation Rate: {:>10.1f} tokens/sec                    \u2502".format(total_gen_sec))
        print("  " + "\u2500" * 62)


def show_by_range(usage_data, output_json=False):
    """Show usage by time period."""
    # Since Ollama logs don't have reliable timestamps, show a simple breakdown
    ranges = [("today", 0), ("week", 7), ("month", 30), ("6months", 180), ("all", None)]

    results = []
    for label, days in ranges:
        results.append({
            "range": label,
            "range_label": RANGE_LABELS[label],
            "sessions": len(usage_data) if days is None else 0,
            "input": 0, "output": 0,
            "cache_read": 0, "cache_write": 0,
            "cost_usd": 0,
        })

    # If we have timestamps in usage_data, distribute by time
    ts_data = [d for d in usage_data if d.get("timestamp")]
    if ts_data:
        cutoff = datetime.now()
        for d in ts_data:
            try:
                dt = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
                age = (datetime.now() - dt).days
            except (ValueError, TypeError):
                continue
            for label, days in ranges:
                if days is None or age <= days:
                    for r in results:
                        if r["range"] == label:
                            r["sessions"] += 1
                            r["input"] += d.get("prompt_eval_count", 0)
                            r["output"] += d.get("eval_count", 0)
                            break

    if output_json:
        print(json.dumps(results, indent=2))
        return

    print("  Ollama Usage by Time Period:")
    print("  {:<18s} {:>8s} {:>10s} {:>10s} {:>10s}".format(
        "Period", "Requests", "Prompt", "Output", "Total"))
    print("  " + "\u2500" * 18 + " " + "\u2500" * 8 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10)

    for r in results:
        print("  {:<18s} {:>8d} {:>10s} {:>10s} {:>10s}".format(
            r["range_label"], r["sessions"],
            fmt_tokens(r["input"]), fmt_tokens(r["output"]),
            fmt_tokens(r["input"] + r["output"])))


def show_models(output_json=False):
    """Show downloaded models with sizes."""
    models = get_model_list()
    if not models:
        if output_json:
            print(json.dumps({"tool": "ollama", "models": []}))
        else:
            print("  No models downloaded.")
            print("  Download one: ollama pull llama3.2")
        return

    if output_json:
        print(json.dumps([{
            "name": m.get("name"), "size": m.get("size"),
            "digest": m.get("digest"), "modified": m.get("modified_at"),
        } for m in models], indent=2))
        return

    print("  Ollama Models:")
    total_size = 0
    print("  {:<40s} {:>10s} {:<20s}".format("Model", "Size", "Modified"))
    print("  " + "\u2500" * 40 + " " + "\u2500" * 10 + " " + "\u2500" * 20)
    for m in sorted(models, key=lambda x: x.get("name", "")):
        name = m.get("name", "unknown")
        size = m.get("size", 0)
        modified = m.get("modified_at", "")[:19]
        total_size += size
        print("  {:<40s} {:>10s} {:<20s}".format(name, fmt_bytes(size), modified))
    print("  " + "\u2500" * 40 + " " + "\u2500" * 10 + " " + "\u2500" * 20)
    print("  Total: {} model(s), {}".format(len(models), fmt_bytes(total_size)))


def show_loaded(output_json=False):
    """Show currently loaded models."""
    models = get_loaded_models()
    if not models:
        if output_json:
            print(json.dumps({"tool": "ollama", "loaded": []}))
        else:
            print("  No models currently loaded in memory.")
        return

    if output_json:
        print(json.dumps([{
            "name": m.get("name"), "size": m.get("size"),
            "size_vram": m.get("size_vram"),
            "context_length": m.get("context_length"),
            "expires_at": m.get("expires_at"),
        } for m in models], indent=2))
        return

    total_vram = 0
    print("  Loaded Models (in memory):")
    print("  {:<30s} {:>10s} {:>10s} {:>8s}".format("Model", "Size", "VRAM", "Context"))
    print("  " + "\u2500" * 30 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 8)
    for m in sorted(models, key=lambda x: x.get("name", "")):
        name = m.get("name", "unknown")
        size = m.get("size", 0)
        vram = m.get("size_vram", 0)
        ctx = m.get("context_length", "?")
        total_vram += vram
        print("  {:<30s} {:>10s} {:>10s} {:>8s}".format(
            name, fmt_bytes(size), fmt_bytes(vram), str(ctx)))
    print("  " + "\u2500" * 30 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 8)
    print("  Total VRAM used: {}".format(fmt_bytes(total_vram)))


def main():
    action = "summary"
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
        elif a == "--models":
            action = "models"; i += 1
        elif a == "--loaded":
            action = "loaded"; i += 1
        elif a == "--range":
            i += 1
            if i < len(args) and args[i] in TIME_RANGES:
                days_ago = TIME_RANGES[args[i]]; i += 1
        elif a == "--json":
            output_json = True; i += 1
        else:
            i += 1

    # Parse available data sources
    usage_data = parse_usage_log()
    if not usage_data:
        usage_data = parse_server_logs()

    if action == "summary":
        show_summary(usage_data, output_json)
    elif action == "by-range":
        show_by_range(usage_data, output_json)
    elif action == "models":
        show_models(output_json)
    elif action == "loaded":
        show_loaded(output_json)


if __name__ == "__main__":
    main()
