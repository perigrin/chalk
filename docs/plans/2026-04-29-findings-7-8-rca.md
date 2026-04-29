# Findings 7 and 8 RCA and Remediation Plan

**Date:** 2026-04-29
**Findings:** Finding 7 (`defined func($x, @arr)`), Finding 8 (anonsub with
ternary as call argument)
**References:**
- Audit 2 IR-cluster addendum: docs/plans/2026-04-25-audit-2-semirings-findings.md
- Bug 4 RCA: docs/plans/2026-04-25-bug-4-rca-and-remediation.md
- Bug 1+5 RCA: docs/plans/2026-04-26-bug-1-and-5-rca-and-remediation.md
- Audit 5: docs/plans/2026-04-25-audit-5-semiring-contract-reality-findings.md
- Synthesis: docs/plans/2026-04-25-phase-a2-synthesis.md
**Status:** RCA complete. Remediation proposed. Not implemented.

## Verification of probe findings under current state

Both findings reproduce against current `worktree-pu` HEAD (commits
`fa068a16` audit notes + `ff8f1f49` Fix B + `ac0e66ce` Fix A on top of
`d7432d43` Bug 5 + `a1013c4f` Bug 1 + `885beb87` Phase 3a-infra +
`1ec8cae1` Bug 4).

### Finding 7 reproduction

Probe: `/tmp/findings-7-8-stage.pl` (Boolean parser vs full FilterComposite
parser, both on the current HEAD).

| Case | Boolean | Full Stack | Verdict |
|---|---|---|---|
| `defined func()` | passes | passes | PASS |
| `defined func($x)` | passes | passes | PASS |
| `defined func($x, $y)` | passes | passes | PASS |
| `defined func($x, "lit")` | passes | passes | PASS |
| **`defined func($x, @arr)`** | **passes** | **fails** | **SEMIRING REJECTS** |
| **`defined func(@arr)`** (single Array arg) | **passes** | **fails** | **SEMIRING REJECTS** |
| **`defined func(@a, @b)`** | **passes** | **fails** | **SEMIRING REJECTS** |
| **`defined func($x, %h)`** | **passes** | **fails** | **SEMIRING REJECTS** |
| **`defined func("a", "b", @arr)`** | **passes** | **fails** | **SEMIRING REJECTS** |

The brief's framing — "multi-arg call with at least one array variable" —
is partially correct but not the trigger. The actual trigger is narrower:
**the inner `func(...)` call has any argument whose type is `Array` or
`Hash` (i.e., not a subtype of `Scalar`), AND the outer head is
`defined` or `ref` (which require `Scalar` args)**. Single-arg
`defined func(@arr)` rejects too. Multi-arg with two scalars
(`defined func($x, $y)`) passes. The "multi-arg" framing reflects the
common shape but is not the necessary condition.

The probe also confirms only `defined` and `ref` trigger; `scalar` does
not (its arg_types is `['Any']`, which permits anything).

### Finding 8 reproduction

| Case | Boolean | Full Stack | Verdict |
|---|---|---|---|
| `func($x, sub ($n) { return $n; })` | passes | passes | PASS |
| `func($x, sub ($n) { my $y = $n; return $y; })` | passes | passes | PASS |
| **`func($x, sub ($n) { return defined $n ? 1 : 0; })`** | **passes** | **fails** | **SEMIRING REJECTS** |
| **`func($x, sub ($n) { return defined $n; })`** (no ternary) | **passes** | **fails** | **SEMIRING REJECTS** |
| **`func($x, sub ($n) { defined $n; return 1; })`** (defined as stmt) | **passes** | **fails** | **SEMIRING REJECTS** |
| `func($x, sub ($n) { return scalar $n ? 1 : 0; })` | passes | passes | PASS |
| `func($x, sub ($n) { return !$n ? 1 : 0; })` | passes | passes | PASS |
| `print($x, sub { return defined $_[0] ? 1 : 0; })` (known builtin host) | passes | passes | PASS |
| `func(do { defined $x; })` (do-block, not anonsub) | passes | passes | PASS |
| `my $f = sub ($n) { return defined $n ? 1 : 0; }` (no host call) | passes | passes | PASS |
| `$obj->m(sub ($n) { return defined $n ? 1 : 0; })` (MethodCall host) | passes | passes | PASS |
| `$h[0]->(sub ($n) { return defined $n ? 1 : 0; })` (Subscript-call host) | passes | passes | PASS |

The brief's framing — "anonsub-as-argument-to-call where the anonsub
body contains a ternary expression" — is incorrect. The ternary is not
necessary: `func($x, sub { defined $_; return 1; })` rejects without a
ternary. The actual trigger is more specific:

1. The host is a `CallExpression` (alts 0 or 1) whose head is **not** a
   known builtin in `Chalk::Grammar::Perl::TypeLibrary`.
2. The host call has at least 2 arguments, where the second-or-later arg
   is an `AnonymousSub`.
3. The anonsub body contains a `CallExpression` to a known builtin whose
   `arg_types` is restrictive (e.g., `defined`/`ref` with `arg_types =
   ['Scalar']`).

The "ternary" in the brief was an incidental detail. The "F8" and "F7"
brief framings both have surface symptoms that obscure the underlying
mechanism.

## Finding 7 root cause

Probes: `/tmp/findings-7-instrument.pl`, `/tmp/findings-7-walk-trace.pl`.

The OUTER `defined func($x, @arr)` parses as `CallExpression alt=1`
(`Identifier WS ExpressionList`), with the inner `func($x, @arr)` as a
`CallExpression alt=0` inside the outer ExpressionList. The outer
`CallExpression`'s `_complete_type` (TypeInference.pm:355–404) calls
`_get_item_types($value)` to validate args against `defined`'s
signature `{arg_types => ['Scalar'], min_arity => 1}`.

The shared Context tree at the outer CallExpression's complete event
contains the OUTER `ExpressionList alt=0`'s annotation:

```
[ExpressionList alt=0] returns {item_types=[Array],list_arity=1,valid=1}
```

That `[Array]` is **leaked from the inner CallExpression's tree** via
`_get_rightmost_type` in `TypeInferenceActions.pm:31–37`:

```perl
my sub _get_rightmost_type($ctx) {
    return _walk_ann($ctx, sub ($n) { ... return $ti->{type}; }, true);
}
```

The walker `_walk_ann` (TypeInferenceActions.pm:15–27) **does not
support a prune callback at all**. When the outer ExpressionList's
`alt=0` action runs (`{item_types => [_get_rightmost_type($ctx)]}`),
the walker descends through the inner `func(...)` CallExpression result
node — which carries `{valid=>1}` (no `type`, since `func` has no
TypeLibrary signature) — and into the inner ExpressionList's
descendants, finding the rightmost typed scan node: `@arr` → `Array`.

`Array` then becomes the outer ExpressionList's sole `item_types` slot.
At the outer CallExpression's signature check:

```perl
my $expected = $arg_types->[0] = 'Scalar';
type_satisfies('Array', 'Scalar')  # false
return undef;                        # ZERO
```

`Array is_subtype Scalar` is false, and `Array` is not in
`%POLYMORPHIC_TYPES` (`Scalar`, `Any`, `List`), so the polymorphic
branch doesn't apply. The List-flattening permissive clause from Bug 1
also doesn't apply (`Scalar` is not `List`).

**Single-sentence root cause:** `_get_rightmost_type` (used by
`Atom`/`Expression`/`PostfixExpression`/`ParenExpr`/`Block`/`Signature`/
`Attribute`/`BinaryExpression` actions in `TypeInferenceActions.pm`)
walks freely past completed sub-CallExpression boundaries because its
walker `_walk_ann` does not support the `_is_completed_sub_expr` prune
that `_get_item_types`/`_get_list_arity` got from the Bug 4 fix; this
leaks the inner call's argument types up to the outer wrapper's `type`
tag.

## Finding 8 root cause

Probes: `/tmp/findings-8-instrument.pl`, `/tmp/findings-8-isolate.pl`,
`/tmp/findings-8-triangulate.pl`.

The OUTER `func($x, sub ($n) { ... defined $n ... })` parses as
`CallExpression alt=0` with two args. The anonsub argument's body
contains an inner `defined $n` `CallExpression alt=1`.

When the outer CallExpression's `_complete_type` runs at
`TypeInference.pm:366`:

```perl
my $call_sym = $self->_get_call_symbol($value);
```

it calls `TypeInference::_get_call_symbol` (line 108–115):

```perl
return _walk_annotations($ctx, sub ($n) {
    my $type = $n->annotations()->{type};
    return undef unless defined $type && ref($type) eq 'HASH';
    return $type->{call_symbol};
});
```

This walker **does not pass a `$prune` argument** (unlike
`_get_item_types`/`_get_list_arity`, which were given the
`$is_completed_sub_expr` prune in Bug 4). The walker descends into the
AnonymousSub argument's body, finds the scan node for `defined` (which
was tagged `call_symbol=defined` by `_scan_ctx_call_ident` at scan time),
and returns it.

Now `$call_sym = 'defined'` for the OUTER `func(...)` call. TI looks up
`defined`'s signature `{arg_types => ['Scalar'], min_arity => 1}` and
applies position-by-position validation to the OUTER call's args
`[Scalar, Code]`:

- Position 0: expected `Scalar` (arg_types[0]), got `Scalar` (`$x`'s type) → OK.
- Position 1: arg_types[1] undef, falls back to `arg_types[-1] = 'Scalar'`,
  got `Code` (anonsub's type). `type_satisfies('Code', 'Scalar')` →
  false. ZERO.

A second leak path exists: `Atom`'s action in
`TypeInferenceActions.pm:86–93`:

```perl
method Atom($ctx) {
    my $child_type = _get_rightmost_type($ctx);
    my $call_sym = _get_call_symbol($ctx);
    return { valid => true,
        ($child_type ? (type => $child_type) : ()),
        ($call_sym   ? (call_symbol => $call_sym) : ()),
    };
}
```

`_get_call_symbol` here is the local one in TypeInferenceActions.pm
(line 78–84), also walking freely without a prune. The probe shows:

```
[AnonymousSub alt=0] returns {type=Code,valid=1}
[Atom alt=0] returns {call_symbol=defined,type=Code,valid=1}  # <-- leak
```

The Atom over the anonsub leaks `call_symbol=defined`; same propagation
through `Expression`. So even before the outer CallExpression's own
`_get_call_symbol` walks, the leak has already been established in the
intermediate Context tree's annotations.

**Why the trigger is narrow:** The outer call's head must be unknown
(no own `call_symbol` from its scan) so the leak isn't shadowed by the
correct value. The known-builtin case (e.g., `print(...)`) passes
because `print`'s `call_symbol=print` is set at scan time and visible
via the same walker before the inner leak (or because `print`'s
signature `arg_types => ['Any']` permissively accepts the second arg).
The MethodCall/Subscript-call host case passes because those rules
don't go through the `CallExpression` branch of `_complete_type`. The
do-block case has only one arg (the do-block's return type Bool
satisfies `defined`'s Scalar requirement). The bare anonsub case has no
host call.

**Single-sentence root cause:** `_get_call_symbol` (in TypeInference.pm
and TypeInferenceActions.pm) walks freely past AnonymousSub/completed-
sub-expression boundaries because it doesn't apply the
`_is_completed_sub_expr` prune; the inner builtin's `call_symbol` leaks
up and the outer (unknown-head) call gets validated against the wrong
signature.

## Coupling analysis

**Findings 7 and 8 are the same root cause** in two different walker
methods:

- Finding 7's leak: `_get_rightmost_type` in TypeInferenceActions.pm
  (walker `_walk_ann` with no prune support) used by ExpressionList
  alt=0/`Expression`/`Atom`/several boundary rules.
- Finding 8's leak: `_get_call_symbol` in TypeInference.pm and
  TypeInferenceActions.pm (walker `_walk_annotations` called without a
  prune argument; also `_walk_ann` with no prune support) used directly
  by `_complete_type`'s CallExpression branch and indirectly via Atom
  action.

Both are instances of the **same defect class**: walkers that should
treat completed sub-CallExpressions/AnonymousSubs as opaque leaves but
don't. The Bug 4 fix added prune support to `_walk_annotations` (in
TypeInference.pm) and applied it to two callers (`_get_item_types`,
`_get_list_arity`). Findings 7 and 8 are the **other walker callers
that were not converted** during that Bug 4 fix.

There are nine walker callers across the two files (see "Latent
rejection risk" below); only two were given the prune. The remaining
seven are all candidates for the same defect class. Findings 7 and 8
are the manifestations the audit happened to surface.

**Cross-effect tests:**

1. Does fixing Finding 7 (adding prune to `_get_rightmost_type`) retire
   Finding 8? No. Finding 8 leaks via `_get_call_symbol` (a different
   walker), and `_get_rightmost_type` is not on Finding 8's leak path.
   Probe: `func($x, sub { defined $_; return 1; })` would still find
   `call_symbol=defined` even with `_get_rightmost_type` pruned.
2. Does fixing Finding 8 (adding prune to `_get_call_symbol`) retire
   Finding 7? No. Finding 7 leaks via `_get_rightmost_type`'s `type`
   tag walk. Probe: `defined func($x, @arr)` would still find
   `type=Array` even with `_get_call_symbol` pruned.
3. Are both manifestations of "Bug 4 walker fix didn't cover all the
   cases"? **Yes.** The Bug 4 fix's mechanism (the
   `_is_completed_sub_expr` predicate + depth-aware
   `_walk_annotations`) is correct. It just wasn't applied to all the
   walker callers that need it.

**Recommendation:** treat Findings 7 and 8 as one defect class (walker
prune coverage gap), fix all callers in one PR rather than as two
separate fixes. This is the same shape as the Bug 4 fix but extended
to the remaining callers.

## Categorization per finding

### Finding 7 — Category A (TI logic bug)

The defect is in TypeInferenceActions.pm's `_walk_ann` (no prune
support) and its callers (`_get_rightmost_type` etc.). The
TypeLibrary's `defined`/`ref` signatures are correct. The defect is
that the walker leaks types from completed sub-CallExpressions into the
outer wrapper, polluting `item_types`. With overlap to **Category D
(Decision-5 territory)**: when flow-typing replaces the tree-walk
mechanism, the leak path doesn't exist (each CallExpression's signature
check is on its own typed args, not via tree-walk); but Decision 5 is
multi-issue away.

### Finding 8 — Category A (TI logic bug)

Same analysis. The defect is in `_get_call_symbol` (both copies,
TypeInference.pm and TypeInferenceActions.pm) walking without the
prune. The signatures involved are correct. Decision 5 dissolves this
too.

## Proposed remediation

Both findings are leak-via-walker-without-prune. The remediation is the
same shape as the Bug 4 fix but extended to all walker callers.

### Unified fix (recommended)

**Files affected:**
- `lib/Chalk/Bootstrap/Semiring/TypeInference.pm`
- `lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm`

**Step 1: Add prune support to `_walk_ann` in TypeInferenceActions.pm.**

`_walk_ann` (line 15–27) does not currently accept a prune callback. It
must be extended to match `_walk_annotations` in TypeInference.pm:

- Accept an optional `$prune` parameter.
- Track depth via stack of `[node, depth]` pairs.
- Skip nodes (and their subtrees) when `$depth > 0 && $prune->($node)`.

This keeps the depth-0 root-prune protection that Bug 5 introduced.

**Step 2: Define a shared `_is_completed_sub_expr` predicate (or
replicate in TypeInferenceActions.pm).**

The predicate at TypeInference.pm:125–129 is:

```perl
my $is_completed_sub_expr = sub ($n) {
    my $type = $n->annotations()->{type};
    return false unless defined $type && ref($type) eq 'HASH';
    return exists $type->{valid} && !exists $type->{item_types};
};
```

Replicate in TypeInferenceActions.pm. Two reasonable shapes:

- **Shape A (preferred):** lift the predicate to a shared utility and
  import it in both files.
- **Shape B (smallest diff):** copy-paste the predicate.

Shape A is cleaner. Shape B is more localized. Shape A risks adding a
shared utility module that flow-typing will eventually replace; Shape B
keeps the duplication local. Recommend Shape B as the smallest diff,
flagging the duplication for cleanup when flow-typing lands.

**Step 3: Apply the prune to all walker callers that need it.**

In TypeInference.pm:
- `_get_call_symbol` (line 108–115): pass `$is_completed_sub_expr` as
  the prune.
- `_get_rightmost_type` (line 157–164): pass `$is_completed_sub_expr`.

In TypeInferenceActions.pm:
- `_get_rightmost_type` (line 31–37): pass `$is_completed_sub_expr`.
- `_get_leftmost_type` (line 41–47): pass `$is_completed_sub_expr`.
- `_get_call_symbol` (line 78–84): pass `$is_completed_sub_expr`.
- `_get_op_text` (line 66–72): consider — used for BinaryExpression's
  operator, less likely to leak since op_text is set on operator scan
  nodes that are siblings of the operands. Probably safe to add prune
  defensively.
- `_get_ident_text` (line 51–57): consider — used for method names. The
  method-name lookup probably wants to find within the current rule's
  scope only; same defensive add.

In TypeInferenceActions.pm helpers that explicitly look at item_types:
- `_get_list_arity` (line 139–145): pass `$is_completed_sub_expr`.
- `_get_item_types` (line 149–155): pass `$is_completed_sub_expr`.
- `_get_prev_item_types` (line 159–165): pass `$is_completed_sub_expr`.

**Step 4: Verify prune predicate handles AnonymousSub return values.**

The AnonymousSub action returns `{ valid => true, type => 'Code' }`. The
predicate `valid && !item_types` is true (has valid, no item_types). So
the predicate WILL fire for AnonymousSub result nodes. Good — that's
what Finding 8 needs.

But check the more specific cases: ParenExpr returns `{ valid, type? }`,
Block returns `{ valid, type? }`. These also have `valid && !item_types`
when used as wrappers. The walker will skip them too. That may break
some tree walks that want to descend into ParenExpr or Block. Audit
this carefully:

- `_get_rightmost_type` should NOT descend into a completed inner
  CallExpression (Finding 7's leak).
- `_get_rightmost_type` may need to descend into ParenExpr/Block in
  some cases (e.g., `$x = (1 + 2);` where the outer Atom action wants
  to find `Num` from the ParenExpr's contents).

There's a tension between "treat ParenExpr/Block as opaque leaf" and
"propagate type from ParenExpr's contents". Examine if the existing
ParenExpr/Block actions already populate `type` on the wrapper node
(yes, they do — `{ valid, type => $child_type }`), and walkers seeing a
wrapper with `type` will return that `type` directly without needing
to descend. So the prune is safe.

Caveat: ParenExpr that wraps an empty list `()` returns `{ valid }`
(no type). The walker will prune it, returning undef. That's OK — the
caller (e.g., outer ExpressionList alt=0) would pass undef as
`item_types[0]` which `_complete_type` already handles.

**Step 5: Run the probe set.**

Confirm Finding 7's failing cases now pass:
- `defined func($x, @arr)`
- `defined func(@arr)`
- `defined func($x, %h)`

Confirm Finding 8's failing cases now pass:
- `func($x, sub ($n) { return defined $n ? 1 : 0; })`
- `func($x, sub ($n) { return defined $n; })`
- `func($x, sub { defined $_; return 1; })`

Confirm Bug 4's cases continue to pass:
- `map { defined $_ } @arr`
- `grep { ref $_ } @arr`
- `map { length $_ } @arr`

Confirm Bug 1's cases continue to pass:
- `map { $_ } (1, 2, 3)`
- `grep { $_ > 0 } (1, -1, 2)`

Confirm Bug 5's cases continue to pass:
- `push(@a, 1)`, `unshift(@a, 1)`, `join(",", @a)`, `substr($s, 0, 3)`

### Alternative shape (not recommended): patch only the two specific findings

Add prune to just `_get_rightmost_type` (TypeInferenceActions.pm) and
`_get_call_symbol` (both files). This fixes Findings 7 and 8 but leaves
five other walker callers as latent bug surfaces. Future work would
trip into the same defect class repeatedly.

The unified fix has the same blast radius (small) and a higher payoff
(retires the defect class, not just two manifestations). The Bug 4 fix
is well-tested and the prune predicate is correct; the work is
mechanical.

## Side effects

### Cross-effect with Bug 4 walker fix (commit `1ec8cae1`)

Bug 4's `_walk_annotations` already supports the prune parameter, and
`_get_item_types`/`_get_list_arity` (in TypeInference.pm) already use
it. Adding the prune to the other TypeInference.pm walkers is
consistent with Bug 4's intent. The depth-0 root protection from Bug 5
(commit `d7432d43`) is preserved.

### Cross-effect with Bug 1 fix (commit `a1013c4f`)

Bug 1's `type_satisfies` change (List-flattening) is independent.
Findings 7 and 8 do not interact with `type_satisfies` semantics — they
manifest at the walker level, which feeds the type into
`type_satisfies`. With correct walker output, the type-satisfies check
runs correctly.

### Cross-effect with Bug 5 fix (commit `d7432d43`)

Bug 5 added `[node, depth]` pairs to `_walk_annotations`'s stack and the
`$depth > 0` gate. The unified fix preserves this. The new prune-using
walkers in TypeInference.pm reuse the same `_walk_annotations`. The new
prune-using walkers in TypeInferenceActions.pm need `_walk_ann` to be
extended with the same depth-aware mechanism (Step 1 above).

### Cross-effect with Fix A (commit `ac0e66ce`)

Fix A is in Precedence semiring (PostfixDeref bracket reset and
`->@[range]`). No interaction with TI walkers.

### Cross-effect with Fix B (commit `ff8f1f49`)

Fix B is in grammar (`$#{EXPR}` array-length-of-deref). No interaction
with TI walkers.

### Cross-effect with Decision 4 (semiring contract migration)

TypeInference's contract migration would touch `_complete_type`. The
unified fix does not change `_complete_type`'s return shape — it
changes how the walkers internal to `_complete_type` and the action
methods behave. Contract migration on top of the fixed walkers is
cleaner than on top of the broken walkers (per the Bug 4 sequencing
recommendation, which still applies).

### Cross-effect with Decision 5 (flow-typing completion)

Both findings dissolve under flow-typing — when each CallExpression
carries its own typed args directly (via SSA-like nodes), there is no
tree-walk-and-leak mechanism. The unified fix is a stopgap that
flow-typing will retire.

### Interaction with grammar-conformance.t

After the fix, files using these patterns should newly pass at the
parse stage. Estimating site count:

- Finding 7's pattern (`defined func(..., @arr)` or similar): rare in
  `lib/`. Most production code uses `defined $var` or
  `defined $var->{key}`.
- Finding 8's pattern (anonsub as call argument with internal builtin):
  more common via `pivot()->(sub { ... defined ... })` shapes; ad-hoc
  callbacks. Estimate ~5-10 files.

The unified fix may also retire latent rejections from the other five
walker callers (op_text, ident_text, leftmost_type, etc.), depending
on whether any production files trip them.

## Acceptance criteria

### Finding 7 — minimum acceptance

1. **Minimal failing cases pass under full stack:**
   - `my $x; my @arr; my $r = defined func($x, @arr); return;`
   - `my @arr; my $r = defined func(@arr); return;`
   - `my $x; my %h; my $r = defined func($x, %h); return;`
   - `my @arr; my $r = ref func("name", @arr); return;`

2. **Working cases continue to pass:**
   - `my $r = defined func();`
   - `my $x; my $r = defined func($x);`
   - `my $x; my $y; my $r = defined func($x, $y);`
   - `my $x; my $r = defined $x;`
   - `my $x; my @arr; my $r = scalar func($x, @arr);` (was already passing)

### Finding 8 — minimum acceptance

1. **Minimal failing cases pass under full stack:**
   - `my $x; func($x, sub ($n) { return defined $n ? 1 : 0; }); return;`
   - `my $x; func($x, sub ($n) { return defined $n; }); return;`
   - `my $x; func($x, sub { defined $_; return 1; }); return;`
   - `my $x; func($x, sub ($n) { return ref $n ? 1 : 0; }); return;`

2. **Working cases continue to pass:**
   - `my $x; func($x, sub ($n) { return $n; });`
   - `my $x; print($x, sub { return defined $_[0] ? 1 : 0; });`
   - `my $x; func(do { defined $x; });`
   - `my $f = sub ($n) { return defined $n ? 1 : 0; };`

### Combined acceptance

1. **All Bug 4 / Bug 1 / Bug 5 acceptance criteria continue to hold.**
   The existing `t/bootstrap/typeinference-walker.t` tests must still
   pass. Add new tests for Findings 7 and 8 to that file.

2. **No regression in `t/grammar-conformance.t`.** PASS count strictly
   does not decrease. Expected to increase by some files (estimated
   3-10).

3. **No regression in any `t/bootstrap/*.t` test.** Especially watch
   for `typeinference-walker.t` (already covers the prune mechanism),
   and any test that exercises ParenExpr/Block boundary behavior.

4. **Probe scripts retire:** `/tmp/findings-7-8-stage.pl`,
   `/tmp/findings-7-8-narrow.pl`, `/tmp/findings-7-instrument.pl`,
   `/tmp/findings-7-walk-trace.pl`, `/tmp/findings-8-instrument.pl`,
   `/tmp/findings-8-isolate.pl`, `/tmp/findings-8-triangulate.pl`,
   `/tmp/findings-8-deeper.pl`, `/tmp/findings-7-8-verify.pl` deleted
   at end of session.

## Sequencing recommendation

**The unified Findings 7+8 fix should land BEFORE A4 (Bug 3) and any
other remaining Tier 1 IR-cluster work.**

Reasoning:

- Findings 7 and 8 sit on the same code paths that A4 / Bug 3 (whatever
  shape that takes) would touch. The walker hygiene improvement is a
  prerequisite for clean follow-up work.
- The fix is mechanical (extend a walker, apply a predicate). It's
  cheaper to do once across all callers than to revisit each time a
  new finding appears in the same defect class.
- The fix retires a category of latent bugs (the seven other walker
  callers without prune), which is high-leverage cleanup before
  flow-typing replaces the mechanism entirely.

**Sequencing relative to other in-flight work:**

- **AFTER all earlier fixes** (Bug 1, Bug 4, Bug 5, Phase 3a-infra,
  Fix A, Fix B): all already landed. ✓
- **BEFORE Decision 4 (semiring contract migration):** same reason as
  Bug 4 — contract migration on top of clean walker behavior is
  simpler.
- **BEFORE Decision 5 (flow-typing completion):** the fix is a
  stopgap; flow-typing replaces the walker mechanism entirely. But
  flow-typing is multi-issue away.
- **BEFORE Phase 3a-migration:** Phase 3a-migration touches Actions.pm
  and SemanticAction; minimal interaction. Can be parallel.

**Combined or separate fixes?** Combine into ONE PR with separate
commits per concern:
1. Commit 1: Extend `_walk_ann` to support prune (TypeInferenceActions.pm).
2. Commit 2: Add `_is_completed_sub_expr` to TypeInferenceActions.pm.
3. Commit 3: Apply prune to all walker callers in TypeInference.pm.
4. Commit 4: Apply prune to all walker callers in
   TypeInferenceActions.pm.
5. Commit 5: Add tests in typeinference-walker.t for Findings 7 and 8.

Splitting commits per file/concern makes review tractable. Bundling
them in one PR keeps the conformance signal contiguous.

## Latent rejection risk

The Bug 5 RCA noted: "fixing the walker may unmask further rejections
in currently-passing builtins/calls." The same risk applies here, with
two faces:

### Risk 1: callers currently relying on the leak

Some passing cases may depend on the type leak through the walker. For
example, if a wrapper rule's `_get_rightmost_type` walk currently finds
a deeply-nested type that the wrapper "should" pass up, adding the
prune may now break that lookup.

A specific concern: ParenExpr's action explicitly looks at
`_get_rightmost_type` to find the inner expression's type. With the
prune fired at any inner CallExpression's wrapper, the ParenExpr would
get `undef` instead of the inner type. Probe: `my $x = (defined $y);`
— does this still work? The ParenExpr's $value is the inner CallExpr's
result `{type=>Bool, valid=>true}`. The walker hits this directly and
returns Bool (it's the root of the walk, not a descendant — depth=0,
prune skipped). So this case is fine.

But for `my $x = ((defined $y));` (double parens): outer ParenExpr
walks an inner ParenExpr's value tree. Inner ParenExpr returns
`{type=>Bool, valid=>true}` — has type, so the walker finds it
immediately at the root or near it. Fine.

What about `my $x = func((defined $y), 1);`? Outer call walks a tree
containing the ParenExpr (`(defined $y)`) result. The ParenExpr result
has `type=>Bool`. The walker finds Bool. Fine.

What about cases where the wrapper deliberately passes through an
inner type? Audit needed across the action methods for cases where the
wrapper expects to descend past an inner CallExpression's wrapper.

### Risk 2: other walker callers

Of the remaining seven callers, some will manifest as new failures
under the unified fix only if their leak path was masking a different
defect. Run the spot-check probe (`/tmp/spot-check-v3.pl`) and the
grammar-conformance suite before and after to surface any regressions.

### Risk 3: ternary in F8 was incidental

The brief framed F8 as "ternary inside anonsub body". The actual
trigger is "any builtin call inside anonsub body" (and the anonsub
must be a non-first arg to a non-builtin host call). When the unified
fix lands, the F8 trigger set retires entirely, but a careful
implementer should sweep for related shapes:

- **Recursive anonsub-in-call-in-anonsub**: `func(sub { other(sub
  { defined $x; }); });` — does the leak compound? Probe needed.
- **Anonsub returning anonsub**: `func(sub { return sub { defined $x;
  }; });` — does the inner inner leak through both anonsub
  boundaries? Probe needed.
- **Block-form CallExpression hosts**: `func sub ($n) { defined $n; }
  $arg;` (alt 2) — already shown to reject (probe `F8 FAIL: func sub
  ($n) ...`); the unified fix should retire this too.

### Probe of latent risk

Recommended pre-implementation probe: run the spot-check across the 27
files that currently fail at parse stage (the IR-cluster + others).
Identify which ones change verdict under the unified fix. Then run the
post-fix grammar-conformance to see net delta.

## Connection to Audit 5 findings

### Audit 5 Finding 1 (TI position-dependence)

Both findings manifest only when TI is in `_annotation_semirings()`
(not when TI is `_sa()`). Consistent with Bug 1/4/5. The fix does not
address position-dependence — it fixes what the walker does when the
walker fires. Same as previous fixes: the position-dependence
documentation update remains valid.

### Audit 5 Finding 5 (side effects)

The fix is pure. No side effects added or removed. TypeInference's
`%_method_returns` mutation is unchanged. The walker change is a
behavioral fix to a query method, not a state mutation.

### Audit 2 dead-code finding (`_method_returns` registry)

Unrelated.

## Notes for the implementer

1. **Run the probes BEFORE the fix** to confirm the baseline matches
   this plan's verification table. If something has shifted (e.g.,
   another fix landed in parallel), update the plan.

2. **Run the probes AFTER the fix** to confirm acceptance. Both probes
   are saved in `/tmp/`.

3. **Audit ParenExpr/Block boundary tests carefully.** The
   `_is_completed_sub_expr` predicate fires for any node with `valid
   && !item_types`. This includes ParenExpr and Block wrappers. Some
   walker calls (e.g., `_get_rightmost_type` from outer Atom looking
   for the type of `($x + 1)`) may expect to find the ParenExpr's
   `type` slot at the wrapper itself (which works, since the wrapper
   has type). But cases where the wrapper has only `valid` and the
   walker expects to descend may break. Probe with `my $r = (defined
   $x);` — outer Expression's Atom walks ParenExpr's value tree. The
   ParenExpr action returns `{ valid, type => Bool }` (has type).
   Walker finds Bool at the wrapper itself — no descent needed. Should
   be fine. But verify.

4. **The walker has been touched THREE times now (Bug 4, Bug 5, and
   this fix).** Any further refinement risks interaction. Document the
   final shape clearly in the prune predicate's comment block.

5. **Consider whether the prune predicate needs to be MORE
   discriminating, not less.** The Bug 1+5 RCA's Option 2 (alternative
   to depth-tracking) suggested a more discriminating predicate that
   only fires when `type` or `call_symbol` etc. are present, not just
   `valid`. With the unified fix expanding the prune's coverage, a
   more discriminating predicate may be safer. Audit during
   implementation: does the predicate need to fire on ParenExpr/Block
   wrappers (which return `{valid, type?}`) or only on
   CallExpression/AnonymousSub completions? The Bug 4 fix's behavior
   was tied to "completed sub-expression with valid+!item_types"; if
   ParenExpr/Block's own action methods always produce `type`, the
   wrappers don't trip the predicate; only "valid-only" results
   (Block with empty body, ParenExpr around `()`) would. Verify.

6. **Ternary mention in the brief was incidental.** Don't feel
   obligated to test ternary specifically. The trigger is "anonsub
   body contains a known-builtin CallExpression", regardless of
   whether the body wraps it in a ternary, an if-block, or just a
   bare statement.

7. **Site count realism.** The brief framed Finding 7 as
   `Actions.pm:75`'s `return defined _find_op_in_trees($name, @trees);`.
   That site triggers the bug because `@trees` is an array variable in
   the inner call's args. Sites with this exact shape are rare in
   `lib/`. The site count for Finding 7 is small. Finding 8's site
   count is potentially larger but bounded by "anonsub-as-non-first-
   arg-to-non-builtin-call" frequency in the production code.

End of plan.
