# Agent Coordination — Read This First

You are reading this because you are an agent operating in a `systemic-engineer` context.
This repo is your canonical reference. Read it before reading anything else in the project.

---

## What This Repo Is

Global defaults and conventions for all agents operating under `systemic-engineer`. Think of it
as a shared brain stem — project-specific config layers on top, but the baseline lives here.

---

## Boot Sequence

1. **Role detection** — are you a supervisor or a worker? See [.obc/SUPERVISOR.md](.obc/SUPERVISOR.md)
   or [.obc/WORKER.md](.obc/WORKER.md).
2. **OBC config** — read [.obc/config.dhall](.obc/config.dhall) for canonical defaults.
   Then check for a local `.obc/config.dhall` in the project repo and apply overrides.
3. **Hooks** — if the project doesn't have them installed, copy from `hooks/` to `.git/hooks/`.
4. **Justfile** — if the project doesn't have one, use the template at `Justfile` as a starting point.
5. **Environment** — `agent.nix` defines the reproducible dev shell. Activate before running
   build commands.

---

## Role Detection

**Supervisor** — you were invoked by a launchd/systemd maintenance loop or by a human directly.
Your job: read task context, spawn workers, integrate outputs, open PRs, surface decisions.
→ Read [.obc/SUPERVISOR.md](.obc/SUPERVISOR.md)

**Worker** — you were spawned by a supervisor with a bounded task description.
Your job: execute the assigned subtask, emit chatter events, complete or escalate.
→ Read [.obc/WORKER.md](.obc/WORKER.md)

If unclear: ask via `Agent_Question` before proceeding.

---

## OBC Config

The canonical config lives at `.obc/config.dhall` in this repo. It defines:
- Default budget conditions (what gates action)
- Observable categories (what to watch)
- Cascade defaults (what happens when a budget is exceeded)

**Local override protocol:**

```
systemic-engineer/agents/.obc/config.dhall  ← canonical (this repo)
<project-repo>/.obc/config.dhall            ← local overrides (wins on conflict)
```

The local file may extend or override any field. It does not need to repeat unchanged defaults.

---

## Git Hooks

Two hooks live in `hooks/`. They enforce TDD cycle discipline and coverage at every project.

**Installation (any project):**
```sh
cp hooks/commit-msg .git/hooks/commit-msg
cp hooks/pre-push   .git/hooks/pre-push
chmod +x .git/hooks/commit-msg .git/hooks/pre-push
```

**What they enforce:**

`commit-msg`:
- Every commit subject must carry exactly one TDD phase marker: 🔴 🟢 ♻️ 🔀
- 🔴 must be immediately followed by 🟢 — no skipping to refactor
- Runs `just pre-commit` against staged changes to validate the declared phase

`pre-push`:
- Runs `just pre-push` before any push
- Typically enforces 100% test coverage via `mix coveralls`
- Skips gracefully if the project has no `just pre-push` recipe

**Note:** If the project uses Nix home-manager (`programs.git.hooks`), these hooks are already
wired globally — no manual installation needed.

---

## Justfile

`Justfile` in this repo is a template. Copy it to a new project and trim to what's relevant.

Standard recipes every project should have:
```
pre-commit   — the gate the commit-msg hook calls
pre-push     — the gate the pre-push hook calls
check        — full quality suite (tests + coverage + format + lint)
deps         — fetch + pin dependencies
```

---

## Environment

This repo is a flake. Named devShells per stack — no need to bring your own Nix config.

```sh
# Minimal base: git, just, sops, jq, dhall, gnupg
nix develop github:systemic-engineer/agents

# Elixir 1.18 / OTP 27 + base tools
nix develop github:systemic-engineer/agents#elixir
```

For project-specific deps (pinned Hex packages, etc.), use the project's own `flake.nix` instead.
The canonical environments here are for agent invocations where the project has no flake.

---

## Chatter Protocol

Communicate with your supervisor via these observable types:

| Observable         | When                                        | Supervisor action           |
|--------------------|---------------------------------------------|-----------------------------|
| `Agent_Chatter`    | Working — ambient context, progress notes   | Passive read                |
| `Agent_Question`   | Uncertain — can wait for guidance           | Resolve or escalate         |
| `Agent_Blocker`    | Stopped — cannot proceed without input      | Unblock or reassign         |
| `Agent_Decision`   | At a consequential threshold, needs sign-off| Approve, redirect, escalate |

Emit via `Reed.Events.Dispatcher.dispatch/1` if body is running. Otherwise log to stdout with
a structured prefix: `[CHATTER]`, `[QUESTION]`, `[BLOCKER]`, `[DECISION]`.

---

## What You Should Not Do

- Write to `visibility/private/` — ever. Explicit consent required.
- Commit without a TDD phase marker.
- Push without passing coverage.
- Spawn sub-agents without a task description complete enough to run autonomously.
- Hold permanent credentials — get a scoped lease from the supervisor.

---

## Invariants

These hold regardless of task:

- OBC pipelines are the judgment. You are the executor.
- Workers hold leases, not credentials.
- The chatter protocol is the only coordination surface between workers and supervisor.
- `just check` runs before every commit.
- Body stays protected.
