# Out-of-Scope Findings Backlog

> **These items were flagged by `/agentic-review` as out of scope for the branch
> on which they were found.** They may be stale, may already have been fixed by other
> means, may no longer apply after refactors, or may simply have been judged not worth
> addressing. Verify each entry against the current code before acting on it. Entries
> are removed only when explicitly addressed — no automatic cleanup.

---

## `2c7696e7` — next inside an if arm in a foreach is lowered as last
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm`
- **Symbol:** `_arm_loop_exit_label`
- **Bug class:** Error Handling
- **Description:** `foreach my $x (1,2,3) { if ($x == 2) { next } else { print "e" } } print "\n";` prints `e` for perl's `ee`: the next arm's Proj feeds a Region headed by the Loop and is branched to loop.exit. Pre-existing at a7023ef3.
- **Suggested fix:** Distinguish the loop's exit Region from a continue/latch Region headed by the same Loop before treating an arm as a break.
- **Confidence:** High
- **Found by:** Error Handling (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `4182d850`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `e1a15d3a`
- **Severity:** Important

## `336a2f63` — A reference stringifies as its element count
- **File (at first sighting):** `lib/Chalk/Target/LLVM/Context.pm`
- **Symbol:** `_emit_to_str`
- **Bug class:** Logic
- **Description:** The aggregate arm treats ArrayRef/HashRef like an aggregate in scalar context: `my $r = [1,2,3]; print $r` prints `3` for perl's `ARRAY(0x...)`. t/bootstrap/llvm-stringify-undef.t subtest 4 (ArrayRef must GAP) fails at a7023ef3 and after.
- **Suggested fix:** Refuse (GAP) a Ref repr in _emit_to_str; keep the count only for Array/Hash in scalar context.
- **Confidence:** High
- **Found by:** Logic, Error Handling, Contract, Spec Compliance (`claude-opus-5-5[1m]`)
- **First seen:** 2026-10-23 on branch `bson/llvm-corpus` at `4182d850`
- **Last seen:** 2026-10-23 on branch `bson/llvm-corpus` at `e1a15d3a`
- **Severity:** Important

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
