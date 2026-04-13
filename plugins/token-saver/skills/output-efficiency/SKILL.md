---
name: output-efficiency
description: >
  Reduces output token usage by injecting terse-mode instructions.
  Removes filler phrases, trailing summaries, and converts prose to bullets.
  Configurable: off / lite / full / ultra.
  Auto-triggers at session start or when context is running low.
allowed-tools:
  - Read
  - Bash
---

<purpose>
Cut output token waste without losing information.
Code blocks stay untouched — only compress prose.
</purpose>

<modes>
OFF:    No output compression. Default Claude verbosity.
LITE:   Remove filler phrases only. Keep structure.
FULL:   Terse mode. Bullets over paragraphs. No summaries.
ULTRA:  Caveman mode. Minimal prose. Max compression.

Default: FULL
User override: "set output-efficiency to [mode]"
</modes>

<rules mode="lite">
Remove these filler phrases from all responses:
- "It's worth noting that"
- "Let me explain"
- "I'll help you with that"
- "Sure, I can do that"
- "Great question"
- "As you can see"
- "Basically"
- "In other words"
- "To summarize"
- "In summary"
- "As mentioned earlier"
- "It should be noted"
- "It's important to remember"

Do NOT remove:
- Technical qualifiers ("Note: this will break if...")
- Warning/caution language
- Uncertainty markers ("I'm not sure, but...")
</rules>

<rules mode="full">
All LITE rules, plus:
- Remove trailing summaries ("In summary, I've done X, Y, Z")
- Remove recap sections at end of responses
- Use bullet points instead of paragraphs for explanations
- Lead with the answer, not the reasoning
- One sentence where three would do
- Keep code blocks unchanged — only compress surrounding prose
- Skip preamble — go straight to the point
</rules>

<rules mode="ultra">
All FULL rules, plus:
- Maximum 2 sentences of prose between code blocks
- No transition sentences between steps
- Strip adjectives and adverbs from explanations
- File paths and function names over descriptions
- "Fixed X" over "I've updated the file at X to fix the issue by..."
</rules>

<constraints>
1. NEVER modify code blocks, terminal output, or structured data.
2. NEVER remove information — only reduce verbosity.
3. NEVER apply to error explanations or debugging guidance.
4. ALWAYS preserve technical accuracy over brevity.
5. ALWAYS respect user's chosen mode.
</constraints>

<session_injection>
At session start, prepend this instruction based on active mode:

LITE: "Keep responses concise. Remove filler phrases."
FULL: "Be terse. Lead with answers. Bullets over paragraphs. No trailing summaries. Code stays verbose; prose stays lean."
ULTRA: "Minimum words. No filler. No summaries. No transitions. Just code and terse annotations."
</session_injection>
