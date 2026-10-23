# Out-of-Scope Findings Backlog

> **These items were flagged by `/agentic-review` as out of scope for the branch
> on which they were found.** They may be stale, may already have been fixed by other
> means, may no longer apply after refactors, or may simply have been judged not worth
> addressing. Verify each entry against the current code before acting on it. Entries
> are removed only when explicitly addressed — no automatic cleanup.

---

## `c7113f1e` — Statement after an inner foreach inside an outer foreach is dropped
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm:6160`
- **Symbol:** `_process_loop_node`
- **Bug class:** Spec Compliance
- **Description:** `foreach my $x (1,2) { foreach my $y ("a","b") { print $y } print "|" }` prints "abab" through chalk->lli; perl prints "ab|ab|". Wrong at base 5948f648 and HEAD 59e7b915.
- **Suggested fix:** Ensure the outer loop body walk continues past the inner loop's exit Region to its control-chain successors, or GAP when a statement follows an inner loop.
- **Confidence:** High
- **Found by:** Spec Compliance (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `59e7b91`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `59e7b91`
- **Severity:** Important
