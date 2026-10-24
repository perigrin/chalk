# Out-of-Scope Findings Backlog

> **These items were flagged by `/agentic-review` as out of scope for the branch
> on which they were found.** They may be stale, may already have been fixed by other
> means, may no longer apply after refactors, or may simply have been judged not worth
> addressing. Verify each entry against the current code before acting on it. Entries
> are removed only when explicitly addressed — no automatic cleanup.

---

## `552af56b` — die prints no message to stderr
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm`
- **Symbol:** `_emit_unwind_terminator`
- **Bug class:** Error Handling
- **Description:** The Unwind terminator emits only exit(255); `die "neg\n"` prints nothing where perl prints `neg` on stderr. Invisible to the stdout-only census.
- **Suggested fix:** Lower the die message operand and write it to stderr before exit(255).
- **Confidence:** High
- **Found by:** orchestrator probe (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `4182d850`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `e1a15d3a`
- **Severity:** Suggestion

## `81c5efed` — An inlined call in a short-circuit arm does not dominate the merge
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm`
- **Symbol:** `_lower_inlined_effects_then_value`
- **Bug class:** Logic
- **Description:** sub g { return $_[0] * 2 } my $c = 0; my $x = $c && g(3); lli rejects the module: the inlined callee's mul is defined in the && arm block, which does not dominate the merge phi. Pre-existing at 4182d850.
- **Suggested fix:** Lower the call's value in the arm's tail block, as phi arms are, or refuse a call inside an And/Or arm.
- **Confidence:** High
- **Found by:** review of e1a15d3a (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `e1a15d3a`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `73b983bc`
- **Severity:** Important

