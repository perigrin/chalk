# Bug 4 RCA and Remediation Plan

**Date:** 2026-04-25
**Bug:** "TypeInference + SemanticAction interaction" rejecting builtins inside
`map`/`grep`/`sort` BLOCK
**Audit reference:**
`docs/plans/2026-04-25-audit-2-semirings-findings.md` "Addendum: IR-cluster
rejection pattern"
**Status:** RCA complete. Remediation proposed. Not implemented.

## Verification of audit findings

The audit's claims hold up under fresh probes (`/tmp/bug4-verify.pl`,
`/tmp/bug4-rca.pl`):

| Stack | `map { defined $_ } @arr` |
|---|---|
| `[B]` | PASS |
| `[B,P]` | PASS |
| `[B,P,T]` | PASS |
| `[B,P,T,S]` | PASS |
| `[B,P,T,S,A]` | **FAIL** |
| `[B,T]` | PASS |
| `[B,A]` | PASS |
| `[B,T,A]` | **FAIL** (minimal failing combo) |
| `[B,T,S,A]` | FAIL |

Trigger-builtin classification reproduced — `defined`, `ref`, `length` all
FAIL in `[B,T,A]`; `return`, `pop`, `keys`, `sort` all PASS.

The audit's framing of Bug 4 as a TI+SA *interaction* is empirically correct
at the pass/fail level (neither TI alone nor SA alone rejects), but the
addendum's hypothesis that "SA's action returns undef" or "the threaded
context is causing side effects via some action's input handling" is wrong.
Instrumentation shows a different mechanism. See "Root cause" below.

## Observation log

Probes used: `/tmp/bug4-verify.pl`, `/tmp/bug4-rca.pl`, `/tmp/bug4-walk.pl`,
`/tmp/bug4-final-verify.pl`, `/tmp/bug4-pop-test.pl`. All deleted at end of
session.

### Per-event return values for `my @x = map { defined $_ } @arr;`

`/tmp/bug4-rca.pl` instruments `TypeInference._complete_type`, capturing
`_get_call_symbol`, `_get_item_types`, and `_get_list_arity` at each
CallExpression complete event. Distinct events observed:

#### `[B,T,A]` (FAIL)

```
[1x] CallExpr alt=1 call_sym=defined arity=1 item_types=[Scalar] -> HASH(...)
[1x] CallExpr alt=1 call_sym=map     arity=1 item_types=[HashRef] -> ZERO
[1x] CallExpr alt=2 call_sym=map     arity=1 item_types=[Scalar]  -> ZERO   <-- correct outer parse, rejected
[1x] CallExpr alt=3 call_sym=map     arity=1 item_types=[Scalar]  -> ZERO
```

#### `[B,T]` (PASS)

```
[2x] CallExpr alt=1 call_sym=<none>  arity=<none> item_types=<none> -> HASH
[1x] CallExpr alt=2 call_sym=<none>  arity=<none> item_types=<none> -> HASH
[1x] CallExpr alt=3 call_sym=<none>  arity=<none> item_types=<none> -> HASH
```

In `[B,T]`, every `_get_call_symbol`/`_get_item_types`/`_get_list_arity` walk
returns `<none>`. The signature-validation block at
`TypeInference.pm:340-365` is a no-op because `if ($call_sym)` is false. TI's
"keep" of every CallExpression in `[B,T]` is *coincidental* — it is the
absence of a working tree-walk, not a deliberate accept.

In `[B,T,A]`, the same walk returns concrete values, the signature block
runs, and rejects.

### Walk-order evidence (`/tmp/bug4-walk.pl`)

For `[B,T,A]` parsing `my @x = map { defined $_ } @arr;`, the SA-built shared
Context tree at the outer `CallExpression alt=2` complete event contains
two nodes with `item_types`:

```
[d=17] type={item_types=[Scalar],list_arity=1,valid=1}    <-- INNER ExpressionList ($_)
[d=1]  type={item_types=[Array], list_arity=1,valid=1}    <-- OUTER ExpressionList (@arr)
```

`_walk_annotations` (`TypeInference.pm:77-91`) is left-to-right DFS via
explicit stack with `pop`-after-`push-reversed`. It returns the first
`item_types` it encounters. The leftmost-deepest path leads through the
inner `defined $_` BLOCK, so `[Scalar]` is found before `[Array]`.

Then `_complete_type` does:

```perl
my $sig_offset = ($alt_idx == 2 || $alt_idx == 3) ? 1 : 0;     # alt=2 -> 1
my $expected = $arg_types->[0 + 1] = 'List';                   # map's 2nd slot
type_satisfies('Scalar', 'List')                               # false
return undef;                                                  # ZERO
```

`Scalar` is in `%POLYMORPHIC_TYPES`, but `is_subtype('List', 'Scalar')` is
false (List is not a subtype of Scalar). Both directions of the satisfies
check fail. ZERO propagates.

### Why the audit thought this was an "interaction"

The empirical observation `[B,T] PASS, [B,A] PASS, [B,T,A] FAIL` is real.
But it is not because TI and SA together do something that neither alone
does. It is because of two structural facts about the FilterComposite
plumbing:

1. **TI as `_sa()` does not populate `annotations->{type}` on shared
   Context nodes.** FilterComposite's `_annotation_semirings()` returns
   `[Boolean]` in `[B,T]`. Only annotation semirings have their multiply
   results stored in `annotations->{slot}` via `_wrap_sa_result`. TI's
   tag-hash returns from scan/complete events are *discarded* in `[B,T]`
   because TI is the last semiring (the tree-builder), not a slot writer.
   Result: every node has `annotations->{type} = undef`. Walker finds
   nothing. Signature check no-ops.

2. **TI as an annotation semiring populates `annotations->{type}` even
   without SA, but the tree is structurally degenerate.** In `[B,P,T,S]`,
   Structural is `_sa()`. Structural returns integers, so
   `_wrap_sa_result`'s `children => $is_ctx ? […] : []` produces a
   one-node-deep wrapper Context. The walker sees only the outer wrapper's
   annotations and stops. Signature check no-ops because no descendants
   exist to find call_symbol/item_types in.

Only when SA is `_sa()` AND TI is in `_annotation_semirings()` does the
shared Context tree have both (a) deep child structure and (b) populated
`annotations->{type}` slots. Only then does TI's signature check actually
execute. And when it executes, the tree-walk finds the wrong
`item_types` and rejects.

## Root cause

**Bug 4 is the same root cause as Audit 2's Bug 1 and Bug 2.** All three
are TypeInference's `CallExpression` branch
(`lib/Chalk/Bootstrap/Semiring/TypeInference.pm:340-365`) applying
per-position type checking incorrectly to block-form builtins. The sub-cases:

- **Bug 1**: outer LIST argument is parenthesized literal list. `_get_item_types`
  finds the LIST literal's per-position types (e.g. `[Int, Int]`) and checks
  them against arg_types[0]='Code' or arg_types[1]='List'. Per-position
  Int does not satisfy the variadic List slot.
- **Bug 2**: BLOCK contains fat-arrow ExpressionList. `_get_item_types` finds
  the inner ExpressionList's item_types (`[Scalar, Int]`) and checks them
  against arg_types. The inner BLOCK's body type leaks.
- **Bug 4**: BLOCK contains a CallExpression with explicit ExpressionList
  (e.g. `defined $_`, `length $_`, `ref $_`). `_get_item_types` finds the
  innermost ExpressionList's item_types (e.g. `[Scalar]` for `$_`),
  not the outer ExpressionList for `@arr`/`$ref->@*`/`qw(a b c)`.
  `type_satisfies('Scalar', 'List')` is false because `is_subtype('List',
  'Scalar')` is false (List is not a subtype of polymorphic Scalar).

**Single sentence**: `_get_item_types` is greedy DFS and finds whatever
ExpressionList comes first in left-to-right depth-first order, which is
not necessarily the CallExpression's *direct* argument list.

**Why trigger-set ≠ all-builtins**: A builtin's containing-BLOCK only
triggers the bug when it is parsed via `CallExpression` alt 1
(`Identifier WS ExpressionList`) and produces an inner ExpressionList
in the multiply tree. Builtins that parse via dedicated grammar rules
(`return` → ReturnStatement, `sort` parsed alongside its block, `pop`/`keys`
where the inner ExpressionList happens to have type-compatible items by
coincidence) do not produce the same trigger shape.

## Categorization

**Category A (TI bug)** with a footnote about Decision 5.

The bug is entirely within TypeInference's `_complete_type` /
`_get_item_types` / tree-walk logic. SA's role is to *enable* the bug by
providing a child-bearing tree for TI to walk. SA's role is not part of the
defect — SA correctly threads the multiply tree, and `ConciseTree::Actions`
correctly produces a parse forest that includes the BLOCK-with-inner-call
shape. There is no contract drift between TI and SA for Bug 4 (Bug 4 does
not interact with the strengthen-the-contract decision).

The Decision 5 footnote: when TypeInference is fully reconstituted as
flow-typing (Decision 5, per the synthesis), the BLOCK position's type
becomes "the type produced by the BLOCK's body in list context." For
`{ defined $_ }` that's `Bool` reflowed as the per-iteration item type.
The signature check would then ask "does `Code(args=Scalar) returning Bool`
satisfy `Code` in `map`'s sig?" rather than the current "does `Scalar`
satisfy `List`?" Bug 4 would not arise from that question. So **Bug 4 is
likely to dissolve as a side effect of flow-typing completion**, but it is
not exclusively a Decision-5 issue — it is also patchable as a TI bug
today, as Bugs 1 and 2 are.

This places Bug 4 in **Category A** with **Category E as a secondary
description**: A is the diagnosis ("today this is a TI tree-walk bug"); E
is the long-arc framing ("flow-typing completion will make this go away").

## Proposed remediation

There are two reasonable shapes. Picking between them is a sequencing
question covered in the next section.

### Shape 1: Patch TI's tree-walk for direct ExpressionList lookup (Tier 1, fast)

**File**: `lib/Chalk/Bootstrap/Semiring/TypeInference.pm:111-118`
(`_get_item_types`, and the analogous `_get_list_arity` at 122-129).

**Change**: replace the greedy DFS with a *direct-child ExpressionList*
lookup. The CallExpression's direct argument-list is the rule's last
significant child (the ExpressionList symbol from the BNF
`Identifier WS Block WS ExpressionList`). The tree-walk should look at
the *outermost* ExpressionList visible at the top level of `$value`, not
descend into nested CallExpressions/Blocks looking for any ExpressionList.

Implementation options, in order of preference:

1. **Stop descent at completed-CallExpression boundaries.** When walking
   `$value`, do not descend into a node whose `annotations->{type}->{type}`
   indicates a completed CallExpression result (the result hash with
   `type=$return_type`). This makes the walker treat completed sub-calls
   as opaque leaves.
2. **Walk in reverse-DFS order, stop at first match.** Right-to-left DFS
   would find the OUTER ExpressionList (which is the rightmost element of
   the alt=2 sequence `Identifier WS Block WS ExpressionList`) before the
   inner one. This is structurally correct for alt=2 (`Identifier WS Block
   WS ExpressionList`) but NOT for alt=3 (`Identifier WS Block`), where
   there is no outer list — and not for alt=0/1 either. So this would need
   to be alt-aware.
3. **Track the ExpressionList directly via Context's `rule` field.** The
   ExpressionList that is the CallExpression's direct argument list has
   its containing-Context's `rule` set to `'ExpressionList'` and is the
   only ExpressionList among `$value`'s top-level children (not below a
   completed sub-call). Walk only top-level children whose `rule` is
   `ExpressionList`.

Option 1 is the smallest behavior change. Option 3 is the most principled
but requires verifying that the `rule` field is set on intermediate
contexts in the way the implementation needs.

**Cross-effect with Bug 1 and Bug 2**: Bugs 1 and 2 share the same fix
site. Bug 1 needs a different remediation (the LIST signature slot's
satisfies-check needs to accept per-position scalars, OR the outer
ExpressionList's per-position types should not be checked when the slot
is variadic LIST). Bug 2 needs the BLOCK's return type to be treated as
Code, not as the BLOCK's body's last expression type. Bug 4's fix
(stop-at-call-boundary in the walker) is compatible with either Bug 1 or
Bug 2 fix, but does not retire them — Bug 1 and Bug 2 each need their own
remediation in addition.

If the BLOCK position type is fixed as "Code regardless of body" (Bug 2
shape), Bug 4 partly resolves: the BLOCK position's `_get_item_types`
walk wouldn't matter for the alt=2 LIST slot because the LIST slot is
position 1, not position 0. But the per-position check would still walk
the tree and might still find the wrong item_types for the LIST slot.

### Shape 2: Defer to Decision 5 (flow-typing completion)

**File**: none — this is a deferral.

**Rationale**: The current `_complete_type` is documented (per Decision 5
and `pvm_typeinference_reference.md`) as transitional scaffolding. The
"correct" model is: each CallExpression knows its *own* signature and its
*own* arguments, not by tree-walking but by the parser's structural data.
Flow-typing completion will replace the tree-walk-for-call_symbol/item_types
with explicit per-rule typed values flowing through the IR.

If the work to make `_get_item_types` correct here will be discarded
during flow-typing completion, patching it now is wasted effort. The cost
of waiting: `t/grammar-conformance.t` keeps reporting 27 failing files
including the IR cluster.

**Where Decision 5 lives in the timeline** (from the synthesis):
> Likely lives between MOP Phase 3c (typed-node SSA graphs land) and Phase
> 5 (optimizer signatures benefit from flow-typed return values).

That's a multi-issue gap. Patching now (Shape 1) costs ~2-4 hours and
unblocks the IR cluster files; deferring costs nothing today but holds
the IR cluster failures open through Phases 3a-infra, 3a-migration, 3b,
3c. Shape 1 is the better trade-off as long as the patch doesn't get in
flow-typing's way.

### Recommended shape

**Shape 1 with Option 1 implementation** (stop descent at completed-
CallExpression boundaries). This is a single-method change in
`TypeInference.pm`, narrow in scope, retires the same site as Bugs 1+2,
and unblocks `t/grammar-conformance.t` for the 9 IR-cluster files plus
5+ non-cluster files.

The recommended fix is *not* a reverse-DFS walk (Option 2). The trees TI
walks vary in shape across alts, and a uniform reversal would just trade
one set of false positives for another.

## Side effects

1. **Interaction with Bugs 1+2's fix** (TypeInference.pm:340-365):
   Bug 4's fix and Bugs 1+2's fix touch the same site. Sequencing them is
   important. If Bug 4 fix lands first, Bug 1's failing case `map { … }
   (1, 2, 3)` still fails (different tree shape, different walker target).
   If Bugs 1+2 land first via "BLOCK position is Code" change, Bug 4's
   trigger may partially resolve but the per-position LIST check still
   walks. Recommended order: land Bug 4's walker fix first (smaller
   scope), then revisit Bug 1+2 — they may need less than the audit
   suggests once the walker is direct-child-bound.

2. **Interaction with Decision 4 (semiring contract)**: Bug 4 has no
   dependency on the contract migration. TI is already a contract
   violator (mixed return types). Bug 4's fix does not change that — it
   only changes the *tree-walk* used inside `_complete_type`. The
   contract-migration sequencing (zero/one/multiply uniform across all
   call paths) is orthogonal.

3. **Interaction with Decision 5 (flow-typing)**: Bug 4 fix is a
   transitional patch that flow-typing will eventually replace. The
   patch should not introduce new tree-walk infrastructure that would
   need to be ripped out — Option 1 above keeps the change to a single
   method body, which is consistent with "patch the symptom, plan to
   replace the mechanism."

4. **Interaction with IR-cluster files**: After fix, the 9 IR-cluster
   files plus 5+ non-cluster files using the `map/grep/sort BLOCK`
   pattern with named-unary builtins should parse end-to-end at the
   semiring stage. They may still fail downstream (Earley stale-merge,
   action bugs in Actions.pm) — Bug 4 fix unblocks parse-recognition,
   not full IR-build correctness.

5. **Interaction with Phase 3c reviving `ir-program-pipeline.t` and
   `ir-sub-info-pipeline.t`**: those tests parse Shim.pm, NodeFactory.pm,
   etc., which contain the trigger pattern. Bug 4 fix is a prerequisite
   for those tests to reach the IR-build stage at all. The synthesis
   notes this dependency at Tier 1.

## Acceptance criteria

1. **Minimal failing case passes**: `my @x = map { defined $_ } @arr;`
   parses end-to-end in `[B,P,T,S,A]` (full stack).
2. **Trigger-builtin set passes**: All 22 builtins listed in the
   audit addendum trigger list pass when used as `map { BUILTIN $_ }
   @arr` and `grep { BUILTIN $_ } @arr` (where applicable). Probe
   structure already exists in the audit's `/tmp/audit2-followup-isa.pl`.
3. **Non-trigger-builtin set still passes**: `return`, `die`, `pop`,
   `shift`, `keys`, `values`, `each`, `sort`, `reverse` still pass with
   no regression.
4. **IR-cluster grammar-conformance regression**: `lib/Chalk/IR/MethodInfo.pm`,
   `SubInfo.pm`, `UseInfo.pm`, `FieldInfo.pm`, `Node.pm`,
   `Bootstrap/IR/NodeFactory.pm`, `Bootstrap/BNF/Target/XS/AST/XSUB.pm`,
   `Grammar/Rule.pm` parse to a semiring-validated parse tree at full
   stack. (They may still fail at action-stage; this criterion is about
   the parse stage.)
5. **No regression in passing files**: `t/grammar-conformance.t` PASS
   count does not decrease. The 121 passing files continue to pass.
6. **No regression in unit tests**: `t/bootstrap/*.t` continues to pass.
   In particular, the TypeInference unit tests do not regress.
7. **Bug 1 and Bug 2 minimal cases continue to fail (as before)**:
   `map { … } (1, 2, 3)` still fails; `map { $_ => 1 } @arr` still
   fails. Bug 4 fix does not retire those — they need their own
   remediation. This is an explicit non-goal — Bug 4 fix is not a
   universal `_complete_type` rewrite.

## Sequencing recommendation

**Bug 4 fix lands BEFORE Bugs 1+2 fix.** Reasoning:

- Bug 4's site count (14+ files) is larger than Bugs 1+2 combined (Bug 1
  is paren-list LIST arg, ~rare in `lib/`; Bug 2 is fat-arrow in BLOCK,
  also rare). Front-loading Bug 4 unblocks the most files per fix.
- Bug 4 fix is narrower in scope (one tree-walk method change) than
  Bugs 1+2 fix (which requires either `type_satisfies` semantics change
  or alt-aware `_complete_type` logic).
- After Bug 4 fix, re-checking Bugs 1+2 may show the audit's framing
  shifted — the walker fix may make the per-position check examine
  different (correct) item_types, possibly retiring Bug 1 or Bug 2 or
  both as side effects.

**Bug 4 fix lands BEFORE Phase 3a-infra (MOP).** The Tier 1 synthesis
already names these as the two highest-leverage Tier 1 items. They are
independent — Bug 4 is in TypeInference.pm; Phase 3a-infra is in
Context.pm + SemanticAction.pm + Actions.pm. They can be parallelized.
However, Bug 4 unblocks IR-cluster parses needed by Phase 3c tests, so
sequencing it earlier is safer.

**Bug 4 fix lands BEFORE Decision 4 (contract strengthening) on
TypeInference.** TypeInference's contract migration (mixed-types →
uniform Context return) will touch the `_complete_type` method. Doing
contract migration on top of an unfixed Bug 4 means migrating the wrong
behavior. Doing Bug 4 fix first means contract migration starts from
correct behavior.

**Bug 4 fix lands BEFORE Decision 5 (flow-typing completion).** Flow-
typing will replace `_complete_type`'s tree-walk approach entirely.
Patching Bug 4 now is a stopgap. If flow-typing completion gets queued
ahead of any further IR-cluster work, Bug 4 fix could be skipped — but
that requires a concrete date for flow-typing, which we don't have.
Default: patch now, expect to delete the patch when flow-typing lands.

**Final ordering**:

1. **Now**: Bug 4 fix (this plan, ~2-4 hours, single-method change)
2. **Now or parallel**: Phase 3a-infra (MOP $graph/$scope to Context fields)
3. **Now or parallel**: Bug 1 + Bug 2 fix (re-evaluate after Bug 4 lands)
4. **Subsequent**: TypeInference contract migration (Decision 4)
5. **Eventual**: Flow-typing completion (Decision 5) — Bug 4 patch can be
   removed during this work

## Probe artifacts

The following probe scripts were created and run during this RCA. All
produce reproducible results against the current `worktree-pu` HEAD. They
are saved in `/tmp/` and intended to be deleted at end of session:

- `/tmp/bug4-verify.pl` — reproduces the audit's per-stage discrimination
- `/tmp/bug4-rca.pl` — instruments TI._complete_type, prints the
  call_symbol/item_types/list_arity values found at each CallExpression
  complete event
- `/tmp/bug4-walk.pl` — visualizes the shared Context tree that
  `_walk_annotations` traverses, for the `[B,T,A]` failing case
- `/tmp/bug4-pop-test.pl` — confirms why `pop`/`keys`/`return`/`sort`
  do not trigger the bug (different parse rule paths or coincidental
  type compatibility)
- `/tmp/bug4-final-verify.pl` — sweeps a battery of BLOCK contents to
  confirm the trigger condition is "BLOCK contains a CallExpression alt=1
  with explicit ExpressionList" rather than "specific named builtin"
