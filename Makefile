SHELL := /bin/bash

.EXPORT_ALL_VARIABLES:

.PHONY: help check setup setup-dmg install-dmg install-service install-service-dmg uninstall-service verify verify-dmg run run-dmg run-foreground run-dmg-foreground start status gui copy-api-key hf-download qwen3-retrieval-download promote-model smoke audit-root test-server stop teardown teardown-plan clean-local validate

help:
	@printf '%s\n' \
		'Targets:' \
		'  make setup        Full first-slice setup: user, dirs, profile, install, verify, smoke' \
		'  make setup-dmg    Same setup, but installs oMLX.app from a local DMG' \
		'  make run          Install/start the source LaunchDaemon under Seatbelt' \
		'  make run-dmg      Install/start the DMG LaunchDaemon under Seatbelt' \
		'  make start        Start the installed LaunchDaemon' \
		'  make status       Show LaunchDaemon and oMLX process status' \
		'  make gui          Open the sandboxed oMLX web admin UI' \
		'  make copy-api-key Copy the sandbox API key to the console user clipboard' \
		'  make hf-download REPO=org/model [REVISION=main] Download to quarantine and scan' \
		'  make qwen3-retrieval-download [SIZES="0.6B 8B"] [KINDS="embedding reranker"]' \
		'  make promote-model CANDIDATE=/Users/Shared/... Promote a scanned quarantine model' \
		'  make run-foreground      Debug: run source oMLX in foreground with sudo wrapper' \
		'  make run-dmg-foreground  Debug: run DMG oMLX in foreground with sudo wrapper' \
		'  make audit-root   Check service user, sudo, setuid, and argv hardening' \
		'  make test-server  Test auth and /v1/models against the running server' \
		'  make stop         Stop running oMLX processes owned by the service user' \
		'  make uninstall-service   Remove the LaunchDaemon plist' \
		'  make teardown     Destructive: stop server, remove /Users/Shared tree, delete user/group' \
		'  make teardown-plan Preview teardown without deleting anything' \
		'  make validate     Shell/Python syntax checks for this control repo' \
		'' \
		'Optional overrides: OMLX_PORT=18000 OMLX_VERSION=v0.3.8 DMG=/path/to/oMLX.dmg'

check:
	@scripts/00-check-host.sh

validate:
	@bash -n scripts/*.sh
	@python3 -m py_compile scripts/*.py

setup: validate check
	@sudo -v
	@sudo APPLY=1 scripts/10-create-service-user.sh
	@sudo scripts/11-harden-service-user.sh
	@sudo scripts/20-bootstrap-layout.sh
	@sudo scripts/render-sandbox-profile.sh
	@sudo scripts/50-smoke-sandbox.sh
	@sudo scripts/30-install-omlx-source.sh
	@sudo scripts/32-freeze-source-runtime.sh
	@sudo scripts/35-verify-install.sh
	@sudo env RUNTIME=source scripts/70-install-launchd-service.sh
	@printf '\nSetup complete. Start the server with: make run\n'

setup-dmg: validate check
	@sudo -v
	@sudo APPLY=1 scripts/10-create-service-user.sh
	@sudo scripts/11-harden-service-user.sh
	@sudo scripts/20-bootstrap-layout.sh
	@sudo scripts/render-sandbox-profile.sh
	@sudo scripts/50-smoke-sandbox.sh
	@sudo env DMG="$(DMG)" scripts/31-install-omlx-dmg.sh
	@sudo scripts/36-verify-dmg-install.sh
	@sudo env RUNTIME=dmg scripts/70-install-launchd-service.sh
	@printf '\nDMG setup complete. Start the server with: make run-dmg\n'

install-dmg:
	@sudo env DMG="$(DMG)" scripts/31-install-omlx-dmg.sh

install-service:
	@sudo env RUNTIME=source scripts/70-install-launchd-service.sh

install-service-dmg:
	@sudo env RUNTIME=dmg scripts/70-install-launchd-service.sh

uninstall-service:
	@sudo scripts/75-uninstall-launchd-service.sh

verify:
	@sudo scripts/35-verify-install.sh
	@sudo scripts/50-smoke-sandbox.sh

verify-dmg:
	@sudo scripts/36-verify-dmg-install.sh
	@sudo scripts/50-smoke-sandbox.sh

run:
	@sudo scripts/80-stop-server.sh
	@sudo env RUNTIME=source scripts/70-install-launchd-service.sh
	@sudo scripts/71-start-launchd-service.sh

run-dmg:
	@sudo scripts/80-stop-server.sh
	@sudo env RUNTIME=dmg scripts/70-install-launchd-service.sh
	@sudo scripts/71-start-launchd-service.sh

run-foreground:
	@sudo scripts/40-run-omlx-seatbelt.sh

run-dmg-foreground:
	@sudo scripts/41-run-omlx-dmg-seatbelt.sh

start:
	@sudo scripts/71-start-launchd-service.sh

status:
	@sudo scripts/72-status-launchd-service.sh

gui:
	@scripts/62-open-admin.sh

copy-api-key:
	@sudo scripts/63-copy-api-key.sh

hf-download:
	@test -n "$(REPO)" || { echo 'usage: make hf-download REPO=org/model [REVISION=main] [NAME=local-name]' >&2; exit 2; }
	@sudo env REPO="$(REPO)" REVISION="$(REVISION)" NAME="$(NAME)" HF_TOKEN_FILE="$(HF_TOKEN_FILE)" scripts/64-hf-download-to-quarantine.sh

qwen3-retrieval-download:
	@sudo env SIZES="$(SIZES)" KINDS="$(KINDS)" HF_TOKEN_FILE="$(HF_TOKEN_FILE)" scripts/65-download-qwen3-retrieval.sh

promote-model:
	@test -n "$(CANDIDATE)" || { echo 'usage: make promote-model CANDIDATE=/Users/Shared/omlx-sandbox/models-quarantine/name' >&2; exit 2; }
	@sudo env ALLOW_WARNINGS="$(ALLOW_WARNINGS)" scripts/promote-model.sh "$(CANDIDATE)"

smoke:
	@sudo scripts/50-smoke-sandbox.sh

audit-root:
	@sudo scripts/55-audit-root-escape.sh

test-server:
	@sudo scripts/60-test-server.sh

stop:
	@sudo scripts/80-stop-server.sh

teardown:
	@sudo YES=1 scripts/90-teardown.sh

teardown-plan:
	@sudo scripts/90-teardown.sh

clean-local:
	@find scripts -type d -name __pycache__ -prune -exec rm -rf {} +
