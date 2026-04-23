# Privacy

Emu watches your Claude Code session to do its job: runway tracking, drift detection, checkpointing, and dedup. Watching means reading. This page names **exactly** what Emu reads, what it stores, what it does *not* transmit, and how to verify each claim yourself.

## Principles

1. **Everything Emu does runs locally.** No cloud service, no phone-home, no telemetry.
2. **Nothing is transmitted off your machine.** Emu has no outbound network code. Every hook and script either writes to stdout (the conversation), to `~/.claude/fae/` (state), or to `stderr` (logs).
3. **You can verify every claim on this page.** The source is in this repo; the storage is on your disk; `grep` is enough.

## What Emu reads

| Surface | Read by | Why |
|---------|---------|-----|
| Every prompt you submit | `context-guard` PreToolUse / PostToolUse hooks | Runway estimation, drift detection, dedup. |
| Every tool-call output | `context-guard` PostToolUse hook | Compression of large outputs, drift scoring. |
| Turn-by-turn transcript | `context-guard` + `state-keeper` | Checkpoint content, entropy scoring. |
| File reads you or Claude initiate | Not read by Emu. | Emu does not re-read files. |
| Your git repo contents | Not read by Emu. | Emu has no git integration. |
| Environment variables | Not read, except those set by Claude Code itself. | Emu reads no process env beyond `CLAUDE_*`. |

Concretely: Emu reads the **contents of your conversation**, because that's what produces tokens. It does not read your source code, your git history, your SSH keys, your shell history, or anything else.

## What Emu stores

All state lives under `~/.claude/fae/` (or the Claude Code plugin state directory if you've customized it).

| File / dir | Contents | Lifetime |
|------------|----------|----------|
| `checkpoints/<session-id>.json` | Session goal, open decisions, next step, turn count, token budget. **No verbatim transcript.** | Until you delete it. |
| `runway/session.json` | Rolling runway estimate + recent turn sizes (integers, not content). | Overwritten each turn. |
| `drift/window.json` | Shannon-entropy scores per recent turn (floats, not content). | Sliding window, ~20 turns. |
| `dedup/cache.json` | Hashes of recent tool outputs to detect duplicates. | Per-session. |
| `logs/hooks.log` | Timestamp + event name + session id. **No content.** | Until you delete it. |

**Checkpoints are summary metadata**, not verbatim transcripts. If you want to verify: `cat ~/.claude/fae/checkpoints/*.json` — you'll see the shape; you won't see your prompts.

## What Emu does not transmit

Emu has **no outbound network code**. To verify:

```bash
# grep every shell hook and Python script for network invocations
grep -rE 'curl|wget|requests|urllib|httpx|socket|nc -' ~/.claude/plugins/fae-*/
grep -rE 'fetch\(|XMLHttpRequest|WebSocket' ~/.claude/plugins/fae-*/
```

Both should return zero matches.

If either returns a match, file a security report — that would be a P0 bug against this policy. See [SECURITY.md](SECURITY.md).

## What Emu does not do

- **No fingerprinting.** Emu does not compute stable identifiers across sessions.
- **No profiling of your code.** Emu does not read source files; it reads tool-call output, which is your call.
- **No inference.** Emu does not send your prompts to a model to get an embedding. Every score Emu computes is a local arithmetic operation on integers or hashes.
- **No ad-serving, no A/B testing.** Not a SaaS.

## Disabling specific behaviors

If you don't want Emu to keep checkpoints:

```jsonc
// .claude/settings.json
{
  "plugins": {
    "state-keeper": { "enabled": false }
  }
}
```

Same pattern for any sub-plugin. Disabling `context-guard` turns off runway + drift + dedup.

## Clearing all state

```bash
rm -rf ~/.claude/fae/
```

No side effects, no re-downloads, no "would you like to keep…" prompts. The next session starts clean.

## What to do if you suspect a leak

1. Check `~/.claude/fae/logs/hooks.log` for unexpected events.
2. Run the two `grep` commands above against the installed plugin directory.
3. If anything looks off, file a private security advisory — see [SECURITY.md](SECURITY.md).

## Governance

- The shared behavioral contract at [shared/conduct/hooks.md](shared/conduct/hooks.md) § Injection over denial forbids hooks from taking side effects on repo state (auto-commits, auto-renames). Emu's hooks adhere to this.
- Any change to what Emu stores or transmits requires an ADR in [docs/adr/](docs/adr/) before merge.
- The `CODEOWNERS` file routes privacy-relevant paths through the maintainer.

This page is binding. If behavior diverges from this document, the behavior is the bug.
