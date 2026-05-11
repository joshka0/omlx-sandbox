#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sizes="${SIZES:-0.6B 8B}"
kinds="${KINDS:-embedding reranker}"

repo_for() {
  case "$1:$2" in
    embedding:0.6B) printf '%s\n' "Qwen/Qwen3-Embedding-0.6B" ;;
    embedding:8B) printf '%s\n' "Qwen/Qwen3-Embedding-8B" ;;
    reranker:0.6B) printf '%s\n' "Qwen/Qwen3-Reranker-0.6B" ;;
    reranker:8B) printf '%s\n' "Qwen/Qwen3-Reranker-8B" ;;
    *) return 1 ;;
  esac
}

revision_for() {
  case "$1:$2" in
    embedding:0.6B) printf '%s\n' "97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3" ;;
    embedding:8B) printf '%s\n' "1d8ad4ca9b3dd8059ad90a75d4983776a23d44af" ;;
    reranker:0.6B) printf '%s\n' "e61197ed45024b0ed8a2d74b80b4d909f1255473" ;;
    reranker:8B) printf '%s\n' "77d193c791ed757ca307ee72715aa132723da912" ;;
    *) return 1 ;;
  esac
}

for kind in ${kinds}; do
  case "${kind}" in
    embedding|reranker) ;;
    *)
      echo "ERROR: unsupported KINDS entry '${kind}' (expected embedding or reranker)" >&2
      exit 2
      ;;
  esac

  for size in ${sizes}; do
    case "${size}" in
      0.6B|8B) ;;
      *)
        echo "ERROR: unsupported SIZES entry '${size}' (expected 0.6B or 8B)" >&2
        exit 2
        ;;
    esac

    repo="$(repo_for "${kind}" "${size}")"
    revision="$(revision_for "${kind}" "${size}")"
    name="qwen3-${kind}-${size}"

    echo
    echo "== ${repo} @ ${revision} =="
    env REPO="${repo}" REVISION="${revision}" NAME="${name}" HF_TOKEN_FILE="${HF_TOKEN_FILE:-}" \
      "${SCRIPT_DIR}/64-hf-download-to-quarantine.sh"
  done
done
