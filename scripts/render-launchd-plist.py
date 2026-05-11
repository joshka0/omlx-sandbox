#!/usr/bin/env python3
"""Render the oMLX LaunchDaemon plist."""

from __future__ import annotations

import argparse
import plistlib
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--group", required=True)
    parser.add_argument("--home", required=True)
    parser.add_argument("--tmp", required=True)
    parser.add_argument("--xdg-cache", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--python")
    parser.add_argument("--base-path", required=True)
    parser.add_argument("--stdout", required=True)
    parser.add_argument("--stderr", required=True)
    args = parser.parse_args()

    command = [
        "/usr/bin/sandbox-exec",
        "-f",
        args.profile,
    ]
    if args.python:
        command.extend([args.python, args.executable])
    else:
        command.append(args.executable)
    command.extend(
        [
            "serve",
            "--base-path",
            args.base_path,
        ]
    )

    plist = {
        "Label": args.label,
        "UserName": args.user,
        "GroupName": args.group,
        "ProgramArguments": command,
        "WorkingDirectory": args.home,
        "EnvironmentVariables": {
            "HOME": args.home,
            "TMPDIR": args.tmp,
            "XDG_CACHE_HOME": args.xdg_cache,
            "PYTHONDONTWRITEBYTECODE": "1",
        },
        "StandardOutPath": args.stdout,
        "StandardErrorPath": args.stderr,
        "RunAtLoad": False,
        "KeepAlive": False,
        "ProcessType": "Background",
        "InitGroups": False,
        "Umask": 0o077,
    }
    plistlib.dump(plist, sys.stdout.buffer, sort_keys=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
