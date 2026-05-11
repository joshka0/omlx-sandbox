# oMLX Sandbox

Local control plane for testing oMLX with a hostile-model threat model.

The goal is not to containerize the Metal worker. oMLX/MLX needs native macOS
Metal access for useful performance. The goal is to keep untrusted model
artifacts and the serving process away from normal user data, secrets, and
unbounded network access.

Start with the plan:

```sh
less docs/plan.md
```

First-slice setup is a single make target:

```sh
make setup
make run
```

Then open the sandboxed web admin UI:

```sh
make gui
make copy-api-key
```

`make gui` opens `http://127.0.0.1:18000/admin`, served by the sandboxed
`omlxsvc` process. `make copy-api-key` copies the generated API key to the
logged-in user's clipboard for the admin login screen.

`make run` uses a LaunchDaemon. The control command uses `sudo` to install and
start the service, but the long-running oMLX process is launched by `launchd`
directly as `omlxsvc` under the Seatbelt profile. Foreground runs are kept only
for debugging:

```sh
make run-foreground
```

To use the signed DMG instead of the source checkout, install the app bundle
into the sandbox and run only its CLI entrypoint:

```sh
make setup-dmg
make run-dmg
```

`setup-dmg` auto-detects the newest `~/Downloads/oMLX-*.dmg` for the sudo
invoking user. Override it when needed:

```sh
make setup-dmg DMG=/path/to/oMLX.dmg
```

This harness deliberately does not launch the native menu-bar GUI app for the
untrusted runtime. A normal GUI app would run in the logged-in Aqua session and
needs WindowServer, LaunchServices, update, and user-home surfaces. Use the web
admin UI for this sandbox unless you intentionally move GUI testing into a
separate macOS account or VM.

With the server running, verify from another terminal:

```sh
make test-server
make audit-root
make status
```

Tear down all sandbox state, including the service user and group:

```sh
make teardown
```

Do not point oMLX at arbitrary downloaded model repositories. Put candidate
models in the quarantine directory, scan them, then promote only approved
artifacts into the approved model directory.

Hugging Face browsing/downloading from inside the oMLX admin UI is expected to
fail in the hardened profile because the daemon has no outbound network. Use
the host-side intake path instead:

```sh
make hf-download REPO=mlx-community/Llama-3.2-1B-Instruct-4bit REVISION=main
make promote-model CANDIDATE=/Users/Shared/omlx-sandbox/models-quarantine/<candidate>
make run
```

The downloader resolves `REVISION` to an immutable Hugging Face commit SHA,
saves that source metadata in quarantine, scans the files, and only promotes
approved artifacts into the runtime-visible model directory.

For the pinned Qwen3 embedding/reranker set:

```sh
make qwen3-retrieval-download
```

That downloads these exact pinned revisions into quarantine:

- `Qwen/Qwen3-Embedding-0.6B`
- `Qwen/Qwen3-Embedding-8B`
- `Qwen/Qwen3-Reranker-0.6B`
- `Qwen/Qwen3-Reranker-8B`

Start with the smaller pair when testing the flow:

```sh
make qwen3-retrieval-download SIZES=0.6B
```
