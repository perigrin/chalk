---
title: "G6 fast-follows: alternation, \\Q\\E, \\G, /g, non-greedy, backrefs"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-10T07:33:29.609238588Z
updated: 2026-06-10T07:33:29.609238588Z
---

Tracked follow-ups deferred from G6 (the Option-B core tranche T0-T4 + qr// + s/// shipped 2026-06-10; regex.md R1-R6 all GREEN). Every deferred feature DIES AS AN EXPLICIT GAP today (no silent literal-matching). By lib/ frequency:

- T5 alternation (?:a|b) — 27 lib/ hits. May force a DFA-table fallback if the backoff-loop approach blows up on alternation; the spike flagged this as the one likely-architecture-bender.
- T6 \Q$var\E quotemeta interpolation (~5 hits) — parametric literal-matcher taking the var ptr,len at runtime.
- \G anchored continuation — used by the parser own \G($pattern) scan loop; needs match-position state threading.
- s///g global substitution — loop the match+splice; common in lib/ (128 s/// sites, many /g).
- Non-greedy *? +? ?? — medium difficulty per the spike; backoff loop runs min-up instead of max-down.
- T7 backrefs (~0 lib/ hits) — non-regular; lowest priority.
- T8-T10 ASSERTED OOS: fully-runtime-computed patterns (2 sites; needs a matcher-fn ABI — the deferred %MatchResult-at-function-boundary question), (?{code}) (0 hits), exotic Unicode \p{} (ties to G3 non-ASCII).

Also: the G7 $N magic-var consumer reads _regex_captures (RegexMatch/Match record SSA offset-pair side data keyed by node id) — G7 design should consume that contract, not invent a struct.
