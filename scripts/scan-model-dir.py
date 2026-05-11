#!/usr/bin/env python3
"""Scan a candidate model directory before promotion to oMLX approved storage."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path


DENY_EXTENSIONS = {
    ".bin",
    ".ckpt",
    ".dylib",
    ".egg",
    ".exe",
    ".pkl",
    ".pickle",
    ".pt",
    ".pth",
    ".pyc",
    ".so",
    ".whl",
}

WARN_EXTENSIONS = {
    ".bat",
    ".command",
    ".fish",
    ".js",
    ".mjs",
    ".ps1",
    ".py",
    ".rb",
    ".sh",
    ".zsh",
}

ALLOW_EXTENSIONS = {
    ".json",
    ".md",
    ".model",
    ".safetensors",
    ".spm",
    ".tiktoken",
    ".txt",
    ".yaml",
    ".yml",
    ".jinja",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def scan(root: Path) -> dict:
    root = root.resolve()
    findings: list[dict] = []
    files: list[dict] = []
    safetensors = 0

    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
      dir_path = Path(dirpath)
      for dirname in list(dirnames):
          p = dir_path / dirname
          if p.is_symlink():
              findings.append({"severity": "deny", "path": str(p.relative_to(root)), "reason": "symlink directory"})
              dirnames.remove(dirname)

      for filename in filenames:
          path = dir_path / filename
          rel = path.relative_to(root)
          suffix = path.suffix.lower()

          if path.is_symlink():
              findings.append({"severity": "deny", "path": str(rel), "reason": "symlink file"})
              continue

          resolved = path.resolve()
          if root not in resolved.parents and resolved != root:
              findings.append({"severity": "deny", "path": str(rel), "reason": "path escapes root"})
              continue

          mode = path.stat().st_mode
          executable = bool(mode & 0o111)

          if suffix in DENY_EXTENSIONS:
              findings.append({"severity": "deny", "path": str(rel), "reason": f"denied extension {suffix}"})
          elif suffix in WARN_EXTENSIONS:
              findings.append({"severity": "warn", "path": str(rel), "reason": f"code/script extension {suffix}"})
          elif suffix not in ALLOW_EXTENSIONS:
              findings.append({"severity": "warn", "path": str(rel), "reason": f"unknown extension {suffix or '<none>'}"})

          if executable:
              findings.append({"severity": "warn", "path": str(rel), "reason": "executable bit set"})

          if suffix == ".safetensors":
              safetensors += 1

          files.append({
              "path": str(rel),
              "size": path.stat().st_size,
              "sha256": sha256(path),
          })

    if safetensors == 0:
        findings.append({"severity": "deny", "path": ".", "reason": "no .safetensors files found"})

    denied = any(f["severity"] == "deny" for f in findings)
    return {
        "root": str(root),
        "status": "denied" if denied else "approved-with-warnings" if findings else "approved",
        "files": sorted(files, key=lambda f: f["path"]),
        "findings": findings,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("model_dir", type=Path)
    parser.add_argument("--json", action="store_true", help="emit JSON only")
    args = parser.parse_args()

    result = scan(args.model_dir)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if result["status"] == "denied" else 0


if __name__ == "__main__":
    raise SystemExit(main())
