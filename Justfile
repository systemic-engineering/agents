# Template Justfile for systemic-engineer projects.
# Copy to your project and trim to what's relevant.
# Canonical source: systemic-engineer/agents/Justfile

# ── Variables ────────────────────────────────────────────────────────────────

GLUE_BIN     := env_var_or_default("GLUE_BIN",        x'~/.local/libexec/glue/bin/glue')
GLUE_CHANNEL := env_var_or_default("GLUE_CHANNEL", "channel-unknown")
GLUE_WORKER  := env_var_or_default("GLUE_WORKER",  "worker-unknown")

# List all commands
default:
    @just --list

# ── Dependencies ────────────────────────────────────────────────────────────

# Fetch dependencies (Elixir projects)
deps:
    mix deps.get
    mix2nix > deps.nix

# Fetch deps without regenerating deps.nix
deps-get:
    mix deps.get

# Compile the project
compile:
    mix compile

# ── Quality ─────────────────────────────────────────────────────────────────

# Run tests
test:
    mix test

# Run only tests affected by recent changes
test-stale:
    mix test --stale

# Check test coverage
coverage:
    mix coveralls

# Generate HTML coverage report
coverage-html:
    mix coveralls.html

# Run linter
lint:
    mix credo --strict

# Format code
format:
    mix format

# Run all quality checks
check:
    mix check

# ── Build / Release ──────────────────────────────────────────────────────────

# Build production release (Elixir)
release:
    MIX_ENV=prod mix release --overwrite

# ── Daemon ───────────────────────────────────────────────────────────────────

# Start the glue daemon in the background
daemon-start:
    {{GLUE_BIN}} daemon

# Stop the glue daemon
daemon-stop:
    {{GLUE_BIN}} stop

# Stop, rebuild, and restart the daemon
daemon-rebuild: release daemon-stop
    sleep 2
    {{GLUE_BIN}} daemon

# ── Glue bus ─────────────────────────────────────────────────────────────────
#
# Usage (from within the nix devshell or with GLUE_BIN / GLUE_CHANNEL / GLUE_WORKER set):
#
#   just glue-status
#   just glue-init  :supervisor
#   just glue-chat  "message"
#   just glue-dm    TARGET "message"
#
# Override channel/worker inline:
#   just glue-chat "message" channel=my-channel worker=my-worker

# Check whether the glue daemon is reachable
glue-status:
    @{{GLUE_BIN}} rpc "IO.puts(node())" 2>/dev/null && echo "glue: up" || echo "glue: unreachable"

# Announce worker presence (init event). ROLE: :worker | :supervisor | :observer
glue-init role channel=GLUE_CHANNEL worker=GLUE_WORKER:
    @{{GLUE_BIN}} rpc "Glue.Dispatch.dispatch(Glue.Events.init(Glue.Channel.new(\"{{channel}}\"), Glue.Worker.new(\"{{worker}}\"), {{role}}, DateTime.utc_now()))" 2>/dev/null || true

# Broadcast a chatter message to all bus members
glue-chat msg channel=GLUE_CHANNEL worker=GLUE_WORKER:
    @{{GLUE_BIN}} rpc "Glue.Dispatch.dispatch(Glue.Events.chatter(Glue.Channel.new(\"{{channel}}\"), Glue.Worker.new(\"{{worker}}\"), Glue.Message.new(\"{{msg}}\"), DateTime.utc_now()))" 2>/dev/null || true

# Send a direct message to a specific worker
glue-dm target msg channel=GLUE_CHANNEL worker=GLUE_WORKER:
    @{{GLUE_BIN}} rpc "Glue.Dispatch.send_to(Glue.Worker.new(\"{{target}}\"), Glue.Events.dm(Glue.Channel.new(\"{{channel}}\"), Glue.Worker.new(\"{{worker}}\"), Glue.Worker.new(\"{{target}}\"), Glue.Message.new(\"{{msg}}\"), DateTime.utc_now()))" 2>/dev/null || true

# Tail the glue event log (set GLUE_EVENT_LOG in env)
glue-recv:
    tail -f "${GLUE_EVENT_LOG:-/tmp/glue-events.log}"

# ── Hooks ────────────────────────────────────────────────────────────────────

# Pre-commit gate: called by commit-msg hook. Stash isolation handled by the hook.
pre-commit: check

# Pre-push gate: called by pre-push hook. Enforce 100% coverage.
pre-push: coverage

# ── Secrets ──────────────────────────────────────────────────────────────────

# Start IEx with secrets loaded
iex:
    sops exec-env secrets.sops.yaml 'iex -S mix'

# ── Worktrees ────────────────────────────────────────────────────────────────

# Supervisor: create a dedicated worktree for a worker branch.
# Prints the worktree path on success — capture it to hand to the worker.
# Usage: just spawn-worktree feature/auth
#        just spawn-worktree feature/auth some-other-base
spawn-worktree branch base="main":
    #!/usr/bin/env bash
    set -euo pipefail
    repo=$(git rev-parse --show-toplevel)
    name=$(echo "{{branch}}" | sed 's|.*/||; s|[^a-zA-Z0-9]|-|g')
    path="$(dirname "$repo")/$(basename "$repo")-${name}"
    existing=$(git worktree list | awk -v b="[{{branch}}]" '$3 == b {print $1}')
    if [ -n "$existing" ]; then
      echo "worktree already exists: $existing" >&2
      echo "$existing"
      exit 0
    fi
    if git branch --list "{{branch}}" | grep -q .; then
      git worktree add "$path" "{{branch}}"
    else
      git worktree add -b "{{branch}}" "$path" "{{base}}"
    fi
    echo "$path"

# Supervisor: remove a worker worktree after the branch is merged.
# Usage: just remove-worktree feature/auth
remove-worktree branch:
    #!/usr/bin/env bash
    set -euo pipefail
    path=$(git worktree list | awk -v b="[{{branch}}]" '$3 == b {print $1}')
    if [ -z "$path" ]; then
      echo "no worktree found for branch {{branch}}" >&2
      exit 1
    fi
    git worktree remove "$path"
    echo "✓ removed: $path"

# ── Hooks installation ───────────────────────────────────────────────────────

# Install canonical hooks from systemic-engineer/agents
install-hooks:
    #!/usr/bin/env bash
    BASE="https://raw.githubusercontent.com/systemic-engineer/agents/main/hooks"
    curl -s -o .git/hooks/commit-msg "$BASE/commit-msg"
    curl -s -o .git/hooks/pre-push "$BASE/pre-push"
    chmod +x .git/hooks/commit-msg .git/hooks/pre-push
    echo "✓ Hooks installed from systemic-engineer/agents"
