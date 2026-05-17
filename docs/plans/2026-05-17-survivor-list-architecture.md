# Survivor-List Disambiguation Architecture

**Date**: 2026-05-17
**Status**: Plan / proposal
**Authors**: perigrin + Claude
**Depends on**: docs/plans/2026-04-12-unified-context-design.md, docs/plans/2026-04-24-semiring-contract-drift.md (May 9 addendum)
**Supersedes**: ad-hoc Boolean-carve-out proposals (see "Rejected approaches" below)

## Problem

The filter-stack disambiguation algorithm in `FilterComposite._filter_compare`
(lines 218-288) does **first-wins early-termination**: it iterates components
in priority order and stops at the first component whose `add` returns a
result identical to one input, reading that as a verdict.

Two of the five components (Boolean, Structural) return `$left` by
convention when they have no opinion on disambiguation. The composite's
identity-check (`refaddr($result) == refaddr($left)`) cannot distinguish
"this component picked left" from "this component returned $left
because it has no API to express 'no opinion.'" The conflation silently
short-circuits subsequent components.

For `push @arr, $obj->method();` (51 fires of
`_push_methodcall_inward.peel_builtin` across the IR/MOP/Grammar corpus):

- Boolean's `add` returns `$left` for two non-zero alternatives (Boolean
  has no opinion — both are valid recognitions)
- FilterComposite reads this as "Boolean picked left, left_loses"
- The chart cell is set to the wrong derivation
- `Precedence`, `TypeInference`, `Structural`, `SemanticAction` are
  never consulted
- `Structural` would have picked the right derivation (commit b3d00ab9
  reordered its tag preferences so it correctly prefers IS_LIST over
  IS_METHOD when both are IS_CALL), but its opinion is never registered
- `_push_methodcall_inward.peel_builtin` walker fires post-parse to
  rebuild the correct shape

The walker is the cost of this conflation.

## What the design says

`docs/plans/2026-04-12-unified-context-design.md` §"add — disambiguation"
(lines 134-164) describes the correct algorithm:

> FilterComposite's add is the product of each component's add:
> `product map { $_->add($left, $right) } @components`
>
> Each component's `add` reads its annotation slot from both
> alternatives and returns its result (like Viterbi picks the higher
> probability). The product of all results determines the outcome:
>
> - Any component returns zero → product is zero → alternative eliminated
> - All components return non-zero → alternative survives
>
> Each component disambiguates independently on its own concern.
> Validity is the product of all components.

And:

> As an optimization, components can be evaluated in order from most
> likely to return zero (Boolean, Precedence, TI, Structural, SA). If
> any component returns zero, the product is zero — remaining components
> can be skipped. **This is short-circuit evaluation of the product, not
> a semantic ordering.**

And on what happens when components disagree about which to keep:

> If no component can disambiguate (both alternatives are equivalent
> from every component's perspective), this is unresolved ambiguity.
> The Context can pack both alternatives and flag `is_ambiguous`.
> Higher rules get a chance to resolve it through subsequent
> multiplies. Only if ambiguity reaches `Program` does the parser
> throw an exception.

This is the **survivor-list** model: alternatives survive component-wise
based on non-zero verdicts; multiple survivors get packed into an
ambiguous Context that downstream multiplies resolve.

## What the implementation does (the gap)

`FilterComposite._filter_compare` (lines 218-288):

```perl
for my $sr ($self->_annotation_semirings()) {
    # ...
    my $result = $sr->add($li, $ri);
    # ...
    return $r_eq_left ? 'right_loses' : 'left_loses';  # line 276
}
```

This is **first-wins-early-return**, not **product-over-components**.
The doc explicitly says short-circuit is permitted ONLY when a component
returns zero (eliminating the alternative). The implementation
short-circuits on *any* identity-equal result, which is a different
thing.

The acknowledgment comment at lines 298-303 admits:

> _filter_compare uses first-wins early return rather than the design
> doc's check-all-with-conflict-detection. This is safe because all
> semirings are ordered by priority and conflicts between semirings
> have not been observed across the full 1,867-test regression suite.

The 51 walker fires falsify "conflicts have not been observed." They
were always observed — the walker is the observation. The conflict is
"Boolean has no opinion, but its no-opinion is read as a verdict that
suppresses Structural's actual opinion."

## Component `add` audit

Per audit dispatched 2026-05-17:

| Component | Returns when both non-zero with no opinion | Status |
|---|---|---|
| Boolean | `$left` (convention) | **conflation** — read as verdict |
| Precedence | `[$left]` (single-element arrayref) | honest single-element, FC interprets as verdict |
| TypeInference | `[$merged]` (new Context, ≠ either input) | honest "neither," FC's slot-skip carve-out at line 234 redundant |
| Structural | `$left` (integer fallback at line 245) | **conflation** — same bug as Boolean |
| SemanticAction | `[$left, $right]` (survivor list, line 322) | honest survivor list — **only component honoring the contract** |

Boolean and Structural have the conflation bug. SemanticAction already
returns survivor lists when both non-zero — but FilterComposite never
reaches it because Boolean short-circuits at component 1.

## Where the per-class-resolution and survivor-list framings meet

The architecture docs sometimes give the impression of two conflicting
stories:

- `docs/architecture/ambiguity-classes.md` says each of 7 ambiguity
  classes has a dedicated filtering semiring responsible for it; by SA
  time, no ambiguity remains.
- `docs/plans/2026-04-12-unified-context-design.md` says the chart can
  pack alternatives as ambiguous when no component disambiguates;
  higher multiplies resolve.

These are the same architecture viewed from different ends. The
per-class framing describes which component has *authority* to rule on
each ambiguity class. The survivor-list framing describes what happens
*between* rulings — when locally no component has authority, the
alternative is packed for a higher rule to resolve. "By SA time, no
ambiguity remains" is a statement about the *end* of the filter chain:
after all components have run, after all higher-rule multiplies have
narrowed, the survivor set has been reduced to one. Both descriptions
are true; the survivor-list mechanism is how the per-class authority
gets *applied* across rules.

The current implementation's bug isn't that it tries to enforce per-class
resolution; it's that it terminates the per-class search *prematurely*
because it can't distinguish "this class declines to rule" from "this
class rules for left."

## Migration plan

The smallest-first-step recommended by the audit:

**Phase 1: Audit instrumentation (no behavior change).** Add an
env-flagged `CHALK_FILTER_PRODUCT=1` mode to `FilterComposite._filter_compare`
that runs the full product algorithm (all components consulted) in
parallel with the current first-wins behavior. Compare verdicts.
Record:

- How many merges would produce a different verdict under product mode
- How many merges would produce a "conflict" (component A says left,
  component B says right)
- How many merges would produce "all-no-opinion" (every component says
  both-survive)

Behavior is unchanged in this phase — only instrumentation. Land the
counter, run the audit on the IR/MOP/Grammar corpus, record numbers
in a follow-up addendum to this plan. This bounds the work below.

**Phase 2: Honest no-opinion returns from Boolean and Structural.**
Make Boolean's `add` return a new non-zero Context (not `$left`) for
two non-zero alternatives. Make Structural's `add` return a non-zero
sentinel (e.g., a synthesized Context wrapper, or use the existing
"return new value not equal to either input" idiom that TI uses) when
it has no opinion. This is the smallest contract change that lets the
existing `_filter_compare` route through to subsequent components.
TDD bilateral unit tests on each component's `add` contract.

After Phase 2, run `script/chalk-fixup-audit lib/Chalk/IR lib/Chalk/MOP
lib/Chalk/Grammar` — `_push_methodcall_inward.peel_builtin` count
should drop substantially as Structural's IS_LIST-over-IS_METHOD
preference (from commit b3d00ab9) now actually reaches the verdict.

**Phase 3: Replace first-wins with product semantics.** Remove the
early-return at FilterComposite line 276. Collect verdicts from all
components. If any component says left/right, that's the verdict.
If multiple components return opinions that disagree, raise a hard
parse error (the "conflict" case the design promised would not happen;
if it does, we have a real bug). If all components return
both-survive, pack as ambiguous.

This phase requires the packed-Context shape. Per the design doc's
open question at line 278: "Is `children => [$left, $right]` with
`is_ambiguous => true` sufficient, or do we need a distinct packed
node type?" Recommend starting with the simpler form; refactor if it
proves insufficient.

**Phase 4: Downstream tolerance.** Each `multiply` call site in
Earley.pm (lines 624, 899, 1182, 1237, 1312, 1449) and Context.pm's
multiply must tolerate packed-ambiguous Contexts on either side.
Either by distributing the multiply over the alternatives
(`multiply(packed(A,B), C) = pack(multiply(A,C), multiply(B,C))`) or
by each component semiring's multiply handling the packed shape.
Distribution is the design-doc-aligned approach (semirings work on
single values; the composite distributes).

**Phase 5: End-of-parse resolution.** If a packed-ambiguous Context
reaches the `Program` rule's completion, the parse is genuinely
ambiguous. Throw a structured exception with both alternatives in
the message. Until this phase lands, packed contexts can simply
propagate; the walker will continue to do its job for any that survive.

**Phase 6: Walker retirement.** Once Phase 3 lands and the audit
confirms the relevant walker counters drop to zero, delete the
corresponding walker branches in `lib/Chalk/Bootstrap/Perl/Actions.pm`.

## Acceptance criteria

- **Phase 1**: instrumentation lands; audit numbers recorded in plan
  addendum
- **Phase 2**: Boolean and Structural `add` return honest no-opinion
  signals; unit tests assert the new contracts; spec tests still pass
- **Phase 3**: FilterComposite uses product semantics; conflict detection
  raises errors; ambiguity packing implemented
- **Phase 4**: every multiply call site handles packed contexts; spec
  tests still pass with parses that exercise the packed path
- **Phase 5**: ambiguous-at-Program raises structured exception with
  both derivations
- **Phase 6**: `_push_methodcall_inward.peel_builtin` (51 fires today)
  and `_push_deref_inward.peel_builtin` (11 fires today) drop to zero
  on the IR/MOP/Grammar corpus; corresponding walker code deleted

## Risks and rejected approaches

**Rejected: Boolean carve-out in FilterComposite.** Adding a `next if
$slot eq 'boolean'` matching the existing TI carve-out at line 234
would fix the immediate Boolean issue but leave Structural's identical
bug in place, and would calcify the carve-out pattern as the architecture
rather than treating it as a symptom of the missing product semantics.

**Rejected: `prefer($l, $r)` as separate preference method.** Adding a
new disambiguation protocol distinct from `add` would work but is more
code than necessary — the existing `add` contract is correct per the
design doc; only `_filter_compare`'s misreading of it needs to change.

**Risk — performance**: product semantics consult every component on
every merge instead of short-circuiting on first verdict. Worst case
~5x add calls per merge. Mitigation: keep the "any component returns
zero → product is zero → skip remaining" short-circuit, which is
explicitly permitted by the design doc. Only the spurious early-return
on identity-equal results goes away.

**Risk — undiscovered conflicts**: Phase 1 may reveal that the
"conflicts have not been observed" assertion was true only because
first-wins was masking them. If product mode reveals real conflicts
in the corpus, that's a real bug surfaced by this work — and the
right fix is to find which component's `add` is incorrect, not to
revert to first-wins.

**Risk — packed-Context shape choice**: the design doc's open question
at line 278 hasn't been answered. Phase 3's recommendation of
`children => [L, R]` + `is_ambiguous => true` is the cheap experiment;
if downstream multiply distribution proves awkward, the packed shape
may need iteration.

## Relationship to prior plans

- **2026-04-24-semiring-contract-drift.md May 9 addendum**: this plan
  is the disambiguation-completeness contract migration that addendum
  refers to. The return-shape contract (zero/one/multiply) migration
  is independent and tracked there.
- **2026-04-12-unified-context-design.md**: this plan is the
  implementation of §"add — disambiguation" (lines 134-164) which the
  current `_filter_compare` does not implement.
- **2026-05-09-fixup-audit-baseline.md**: this plan's success criterion
  is the reduction of the per-fixup-branch counters from that baseline.

## Addendum 2026-05-17b: Phase 2 is not independently shippable

Attempted Phase 2 in isolation (TDD red, change Boolean's `add` to
return a synthesized non-zero Context for two-non-zero inputs, change
the unit test). Result:

- The TDD test went GREEN as expected
- The wider spec-test sweep showed regressions:
  - `t/bootstrap/precedence-spec-incdec-bind.t`: 17/18 passing → 17/18
    with `++$x + 1` now producing wrong shape (`++$x` no longer the
    left of the Add)
  - `t/bootstrap/perl-actions-fixup.t`: bilateral push-method-arg case
    produced TWO top-level statements instead of one
    (`Call(push, [@arr])` and `MethodCall($obj, method)` as siblings),
    plus an existing test went from passing to failing
- Probe of `push @arr, $obj->method();` showed the parse now fragments
  into `Call(push, [@arr])` and `MethodCall($obj, method)` as separate
  top-level statements — strictly worse than the pre-fix behavior
  (which was the wrong-shape-but-single-statement that the walker
  corrected)

### Why

Boolean's `$left`-by-convention return wasn't just suppressing
verdicts for the 51 peel_builtin cases — it was also serving as the
de-facto tie-break for many other ambiguous merges where Boolean
happened to return the "right" derivation by luck of iteration order.
When Boolean stops returning `$left`, all those merges fall through
to subsequent components, and either:

1. A subsequent component DOES express a verdict that happens to be
   wrong for those cases (the precedence-spec-incdec-bind regression)
2. NO subsequent component expresses a verdict, and FilterComposite's
   "all components abstained" fallback kicks in (line 285-292: "left
   is returned as a deterministic tie-break") — but with *different*
   iteration timing because the chart now has more surviving
   derivations to merge

The walker stack is more entangled with Boolean's accident-of-convention
than the original phase decomposition accounted for. Phase 2 in
isolation makes the system strictly worse: it doesn't enable walker
retirement (other components' verdicts don't reliably produce the
right shape either), and it breaks previously-passing parses.

### Implication for migration ordering

**Phase 2 must land together with Phase 3 + Phase 5**, not as a
standalone change. The combined change set is:

- Boolean and Structural return honest no-opinion (Phase 2)
- FilterComposite uses product semantics, packs ambiguous when all
  components abstain (Phase 3)
- Packed-ambiguous Contexts in chart cells propagate to next multiply
  (Phase 4 — Earley call sites + Context.multiply distribution)
- `Program` rule completion raises structured exception on remaining
  ambiguity (Phase 5)

Only with all four in place does the system have a working policy
for the cases Phase 2 alone breaks. The audit instrumentation (Phase
1) remains the right first standalone deliverable; it bounds the
work for the combined Phase 2-5 commit without changing behavior.

### What was tried and reverted

- Boolean.pm `add`: changed to return new Context for two non-zero,
  reverted (the trigger-case parse fragmented worse, plus 4
  previously-passing tests regressed)
- semiring-boolean.t: added bilateral no-opinion test, reverted (test
  was correct in isolation but cannot pass without the rest of the
  Phase 2-5 stack)

The intent and direction were correct; the scoping was wrong. The
revised plan: Phase 1 first (instrumentation), then Phase 2-5
combined.
