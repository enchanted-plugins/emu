# token-saver

**Hook type:** PreToolUse — fires before tool execution.

Reduces token usage through two mechanisms:

## Bash Compression

Wraps verbose commands with output truncation:

| Command Pattern | Compression |
|----------------|-------------|
| npm/yarn/pnpm test, vitest, jest | `2>&1 \| tail -n 40` |
| npm/yarn/pnpm install | Filter errors/warnings, tail 20 |
| cargo build/test | Filter errors/warnings, tail 30 |
| git log (verbose) | `--oneline -20` |
| find (no head) | `\| head -n 30` |
| cat (>100 lines) | `head -n 80` with line count |

### Bypass

Prefix any command with `FULL:` to skip compression entirely:
```
FULL: npm test
```

## Duplicate Read Blocking

Detects when the same file is read multiple times within 10 minutes without changes. Shows a preview and blocks the duplicate read (exit 2).

The file hash is compared — if the file changed, the read proceeds normally.
