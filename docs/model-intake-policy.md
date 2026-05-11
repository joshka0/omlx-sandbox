# Model Intake Policy

Use this policy before any model directory is visible to the oMLX runtime.

## Default Decision

Unreviewed model artifacts are denied. A model becomes eligible for serving only
after it has:

- a pinned source repository and revision,
- a generated manifest with file hashes,
- no denied file types,
- no symlink escapes,
- no executable payloads that require review,
- no `trust_remote_code` requirement,
- at least one `.safetensors` file.

## Denied By Default

The scanner fails on:

- `.bin`
- `.ckpt`
- `.dylib`
- `.egg`
- `.exe`
- `.pkl`
- `.pickle`
- `.pt`
- `.pth`
- `.pyc`
- `.so`
- `.whl`
- symlinks
- directories with no `.safetensors`

## Review Required

The scanner warns on source or script files:

- `.py`
- `.sh`
- `.zsh`
- `.fish`
- `.js`
- `.mjs`
- `.rb`
- `.ps1`
- executable bits
- unknown extensions

Warnings do not automatically fail because some tokenizer/model repos include
plain text templates with unusual suffixes. Promotion should still stop until a
human reviews each warning.

## Promotion Rule

Only copy from quarantine to approved storage after scanner output is saved next
to the candidate as a manifest. Do not promote with `mv`; keep quarantine
evidence intact until the model is no longer needed.

## Hugging Face Intake

Do not use the oMLX daemon to fetch from Hugging Face in the hardened runtime
profile. The daemon is offline by design.

Use the control-plane downloader:

```sh
make hf-download REPO=org/model REVISION=main
```

The downloader resolves the requested revision to an immutable Hugging Face
commit SHA, stores source metadata in `omlx-source.json`, downloads only the
default allowlisted model/config/tokenizer files, and runs the scanner before
printing the promotion command.

Use `ALLOW_PATTERNS` and `IGNORE_PATTERNS` only for explicit review cases:

```sh
make hf-download REPO=org/model REVISION=<commit> ALLOW_PATTERNS='*.safetensors,*.json,*.txt'
```

## Pinned Qwen3 Retrieval Set

The convenience target downloads the official Qwen3 embedding and reranker
models requested for this sandbox:

```sh
make qwen3-retrieval-download
```

Pinned inputs:

| Purpose | Size | Repo | Revision |
| --- | --- | --- | --- |
| Embedding | 0.6B | `Qwen/Qwen3-Embedding-0.6B` | `97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3` |
| Embedding | 8B | `Qwen/Qwen3-Embedding-8B` | `1d8ad4ca9b3dd8059ad90a75d4983776a23d44af` |
| Reranker | 0.6B | `Qwen/Qwen3-Reranker-0.6B` | `e61197ed45024b0ed8a2d74b80b4d909f1255473` |
| Reranker | 8B | `Qwen/Qwen3-Reranker-8B` | `77d193c791ed757ca307ee72715aa132723da912` |

Use `SIZES=0.6B` to test the smaller embedding/reranker pair before pulling
the 8B weights:

```sh
make qwen3-retrieval-download SIZES=0.6B
```
