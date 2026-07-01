# Phase 4 Corpus-Wide Status — the real gap map

**Date:** 2026-07-01
**Method:** ran EVERY mdtest corpus case through the actual B::SoN path
(source -> B::SoN -> JSON -> Chalk loader -> backend -> lli == perl oracle),
all 12 topics. Runner: `t/bootstrap/corpus/son-corpus-wide.t`. This replaces
the hand-picked 21-case `son-e2e.t` view with a phase-wide measurement against
Phase 4's gate ("across the corpus topics, behavior matching perl").

## Headline

| | count |
|---|---|
| **GREEN** (lli == perl) | **24** |
| GAP (corpus-declared: pragmas, non-ASCII, CodeRef) | 8 |
| **BUG / worklist** (should lower, doesn't or wrong) | **36** |

Per topic (green / declared-gap / bug):

| topic | green | gap | bug |
|---|---|---|---|
| arithmetic | 5 | 0 | 0 |
| increment | 2 | 0 | 0 |
| statements | 5 | 2 | 0 |
| strings | 4 | 1 | 0 |
| variables | 4 | 0 | 1 |
| classes | 1 | 0 | 6 |
| logical | 1 | 0 | 4 |
| references | 2 | 1 | 8 |
| control-flow | 0 | 1 | 8 |
| regex | 0 | 0 | 6 |
| host | 0 | 0 | 3 |
| subs | 0 | 3 | 0 |

Fully green topics: arithmetic, increment (+ statements/strings modulo
declared gaps). Zero-green topics: control-flow, regex, host.

## The 36 bugs collapse to ~5 root causes (NOT 36 problems)

### RC1 — missing representation on computed/aggregate/method/regex nodes (~15)
The single biggest cluster. "reached LLVM backend with NO representation":
- Subscript.container (7): references R2/R3/R4/R5/R8/R9/R10 — an aggregate
  read whose container node carries no repr.
- MOP::Method body root (5) + Call(method) (1): classes field-basic,
  field-attrs, class-isa, adjust, method-call's `val` — the 4c field-type
  and inherited-dispatch gaps already filed (019f0597).
- RegexMatch (4): regex R1/R4/R5 — a match node with no repr.
This is ONE gap: the loader's repr machinery (`_stamp_field_access_reprs` +
`_propagate_computed_reprs`, added in 4c-1b) does not yet cover Subscript
containers, RegexMatch, or type-source-less fields. A repr-inference pass
that seeds container/aggregate/regex/field reprs (from stamps + producer
type info) closes most of RC1.

### RC2 — control-flow / logical lowers but crashes at runtime, `lli exited 1` (8)
control-flow D2/D3/D4/D5 (while/foreach/postfix), logical L1/L2/L4
(and/or/not). These EMIT LLVM IR that lli rejects at run time — a control-flow
/ short-circuit lowering bug in the B::SoN -> backend path (not a type gap;
the IR is malformed or the branch structure is wrong).

### RC3 — producer fails to translate (dies), `no main::corpus_case method` (4)
host H1/H2 ($1 capture), regex R2 (qr//), logical L3b (defined-or undef-left).
B::SoN dies translating these, so no method is emitted. Producer translation
gaps (capture wiring, qr// node, dor edge case).

### RC4 — semantic miscompile, wrong value (4)
- control-flow D6 ternary + D1 if/else: `Int:2 != Int:1` — branch selection
  INVERTED (returns the else value).
- classes method-call: `Int:0 != Int:11` — object-state not persisted
  (filed 019f1007).
- regex R3 s///: `foobar != bazbar` — substitution not applied.
These are the dangerous class (silently wrong, not a loud GAP).

### RC5 — TernaryExpr Int/Bool branch typing (2)
control-flow D7/D9 nested-if: "TernaryExpr branches true=Int false=Bool".
The two arms get different reprs (one folds to Bool). A branch-repr
unification issue.

### Plus 1 straggler
- classes class-simple: "cannot lower op=Call (not in literal-arithmetic
  slice)" — Empty->new; ref($e) returns a Str; the ref() builtin path.
- host H3 (%ENV): Subscript on a Str repr — EnvRead not modeled (RC1-adjacent).

## What this means vs the Phase 4 gate

- The gate is corpus-wide behavior (+ shape + invariant, which this runner
  does NOT yet check — a separate tightening).
- 24/68 behavior-green. The remaining 36 are ~5 root causes; RC1 (missing
  repr) alone gates ~15, RC2 (control-flow runtime) another 8.
- Highest leverage: RC1 repr-inference (unblocks references + regex + the
  rest of classes) and RC2 control-flow lowering (unblocks control-flow +
  logical). Those two would move roughly 23 of 36.
- RC4 (silent miscompiles) is the most IMPORTANT to fix regardless of count:
  inverted ternary/if is a correctness bug, not a coverage gap.

## Note on the runner
Behavior-only (lli == perl). Does NOT yet enforce the plan's shape-subset or
TypedInvariant checks — a follow-up to make "green" mean the full triple
contract. Also emits Test2 "Wide character" warnings on non-ASCII diag; benign.
