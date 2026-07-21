# Coercion emission cleanup — the minimum-risk precursor to the runtime-MOP refactor

**Status:** PLAN (2026-07-20, rewritten after TWO independent assessments —
crochet:assess (adversarial correctness) + ponytail (lazy/over-build lens) —
both empty-context, both grounded in measured probes. No code yet. Supersedes an
earlier "consolidate behind a `(From,To)` vtable" draft that both assessments
found ~10x over-built.)

## What changed from the first draft (and why)
The first draft (a Fable feasibility pass) proposed a `%COERCE_CELLS` `(From,To)`
vtable + entry point + routing print through the `_emit_int_to_str` do-while
renderer + an epilogue restructure. **Both assessors independently rejected that
as over-built, and correctness-assess PROVED the minimal fix by measurement:**
- The i32 truncation is a **printf format-string bug** (`%d` is 32-bit), not a
  coercion bug. Fix = `%d`→`%lld` + delete the `trunc i64->i32` lines + pass the
  i64 straight to printf. MEASURED end-to-end: `print 4294967296` -> `4294967296`
  (was `0`); INT64_MIN, i64-max, negatives all correct; **full corpus gate WITH
  the patch = 148/worklist=0, zero regressions.** A direct `lli` probe confirmed
  `%lld` honors full i64 varargs on x86-64 (llvm-15).
- So the renderer-routing + epilogue-restructure + INT64_MIN-renderer-edge work
  is UNNECESSARY — INT64_MIN prints correctly via `%lld` for free.
- The `%COERCE_CELLS` vtable is **runtime-MOP pilot groundwork**, not this step's
  need: only ONE site (`_lower_coerce`) dispatches on a runtime `(from,to)` pair
  and it already dispatches; every other site knows `to` statically. Build the
  table when the pilot swaps its first cell for inlined self-hosted IR — that's
  when the real cell signature is known. CUT from this step.

But correctness-assess also found the first draft's INVENTORY was wrong, so the
minimal version had to grow slightly to be *correct*:
- The site inventory is **11+ sites across THREE files**, not 7 across two.
- There is a **THIRD i32-truncation site** (the Slot epilogue) — the format fix
  must cover it or the bug stays latent in the Slot shape.
- There is a **live divide miscompile** (`$x/$y` on two Ints -> lli rejects the
  module) the first draft never named — a real `(Int,Num)` coercion gap.

## Evidence base (all MEASURED against current head; gate baseline 148/worklist=0)

**Bug 1 — i32 truncation (a printf FORMAT-STRING bug), THREE sites:**
- `@fmt = "Int:%d\0A"` (LLVM.pm:1004), fed by `trunc i64->i32` (LLVM.pm:1291) — the Int return epilogue.
- `@fmt_print_int = "%d"` (LLVM.pm:1096), fed by `trunc` (Context.pm:5680-5681) — `_lower_print` Int arm.
- `@fmt_slot_int = "Int:%d"` (LLVM.pm:1068), fed by `trunc` (LLVM.pm:1378) — the **Slot epilogue** (assess found this; the first draft missed it). Could not be reached with a big defined payload in probes (repr inference refined every Slot-shaped probe to Int), but it is live emission code — a %lld fix that skips it leaves the bug latent.
MEASURED: `print 4294967296` -> lli `0` vs perl `4294967296`; bare `4294967296`
-> lli `Int:0` vs oracle `Int:4294967296`. The interpolation/`eq` big-int paths
were ALREADY correct on head (`my $n=4294967296; "$n"` -> `4294967296`) — the bug
is purely the printf `%d` paths.
FIX (measured correct, zero regressions): `%d`->`%lld`, delete the three truncs,
pass i64. INT64_MIN correct for free (proved via lli: `%lld` prints
`-9223372036854775808`). The renderer's INT64_MIN UB edge (Context.pm:954-956)
is NOT touched — it only matters on the interpolation/eq paths, already correct.

**Bug 2 — live divide miscompile (assess found; first draft missed):**
`_lower_divide`'s Num path (Context.pm:754-762) does NOT promote Int operands
(unlike `_lower_binop_int`, whose Num arm promotes via `_lower_as_double` at
Context.pm:702-703). MEASURED: `my $x=3; my $y=4; $x/$y` -> lli rejects the
module `'%tmp' defined with type 'i64' but expected 'double'` on `fdiv double`,
exit 1 (patched fix measured: `3/4` -> `Num:0.75`; Num/Num `1.5/0.5` -> `Num:3`
passthrough unbroken). LOUD (lli verifier), not silent, but it is exactly the
`(Int,Num)` op-contract coercion this cleanup is about.
FIX: `_lower_divide` promotes Int operands via `_lower_as_double`, same as
`_lower_binop_int` already does. NOTE: Divide has NO both-Int i64 fast path to
disturb — an Int-repr Divide dies by design at Context.pm:741-746 — so there is
no fast-path caveat to verify.

**Bug 3 (DEFERRED, filed not fixed here) — dropped numify warning:**
`"abc" == 1` should emit `Argument "abc" isn't numeric in numeric eq (==)` to
STDERR; the emitted module has NO warning path (measured). NOT a DualVar — a
plain `Str->Num` transform with a conditional runtime warning-effect. Measured
Perl 5.42 matrix: warns on `'abc'`,`'3abc'`,`''`,`'0x10'`,`'3.14x'`; silent on
`' 42'`,`'42 '`,`"42\n"`,`'.5'`; silent without `use warnings`. Needs harness
trailer-normalization (the ` at FILE line N.` trailer has a tempfile path) +
producer COP-warnings-bit stamping + a stderr host intrinsic + a deferred
effect-ordering caveat. This is a separate 3-piece chain with its own
producer-side prerequisite — FILE it (preserving the matrix), do not build here.

**The duplicated-emission inventory (11+ sites, THREE files):**
- (Int/Num->Bool) truthiness — FOUR copies: `_lower_coerce` arms (Context.pm:1030-1124), `_ensure_i1` (:1176-1194), `_shortcircuit_i1_cond` (:1892-1910), `ElaboratedContext::_process_if_node` (ElaboratedContext.pm:46-51). Divergent: `_shortcircuit_i1_cond` GAPs Num; ElaboratedContext defaults `$cond_repr // 'Bool'` with no Num arm; `_coerce_ref_to_num` maps undef->Int while `_ensure_i1` dies on undef.
- (Int->Num) sitofp — THREE copies: `_lower_coerce` arm (:1024), `_coerce_ref_to_num` (:1632), `_lower_as_double` (:723-732).
- (Str->Num) leading-numeric — TWO copies: `_lower_coerce` arm (:1078-1083), `_coerce_ref_to_num` (:1639).
- (Int->Str) — `_lower_stringify`/`_emit_int_to_str`, `_str_compare_operand` (already share `_emit_int_to_str`).

**Dedup safety (MEASURED SAFE) — [now DEFERRED to the pilot, see below]:** the
helpers emit instruction-IDENTICAL output to the inline arms — only trailing
COMMENTS differ (`; _ensure_i1: Int truthiness` vs `; Coerce[Int->Bool]
truthiness`). Nothing pins .ll text: the corpus gate compares behavior +
IR-shape + invariant (never .ll bytes), and NO test matches emitted instructions
at all (MEASURED: zero `qr/.../` regexes over sitofp/fdiv/icmp/trunc/GEP in t/;
the only `Int:%d` literals are TypeTag.pm:155/181/138-comment, type-tag.t:162,
and the self-contained g1-miscompile-classification.t fixture). So dedup would be
safe. The divergence caveats (undef-repr: `_coerce_ref_to_num` maps undef->Int
while `_ensure_i1` dies; `_shortcircuit_i1_cond` GAPs Num) are why dedup is NOT
trivial and NOT in this cleanup — see "Deferred: dedup" below.

**Harness rider:** `t/lib/Chalk/CodeGen/Harness/TypeTag.pm:155,181` pin the old
`Int:%d` format as "canonical" (`llvm_fmt_c => 'Int:%d\0A\00'`), and
`type-tag.t:162` checks it. They self-compare (still pass with the fix) but
become stale lies about LLVM.pm — update the 3 strings alongside the fix.
(`g1-miscompile-classification.t:164` is a self-contained fixture — unaffected.)

## THE PLAN (gate-guarded: gate-green>=148 worklist=0 after every step, self-verified by the coordinator)
Gate: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/lib t/bootstrap/corpus/son-corpus-wide.t`
Non-negotiable: NEVER reclassify a regression as worklist; NEVER claim the floor stale (it is 148, freshly measured).

**Step 1 — RED first (worklist corpus cases).** Add to `t/corpus/mdtest/`:
`print 4294967296, "\n"; 1` (expect `4294967296\n` + `Int:1`); bare `4294967296`
(expect `Int:4294967296`); INT64_MIN (`-9223372036854775808`). Slot epilogue: the
DEFINED-payload Slot path could not be reached (repr-inference refined every
constructible big-payload probe to Int), BUT assess found `my @a=(1,2); $a[5]`
(OOB) DOES emit the genuine Slot epilogue — use an OOB Slot case to corpus-cover
the Slot format site (its runtime value is `Undef:`, but the `%lld` patch makes
lli verify the whole module incl. the defined arm, which is the coverage that
matters). Mark all worklist so the gate stays green with them RED. Risk: none
(test-only).

**Step 2 — fix the truncation bug CLASS in one format-string pass.** For all
three sites: change the format `%d`->`%lld` (`@fmt` LLVM.pm:1004, `@fmt_print_int`
:1096, `@fmt_slot_int` :1068), fix the `[N x i8]` array-LENGTH constant on the
GLOBAL, **fix the matching `[N x i8]` type on the GEP USE site** (LLVM.pm:1292,
:1379; Context.pm:5684 — typed-pointer LLVM 15 rejects a mismatched GEP), delete
the three `trunc i64->i32` lines (LLVM.pm:1291, :1378; Context.pm:5680-5681), pass
the i64 straight to printf. Update the harness pins TOGETHER: `TypeTag.pm:155,181`
(+ the `:138` comment) AND `type-tag.t:162` (which hard-codes `'Int:%d\0A\00'` as
a TAP expectation — updating TypeTag.pm without it makes type-tag.t FAIL, loud but
self-catching). Proof: the step-1 print/bare/INT64_MIN cases flip GREEN; floor
148->150+; type-tag.t stays green. Risk: LOW (MEASURED end-to-end this exact
patch class = 148/worklist=0, zero regressions; `%lld` honors full i64 on the
target, proved via lli, INT64_MIN correct for free).

**Step 3 — fix the divide miscompile.** `_lower_divide` Num path promotes Int
operands via `_lower_as_double` (mirror `_lower_binop_int`, Context.pm:702-703).
Add a corpus case `my $x=3; my $y=4; $x/$y` (expect `Num:0.75`). Risk: LOW (a
2-line mirror of an existing call; NO both-Int fast path in Divide to disturb —
Int-repr Divide dies at :741-746; MEASURED patched: `3/4`->`Num:0.75`, Num/Num
passthrough unbroken).

MEASUREMENT CORRECTION (landed as commit 0b0f6eda, this claim was wrong):
the fix greens ONLY the behavior + shape legs, NOT the full triple contract.
The gate's TypedInvariant leg stays RED because Divide requires its inputs to
be Num OR bridged by an explicit `Coerce` node (TypedInvariant.pm:22, pinned by
well-typed-graph.t H2-6/H2-7), and B::SoN emits `Divide(Int,Int)` stamped Num
with NO Coerce node. So gate-green holds at 152, the divide case stays
worklisted, and the floor does NOT rise (still 148). Inserting the real
`Coerce(Int->Num)` node is the coercion-node work fenced to the runtime-MOP
pilot — filed as pilot issue 019f82f1, NOT built here. The original "floor +1"
was a behavior-only measurement; it omitted the invariant leg.

**Step 4 — FILE (do not build) three parked issues:**
- **DEDUP (evicted here per assessment — it is the pilot's opening commit):** the
  duplicated coercion emission (4x Int/Num->Bool truthiness across `_lower_coerce`/
  `_ensure_i1`/`_shortcircuit_i1_cond`/ElaboratedContext; 3x Int->Num sitofp; 2x
  Str->Num). NOT in this cleanup because (a) it touches 5 different functions in 3
  files, unrelated to the epilogue/print/divide edits; (b) the "duplication" is
  mostly deliberately-DIVERGENT 1-liners (each truthiness copy has a different
  contract: die-on-undef vs GAP-Num vs default-Bool) — folding them means
  threading GAP-message params, so "net-negative diff" is doubtful; (c) TOUCH-TWICE:
  the pilot's vtable cells WILL BE the deduped helpers, and the cell signature is
  unknown until the first cell-swap — dedup now onto today's signatures then
  re-route through cells later = same lines twice. Dedup is the pilot's natural
  opening commit. (Only the Str->Num pair is genuinely identical 4-line
  duplication — a candidate for a standalone `/simplify` if wanted, but still
  cheaper to do with the pilot.)
- The numify-warning chain (6a harness trailer-normalization / 6b producer
  COP-warnings-bit / 6c `(Str,Num)` stderr host intrinsic + effect-ordering
  caveat) — paste the measured warning matrix in.
- Print-args-as-Stringify-nodes (producer graph-visibility) — parked WITH the
  runtime-MOP pilot; it is the pilot's opening move, not a bug-fix.

## THE BOUNDARY
**Delivers (as landed):** three i32-truncation sites fixed via one
format-string pass (gate 148->152, commit 523f9c87); the divide `(Int,Int)`->fdiv
miscompile fixed at the BACKEND (commit 0b0f6eda) — behavior + shape green, but
gate-green holds at 152 and the case stays worklisted because its IR needs a
`Coerce(Int->Num)` node the fix does not insert (invariant leg red; filed as
pilot 019f82f1). The numify-warning gap + the coercion-emission DEDUP +
print-args-as-nodes + the Divide Coerce-node insertion all measured/specced and FILED
(dedup evicted to the pilot per assessment — see Step 4); the runtime-MOP vtable
groundwork correctly deferred. This cleanup is intentionally TINY: ~4 bug-fix
edits + tests + filing, no refactor, no new abstraction.

**Deliberately does NOT touch (deferred to the runtime-MOP pilot / bigger refactor):**
the `%COERCE_CELLS` `(From,To)` vtable (pilot's first commit, built when the
first cell-swap defines the cell signature); the `Stringify`->`Coerce` node
merge + S9-S12 ir-block rewrite; ByteBuf + self-hosted subset `coerce(Int,Str)`;
the snippet library (pilot G3); the runtime `Type->coerce` object / from-type-
unknown runtime dispatch; Coerce-node insertion for compares (blocked: no
rewrite machinery, from_repr unknown at produce time, both-Int icmp needs final
reprs — all three blockers grounded and confirmed); the numify warning itself
(filed); Num->Str float formatting (019f7771); UV-vs-IV (019f77d8).

**Honest line:** this is a bug-fix-and-dedup cleanup that removes the coercion
DUPLICATION and fixes three real miscompiles (three truncation sites + divide),
using the file's existing helper idiom. It does NOT build the coercion
abstraction — the vtable and the self-hosting lift are the pilot. Naming this
"Step 1 of the runtime-MOP refactor" over-claims; it is the minimum-risk
CLEANUP that makes the pilot's later work land on a deduplicated, correct base.
