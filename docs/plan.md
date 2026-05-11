# oMLX Sandbox Plan

## Objective

Run oMLX safely enough to test untrusted or not-yet-trusted local model
artifacts without exposing the normal user account, local secrets, broad home
directory contents, or unrestricted network access.

This plan assumes oMLX itself must run as a native macOS process so MLX can use
Metal. Containers remain useful for the model intake pipeline and proxy layer,
but not as the GPU worker boundary.

## Threat Model

In scope:

- Malicious or compromised model repository contents.
- Unsafe model formats such as pickle-backed `.bin`, `.pt`, `.pth`, `.pkl`, and
  `.pickle`.
- Hugging Face repos that require `trust_remote_code`.
- Accidental model downloads or update checks from the serving process.
- Attempts to read user secrets such as SSH keys, cloud credentials, tokens,
  shell history, and project directories.
- Writes outside explicit model, cache, log, temp, and state directories.
- Local API abuse by another process on the Mac.
- Runaway memory, concurrency, or disk cache growth.

Out of scope for the first slice:

- Kernel or Metal driver compromise.
- Full isolation from all host-side macOS services.
- Production-grade notarized App Sandbox packaging.
- Running oMLX GPU inference inside Docker or OrbStack.

## Target Architecture

```text
quarantine downloader/scanner
  -> approved model store
  -> native macOS oMLX process under service user + Seatbelt
  -> local gateway/proxy
  -> clients
```

## Phase 1: First Slice

Goal: get a constrained host-native oMLX process runnable without global
installation.

Deliverables:

- Dedicated hidden macOS service user.
- Dedicated state tree under `/Users/Shared/omlx-sandbox`.
- Source install pinned to `v0.3.8`.
- Optional signed-DMG runtime path that copies `oMLX.app` into the sandbox and
  runs only its CLI entrypoint.
- Local venv and managed Python under the sandbox base.
- Seatbelt profile generated from a path template.
- Root-owned Seatbelt policy directory so `omlxsvc` cannot loosen the next
  launch profile.
- LaunchDaemon installed as `root:wheel` with `UserName=omlxsvc` and
  `GroupName=_omlxsvc` so the long-running server has no root sudo wrapper.
- oMLX bound to `127.0.0.1` on a non-default port with an API key.
- No MCP, no tool execution, and no model download path in the runtime command.
- Smoke tests that verify read denial and outbound network denial.

Acceptance checks:

- oMLX cannot read the normal user's `~/.ssh`, `~/.aws`, `~/.config`, or repos.
- oMLX can read only approved model files.
- oMLX can write only cache, logs, tmp, run, state, and its service home.
- oMLX binds only localhost.
- oMLX outbound internet fails from inside the sandbox.
- oMLX outbound localhost fails from inside the sandbox so it cannot probe
  local privileged services.
- API calls require the generated local key.
- The service user is not `admin`, `staff`, `wheel`, or `_lpadmin`.
- The service user has no non-interactive `sudo` path.
- No setuid or setgid files exist under the sandbox base.
- The API key is not present in process arguments.
- Signed DMG app bundles copied into the sandbox are root-owned and read-only
  to the service user.
- Source installs are frozen root-owned/read-only after installation so the
  service user cannot persist by modifying the executable runtime.

DMG constraint:

- Do not launch the menubar GUI app as the sandboxed runtime. Treat the DMG as
  a signed app bundle artifact, copy it read-only under the sandbox base, and
  execute `Contents/MacOS/omlx-cli` as `omlxsvc` under Seatbelt.
- Use oMLX's web admin dashboard at `/admin` as the GUI for this sandbox. The
  browser runs as the logged-in user, but the model runtime, downloads, cache,
  and approved model directory remain inside the sandboxed daemon.

Root-escape constraint:

- We cannot prove absolute impossibility against kernel, Seatbelt, or Metal
  driver vulnerabilities. The enforced guarantee is that model/runtime code is
  never intentionally granted root, sudo, writable privileged files, or a
  privileged helper API.

## Phase 2: Model Intake

Goal: make model approval a separate, auditable path.

Deliverables:

- Quarantine directory for downloaded candidates.
- Scanner that rejects unsafe file extensions, symlink escapes, executables, and
  custom code by default.
- Manifest with source, pinned revision, file hashes, and scan verdict.
- Host-side Hugging Face downloader that resolves requested revisions to
  immutable commit SHAs, stores metadata, and scans before promotion.
- Promotion command that copies approved artifacts into the approved model
  store.

Policy:

- Pin every model source to an immutable revision.
- Reject pickle-style formats by default.
- Reject `trust_remote_code` by default.
- Prefer `.safetensors` plus plain tokenizer/config files.
- Do not let the oMLX serving process download models.

## Phase 3: Runtime Hardening

Goal: reduce the service boundary after the first working run.

Deliverables:

- Narrower Seatbelt profile based on observed denials.
- Explicit allowlist of required Mach services and IOKit classes if practical.
- LaunchDaemon or supervised user service with deterministic environment.
- Log rotation and cache size guard.
- Memory/concurrency settings checked into config.

Open question:

- MLX/Metal may require broad Mach lookup and IOKit access. If so, document the
  exact reason and keep the rest of the sandbox tight.

## Phase 4: Gateway

Goal: expose only the client API surface we actually want.

Deliverables:

- Containerized localhost gateway.
- API key verification at the gateway.
- Route allowlist for `/v1/models`, `/v1/chat/completions`, `/v1/messages`, and
  later `/v1/responses` if needed.
- Block admin and management endpoints from the gateway.
- Request size, concurrency, and timeout limits.
- Optional prompt logging disabled by default.

## Phase 5: Network Containment

Goal: make outbound denial independent of the Seatbelt profile.

Deliverables:

- `pf` or firewall rule set for the service user or launch context.
- Explicit localhost-only allowance.
- Verification command that proves external TCP and DNS fail from the service
  account.

## Phase 6: Durable macOS Sandbox

Goal: replace the deprecated CLI sandbox wrapper if this becomes permanent.

Deliverables:

- Small signed macOS launcher/helper.
- App Sandbox entitlements with only local network server access and file access
  to the sandbox base.
- Hardened Runtime enabled.
- Same intake and gateway model preserved.

## Phase 7: VM Evaluation

Goal: evaluate stronger isolation only if Seatbelt plus intake is not enough.

Deliverables:

- macOS VM experiment with MLX/Metal smoke benchmarks.
- Comparison against host-native oMLX.
- Decision record on whether the isolation gain is worth performance and
  operational complexity.
