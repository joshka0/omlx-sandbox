#!/usr/bin/env python3
"""Merge sandbox runtime settings into oMLX settings.json."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise SystemExit(f"settings file is not a JSON object: {path}")
    return data


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings-file", required=True)
    parser.add_argument("--api-key-file", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--cache-dir", required=True)
    parser.add_argument("--log-dir", required=True)
    parser.add_argument("--max-process-memory", required=True)
    parser.add_argument("--max-model-memory", required=True)
    parser.add_argument("--max-concurrent-requests", type=int, required=True)
    args = parser.parse_args()

    settings_path = Path(args.settings_file)
    api_key = Path(args.api_key_file).read_text(encoding="utf-8").strip()
    if not api_key:
        raise SystemExit(f"empty API key file: {args.api_key_file}")

    data = load_json(settings_path)
    data["version"] = data.get("version", "1.0")

    server = data.setdefault("server", {})
    server["host"] = args.host
    server["port"] = args.port

    model = data.setdefault("model", {})
    model["model_dirs"] = [args.model_dir]
    model["model_dir"] = args.model_dir
    model["max_model_memory"] = args.max_model_memory

    memory = data.setdefault("memory", {})
    memory["max_process_memory"] = args.max_process_memory

    scheduler = data.setdefault("scheduler", {})
    scheduler["max_concurrent_requests"] = args.max_concurrent_requests

    cache = data.setdefault("cache", {})
    cache["enabled"] = True
    cache["ssd_cache_dir"] = args.cache_dir

    logging = data.setdefault("logging", {})
    logging["log_dir"] = args.log_dir

    auth = data.setdefault("auth", {})
    auth["api_key"] = api_key
    auth.setdefault("skip_api_key_verification", False)

    settings_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = settings_path.with_suffix(settings_path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    tmp_path.replace(settings_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
