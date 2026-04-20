# Frequently asked questions

Quick answers to questions that don't yet have their own doc. For anything deeper, follow the links — the full answer usually lives in a neighboring file.

## What's the difference between Allay and the other siblings?

Allay answers *"what did I spend?"* — it watches your session's token economy: runway, drift, dedup, checkpoints. Sibling plugins answer different questions in the same session: Flux engineers prompts, Hornet watches change trust, Reaper scans for security surface, Weaver coordinates git workflow. All are independent installs; none require the others. See [docs/ecosystem.md](ecosystem.md) for the full map.

## Do I need the other siblings to use Allay?

No. Allay is self-contained — install `full@allay` and every command works standalone. The siblings compose if you install them, but nothing in Allay depends on another repo being present.

## How do I report a bug vs. ask a question vs. disclose a security issue?

- **Security vulnerability** — private advisory, never a public issue. See [SECURITY.md](../SECURITY.md).
- **Reproducible bug** — a bug report issue with repro steps + exact versions.
- **Usage question or half-formed idea** — [Discussions](https://github.com/enchanted-plugins/allay/discussions).

The [SUPPORT.md](../SUPPORT.md) page has the exact links for each.

## Is Allay an official Anthropic product?

No. Allay is an independent open-source plugin for [Claude Code](https://github.com/anthropics/claude-code) (Anthropic's CLI). It's published by [enchanted-plugins](https://github.com/enchanted-plugins) under the MIT license and is not affiliated with, endorsed by, or supported by Anthropic.

## Does Allay transmit any data off my machine?

No. Allay has no outbound network code — every hook and script either writes to stdout (the conversation), to `~/.claude/allay/` (state), or to `stderr` (logs). The claim is verifiable with a single `grep`; see [PRIVACY.md](../PRIVACY.md) for the exact reads/stores/transmits table and the commands to audit yourself.

## Can I disable Allay's token-saver compression or dedup?

Yes, per sub-plugin. Set the relevant entry under `plugins` in your `.claude/settings.json` to `{ "enabled": false }` — for example, `{"token-saver": {"enabled": false}}`. All compression and dedup behavior is advisory per the shared [hooks contract](../shared/conduct/hooks.md); it observes and injects, it never blocks a tool call.
