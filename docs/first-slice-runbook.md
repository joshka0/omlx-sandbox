# First Slice Runbook

## Verified So Far

- Host has `git`, `uv`, `sandbox-exec`, Python, and arm64 macOS.
- Hidden user `omlxsvc` exists.
- `/Users/Shared/omlx-sandbox` directory tree exists.
- Seatbelt template applies in this shell.
- Seatbelt template denies reads of `/Users/joshka/.ssh`.
- Seatbelt template denies outbound TCP to `1.1.1.1:443`.
- Seatbelt template allows writes only under the configured writable runtime
  paths in the test base.
- Model scanner approves a minimal `.safetensors` model directory and denies a
  pickle-style `.bin` model directory.

## Next Root Commands

Run the full first-slice setup from the control repo:

```sh
cd /Users/joshka/repos/personal/omlx-sandbox
make setup
```

`11-harden-service-user.sh` avoids password/authentication mutations by
default because macOS may prompt for an extra user-administration authorization.
The account is still hidden, has `/usr/bin/false` as its shell, and uses
`/var/empty` as its home. If you explicitly want the additional login-lock
mutation, run `sudo LOCK_LOGIN=1 scripts/11-harden-service-user.sh`.

Then start oMLX:

```sh
make run
```

In another terminal:

```sh
cd /Users/joshka/repos/personal/omlx-sandbox
make test-server
```

Equivalent make targets:

```sh
make run
make status
make test-server
make stop
```

`make run` installs and starts a system LaunchDaemon. That still uses `sudo` for
the control-plane action, but the daemon itself is configured with:

```text
UserName = omlxsvc
GroupName = _omlxsvc
ProgramArguments = /usr/bin/sandbox-exec -f ... omlx serve --base-path ...
```

So the long-running process is launched by `launchd` as `omlxsvc`; there is no
root `sudo -u` wrapper left in the parent chain. Use foreground mode only for
debugging:

```sh
make run-foreground
```

Audit the root-escalation controls after setup and after any runtime change:

```sh
make audit-root
```

The audit checks that `omlxsvc` is not in privileged groups, cannot use sudo
non-interactively, has no setuid/setgid files under the sandbox base, and does
not expose the API key in process arguments. A foreground debug run may leave a
root `sudo` monitor in the parent chain; that is a debugging convenience, not a
privilege held by the oMLX Python process.

## Using The Admin GUI

Use the web admin UI served by the sandboxed oMLX daemon:

```sh
make gui
```

That opens:

```text
http://127.0.0.1:18000/admin
```

The admin page is protected by the same sandbox API key used for client
requests. Copy it to the logged-in user's clipboard when the login screen asks
for it:

```sh
make copy-api-key
```

This keeps model serving, downloads, cache writes, and model management inside
the `omlxsvc` Seatbelt profile. The browser is only a client to localhost.

The admin UI's Hugging Face scout/download features are expected to fail in the
hardened profile. The serving daemon has no DNS or outbound internet access.
Use host-side intake instead:

```sh
make hf-download REPO=mlx-community/Llama-3.2-1B-Instruct-4bit REVISION=main
```

That command downloads as `omlxsvc` outside the Seatbelt runtime profile, into:

```text
/Users/Shared/omlx-sandbox/models-quarantine
```

It records the resolved immutable Hugging Face revision and writes a scanner
manifest. Promote only after reviewing any warnings:

```sh
make promote-model CANDIDATE=/Users/Shared/omlx-sandbox/models-quarantine/<candidate>
make run
```

For the pinned Qwen3 embedding/reranker set:

```sh
make qwen3-retrieval-download
```

Start with the smaller pair if you want to verify oMLX detection and endpoints
before downloading the 8B weights:

```sh
make qwen3-retrieval-download SIZES=0.6B
```

After each candidate is approved, promote it using the command printed by the
downloader, then restart the service:

```sh
make run
make test-server
```

## Running From The DMG

The DMG path does not launch the GUI app with Finder or `open`. That would run
in the logged-in GUI session and would require broad WindowServer,
LaunchServices, update, and user-home access. Instead, copy the signed
`oMLX.app` bundle into the sandbox and run `Contents/MacOS/omlx-cli` under the
same `omlxsvc` and Seatbelt profile:

```sh
make setup-dmg
make run-dmg
```

The installer auto-detects the newest `~/Downloads/oMLX-*.dmg` for the user
that invoked sudo. To pin a specific file:

```sh
make setup-dmg DMG=/Users/joshka/Downloads/oMLX-0.3.7-macos26-tahoe.dmg
```

The installed bundle lives at:

```text
/Users/Shared/omlx-sandbox/app/oMLX.app
```

The local DMG observed during setup was `0.3.7`; the source install path is
pinned to `v0.3.8`. Use the DMG route when you specifically want to validate
the packaged signed runtime.

If you need the native menu-bar app specifically, do not run it as the sandboxed
runtime from this harness. Treat that as a separate trust mode: a separate
macOS user account at minimum, and a VM or separate host for hostile model
testing.

Teardown is a single destructive make target:

```sh
make teardown
```

Preview what teardown would remove:

```sh
make teardown-plan
```

## Expected Service Surface

- Host: `127.0.0.1`
- Port: `18000`
- Model dir: `/Users/Shared/omlx-sandbox/models-approved`
- Cache dir: `/Users/Shared/omlx-sandbox/cache`
- API key file: `/Users/Shared/omlx-sandbox/state/api-key`
