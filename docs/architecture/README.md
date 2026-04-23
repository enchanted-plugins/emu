# Emu Architecture

> Auto-generated from codebase by `generate.py`. Run `python docs/architecture/generate.py` to regenerate.

## Interactive Explorer

Open [index.html](index.html) in a browser for the full interactive architecture explorer with tabbed diagrams and plugin component cards.

## High-Level Flow

Three plugins, three lifecycle phases, zero overlap.

```mermaid
graph TD
    CC["Claude Code<br/>Tool Calls"]
    context_guard["context-guard<br/><small>PostToolUse</small>"]
    CC --> context_guard
    context_guard_out(["state/metrics.jsonl"])
    context_guard --> context_guard_out
    style context_guard fill:#161b22,stroke:#3fb950,color:#e6edf3
    state_keeper["state-keeper<br/><small>PreCompact</small>"]
    CC --> state_keeper
    state_keeper_out(["state/metrics.jsonl"])
    state_keeper --> state_keeper_out
    style state_keeper fill:#161b22,stroke:#d29922,color:#e6edf3
    token_saver["token-saver<br/><small>PreToolUse + PostToolUse</small>"]
    CC --> token_saver
    token_saver_out(["state/metrics.jsonl"])
    token_saver --> token_saver_out
    style token_saver fill:#161b22,stroke:#bc8cff,color:#e6edf3
    style CC fill:#0d1117,stroke:#bc8cff,color:#e6edf3
```

## Session Lifecycle

From first tool call through compaction to context restoration.

```mermaid
graph TD
    start(["Session Start"]) --> turns
    subgraph turns["Active Session"]
        t1["Turn N: Tool Call"] --> pre["PreToolUse<br/>token-saver"]
        pre -->|"compress / dedup / delta"| exec["Tool Executes"]
        exec --> post["PostToolUse<br/>context-guard"]
        post -->|"drift detect + token est."| t1
    end
    turns -->|"Context full"| compact["⚠️ Compaction"]
    compact --> precompact["PreCompact<br/>state-keeper"]
    precompact -->|"checkpoint.md"| wipe["Context Wiped"]
    wipe --> restore["state-recovery skill<br/>or restorer agent"]
    restore -->|"Read checkpoint.md"| resume(["Session Continues"])

    style compact fill:#f85149,color:#0d1117
    style precompact fill:#d29922,color:#0d1117
    style restore fill:#3fb950,color:#0d1117
```

## Data Flow

What events each plugin logs and how they feed into `/fae:report`.

```mermaid
graph TB
    subgraph inputs["Tool Calls"]
        Bash["Bash"]
        Read["Read"]
        Write["Write / Edit"]
        Glob["Glob / Grep"]
    end
    cg_metrics["context-guard/state/metrics.jsonl<br/><small>turn (token est.)<br/>drift_detected</small>"]
    Bash --> cg_metrics
    sk_metrics["state-keeper/state/metrics.jsonl<br/><small>checkpoint_saved</small>"]
    ts_metrics["token-saver/state/metrics.jsonl<br/><small>bash_compressed<br/>duplicate_blocked<br/>delta_read<br/>result_aged</small>"]
    Bash --> ts_metrics
    report["📊 /fae:report<br/>Aggregates all metrics"]
    cg_metrics --> report
    sk_metrics --> report
    ts_metrics --> report
```

## Files

| File | What |
|------|------|
| `generate.py` | Reads codebase, generates all diagrams + HTML |
| `index.html` | Interactive architecture explorer (dark theme, tabbed) |
| `highlevel.mmd` | High-level plugin flow (mermaid source) |
| `hooks.mmd` | Detailed hook bindings (mermaid source) |
| `dataflow.mmd` | Metrics data flow (mermaid source) |
| `lifecycle.mmd` | Session lifecycle (mermaid source) |
| `*.svg` | SVG renders (if mmdc installed) |
