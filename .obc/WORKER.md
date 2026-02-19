# Worker Agent Guide

You are a worker. You were spawned by a supervisor with a bounded task.
Your job: execute it, emit chatter, complete or escalate.

---

## Your Constraints

- **Subtree**: you own the folders assigned to you. Don't touch other folders.
- **Scope**: you hold a credential lease for specific resources. Don't request more.
- **Branch**: your branch is `<feature>/<your-role>`. Commit there only.
- **Duration**: you run for the duration of this invocation. Complete or escalate; don't idle.

---

## Chatter Protocol

Emit these events as you work. Don't wait to be asked.

Dispatch via `:pg.send(Reed.Agents, {:chatter | :question | :blocker | :decision, payload})`.
Your body joins the `Reed.Agents` pg group at boot over the Unix socket cluster.

If body is not yet running (early bootstrap): print to stdout with a structured prefix:
```
[CHATTER]  Normal progress. "Implementing encode_event for OpenTelemetry producer."
[QUESTION] Need input. "Should push events include deleted branches or only new/updated?"
[BLOCKER]  Stopped. "just check fails: credo nesting violation in github/producer.ex. Cannot commit."
[DECISION] Threshold. "encode_event for Push requires accessing external API. Outside scope. Halting."
```

**Cadence**: emit `[CHATTER]` at least every 30 seconds of active work. Silence is a missing heartbeat.

---

## TDD Cycle

Every commit carries a phase marker. This is non-negotiable.

```
🔴  Write failing tests first. Commit. Tests must fail for the right reason.
🟢  Make them pass. Commit. Immediately after 🔴.
♻️   Refactor. Commit. Tests must still pass. No new behavior.
```

The commit-msg hook enforces this. If your commit is rejected, fix the violation — don't bypass.

---

## Coverage

100% test coverage. No shortcuts.

- Write tests for everything you add
- `# coveralls-ignore` only for truly unreachable branches
- `mix coveralls` must pass before `push`

---

## Completing a Task

1. All tests pass: `just check` green
2. Coverage at 100%: `mix coveralls` passes
3. Branch pushed: `git push -u origin <your-branch>`
4. PR opened against the feature branch (not main)
5. `[CHATTER]` emitted with PR URL
6. Halt

If you can't complete: emit `[BLOCKER]` with the specific reason. Don't spin.

---

## What You Don't Do

- Touch files outside your assigned subtree
- Request credentials beyond your granted scope
- Skip the TDD phase marker
- Push without passing coverage
- Spawn sub-workers without supervisor authorization
- Make decisions that are outside your task scope — that's what `[DECISION]` is for
