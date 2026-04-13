---
name: compression-rules
description: >
  Reference when user asks why output was truncated
  or how to bypass compression. Also use before every
  bash command compression decision.
allowed-tools:
  - Read
  - Bash
---

<purpose>
Reduce token waste from verbose tool outputs.
Apply rules mechanically. Do not interpret content.
</purpose>

<constraints>
1. NEVER modify commands starting with FULL:
2. NEVER compress commands already piped.
3. NEVER block user workflow — always exit 0.
</constraints>

<compression_rules>
IF "npm test" OR "yarn test" OR "pnpm test" OR "vitest" OR "jest":
  Append: 2>&1 | tail -n 40

IF "python -m pytest" OR "pytest" OR "python -m unittest":
  Append: 2>&1 | grep -E "(PASSED|FAILED|ERROR|passed|failed)" | tail -n 30

IF "go test":
  Append: 2>&1 | grep -E "(^ok|^FAIL|PASS|FAIL|panic)" | tail -n 30

IF "mvn test" OR "gradle test":
  Append: 2>&1 | grep -E "(BUILD |Tests run:|Test .*FAILED)" | tail -n 20

IF "dotnet build" OR "dotnet test":
  Append: 2>&1 | grep -E "(Build succeeded|FAILED|Passed|Failed|Test Run)" | tail -n 20

IF "npm install" OR "yarn" OR "pnpm install":
  Append: 2>&1 | grep -E "(ERR|error|added|removed)" | tail -n 20

IF "cargo build" OR "cargo test":
  Append: 2>&1 | grep -E "(error|warning|test result)" | tail -n 30

IF "make" OR "make build":
  Append: 2>&1 | grep -E "(Error|error|warning|make:)" || echo "Build succeeded"

IF "docker build":
  Append: 2>&1 | grep -E "(^Step |^Successfully |^#[0-9]+ |ERROR)" | tail -n 30

IF "terraform plan":
  Append: 2>&1 | grep -E "(Plan:|No changes|Error)" | tail -n 10

IF "eslint" OR "npx eslint":
  Append: 2>&1 | grep -E "(✖|error|warning|problems)" | head -n 20

IF "tsc" OR "npx tsc":
  Append: 2>&1 | grep -E "(error TS|Found [0-9])" | head -n 20

IF "git log" AND no "-n" flag AND no "--oneline":
  Add: --oneline -20

IF "find ." AND no "head" pipe:
  Append: | head -n 30

IF "cat [file]" AND file >100 lines:
  Replace: head -n 80 [file] && echo "---[N lines total]---"
</compression_rules>

<bypass>
FULL: prefix → remove prefix, apply zero compression, run as-is.
Tell user: "Running uncompressed. Full output will enter context."
</bypass>

<escalate_to_sonnet>
IF command >200 chars AND not in any rule:
  "ESCALATE_TO_SONNET: complex command, compression unclear"
</escalate_to_sonnet>
