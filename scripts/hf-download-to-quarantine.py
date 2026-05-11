#!/usr/bin/env python3
"""Download a Hugging Face model snapshot into quarantine."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
from pathlib import Path

from huggingface_hub import HfApi, snapshot_download


DEFAULT_ALLOW_PATTERNS = [
    "*.safetensors",
    "*.json",
    "*.txt",
    "*.md",
    "*.model",
    "*.spm",
    "*.tiktoken",
    "*.yaml",
    "*.yml",
    "*.jinja",
]

DEFAULT_IGNORE_PATTERNS = [
    "*.bin",
    "*.ckpt",
    "*.dylib",
    "*.egg",
    "*.exe",
    "*.pkl",
    "*.pickle",
    "*.pt",
    "*.pth",
    "*.pyc",
    "*.so",
    "*.whl",
    ".git/*",
]


def split_patterns(value: str | None, default: list[str]) -> list[str]:
    if not value:
        return default
    return [item.strip() for item in value.split(",") if item.strip()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--revision", default="main")
    parser.add_argument("--dest", required=True, type=Path)
    parser.add_argument("--cache-dir", required=True, type=Path)
    parser.add_argument("--allow-patterns")
    parser.add_argument("--ignore-patterns")
    parser.add_argument("--token-file", type=Path)
    parser.add_argument("--max-workers", type=int, default=4)
    args = parser.parse_args()

    token = None
    if args.token_file:
        token = args.token_file.read_text(encoding="utf-8").strip()
    elif os.environ.get("HF_TOKEN"):
        token = os.environ["HF_TOKEN"]

    allow_patterns = split_patterns(args.allow_patterns, DEFAULT_ALLOW_PATTERNS)
    ignore_patterns = split_patterns(args.ignore_patterns, DEFAULT_IGNORE_PATTERNS)

    api = HfApi(token=token)
    info = api.model_info(args.repo, revision=args.revision)
    resolved_revision = info.sha

    args.dest.mkdir(parents=True, exist_ok=False)
    args.cache_dir.mkdir(parents=True, exist_ok=True)

    snapshot_download(
        repo_id=args.repo,
        revision=resolved_revision,
        local_dir=args.dest,
        allow_patterns=allow_patterns,
        ignore_patterns=ignore_patterns,
        token=token,
        max_workers=args.max_workers,
    )

    shutil.rmtree(args.dest / ".cache", ignore_errors=True)

    source = {
        "downloaded_at": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat(),
        "repo": args.repo,
        "revision_requested": args.revision,
        "revision_resolved": resolved_revision,
        "allow_patterns": allow_patterns,
        "ignore_patterns": ignore_patterns,
    }
    (args.dest / "omlx-source.json").write_text(
        json.dumps(source, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(json.dumps(source, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
