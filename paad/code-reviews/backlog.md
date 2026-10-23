# Out-of-Scope Findings Backlog

> **These items were flagged by `/agentic-review` as out of scope for the branch
> on which they were found.** They may be stale, may already have been fixed by other
> means, may no longer apply after refactors, or may simply have been judged not worth
> addressing. Verify each entry against the current code before acting on it. Entries
> are removed only when explicitly addressed — no automatic cleanup.

---

## `34066162` — Unbounded recursion lowering an element store plus a guarded store in a foreach
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm`
- **Symbol:** `process_control_node`
- **Bug class:** Concurrency
- **Description:** `my @a = (1, 2); foreach my $x (1, 2) { $a[1] = $x; if ($x > 1) { $a[0] = 9 } print $a[0], $a[1] } print "\n";` recurses without bound in process_control_node (Deep recursion, OOM). Pre-existing at a7023ef3.
- **Suggested fix:** Find the control cycle the walk re-enters and add a visited guard that refuses with a GAP.
- **Confidence:** High
- **Found by:** Concurrency & State (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `4182d850`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `e1a15d3a`
- **Severity:** Important

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

## `9c217485` — defined over an out-of-range array element emits br on a %Slot
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm`
- **Symbol:** `_lower_defined`
- **Bug class:** Logic
- **Description:** `my @a = (1); if (defined $a[3]) {...}` -- the Subscript is stamped Undef but lowered as a %Slot; the Undef arm hands it to `br i1` and lli rejects the module. The ternary form fails the same way, and an inlined callee now reaches it too. Pre-existing at a7023ef3.
- **Suggested fix:** Key the arm on the lowered value's representation (or reconcile the Subscript stamp to Slot) and extract the Slot's defined bit.
- **Confidence:** High
- **Found by:** Verifier (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `4182d850`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `e1a15d3a`
- **Severity:** Important

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

## `22f3248c` — An Int accumulator that becomes a Num in a loop emits phi double over an i64
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm`
- **Symbol:** `_process_loop_node`
- **Bug class:** Logic
- **Description:** my $s = 0; for my $i (1..3) { $s += $i / 2 } -- phi double [ i64 ... ]; lli rejects the module. Pre-existing.
- **Suggested fix:** Coerce the loop phi's init value to the phi's repr in the preheader.
- **Confidence:** High
- **Found by:** review of e1a15d3a (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `e1a15d3a`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `73b983bc`
- **Severity:** Important

## `4d7c2e19` — An element store past an array's end corrupts the heap or is dropped
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm`
- **Symbol:** `_prelower_branch_store_operands`
- **Bug class:** Memory
- **Description:** `my $n = 1; $n = $n + 0; my @a = (1, 2); if ($n) { $a[2] = 3 } print scalar(@a), "\n";` aborts in lli with `munmap_chunk(): invalid pointer` where perl prints 3. No arm is needed: `my @a = (1, 2); $a[2] = 3; print scalar(@a)` aborts the same way, and `$a[5] = 3` prints 2 for perl's 6 (a silent wrong answer). Pre-existing at e1a15d3a. `push` grows the same literal-built array correctly.
- **Suggested fix:** Check how the element store grows a literal-built %Array (the literal's slots may not be heap memory that realloc/free can take) and allocate the literal's slots with malloc, or refuse a growing store.
- **Confidence:** High
- **Found by:** orchestrator probe (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `f65a372a`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `f65a372a`
- **Severity:** Important
