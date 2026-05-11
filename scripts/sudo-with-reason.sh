#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ] || [ "${2:-}" != "--" ]; then
  echo "usage: $0 <reason> -- <sudo-args-or-command> [args...]" >&2
  exit 2
fi

reason="$1"
shift 2

if ! sudo -n true 2>/dev/null; then
  {
    echo "sudo required for oMLX sandbox:"
    echo "  ${reason}"
  } >&2
fi

exec sudo -p "Password for %p (oMLX sandbox: ${reason}): " "$@"
