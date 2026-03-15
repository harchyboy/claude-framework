#!/usr/bin/env python3
"""RTK Rewrite Hook — Token compression via RTK (Rust Token Killer).

Runs on: PreToolUse (matched to Bash)

Intercepts Bash commands and rewrites them through RTK for automatic
token compression. RTK strips noise from git, ls, find, pytest, etc.
before output enters the context window.

Saves 60-90% tokens on common dev commands with zero workflow changes.
See: https://github.com/rtk-ai/rtk
"""

import json
import os
import shutil
import subprocess
import sys


def main():
    # Read JSON from stdin
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, IOError):
        return  # Pass through silently

    command = data.get("tool_input", {}).get("command", "")
    if not command or command.startswith("rtk "):
        return  # Nothing to rewrite

    # Find rtk binary
    rtk_bin = shutil.which("rtk") or shutil.which("rtk.exe")
    if not rtk_bin:
        # Check common install locations
        for candidate in [
            os.path.expanduser("~/.local/bin/rtk.exe"),
            os.path.expanduser("~/.local/bin/rtk"),
            os.path.expanduser("~/bin/rtk"),
        ]:
            if os.path.isfile(candidate):
                rtk_bin = candidate
                break

    if not rtk_bin:
        return  # RTK not installed, pass through

    # Ask rtk if this command should be rewritten
    try:
        result = subprocess.run(
            [rtk_bin, "rewrite", command],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.TimeoutExpired, OSError):
        return  # Don't block on errors

    # Exit code 1 = no rewrite available, pass through
    if result.returncode != 0 or not result.stdout.strip():
        return

    rewritten = result.stdout.strip()

    # Output the rewrite in Claude Code's hook format
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "RTK token compression",
            "updatedInput": {
                "command": rewritten,
            },
        }
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
