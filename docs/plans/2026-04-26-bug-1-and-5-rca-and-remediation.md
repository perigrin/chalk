# Bug 1 and Bug 5 RCA and Remediation Plan

**Date:** 2026-04-26
**Bugs:** Bug 1 (literal list as LIST arg to block-form builtin), Bug 5
(call-form binding for specific builtins)
**Audit references:**
- Bug 1: `docs/plans/2026-04-25-audit-2-semirings-findings.md` "Bug 1"
- Bug 5: probe `bm0p3ww3d` (this conversation; not in any prior audit)
- Predecessor RCA: `docs/plans/2026-04-25-bug-4-rca-and-remediation.md`
- Audit 5 findings: `docs/plans/2026-04-25-audit-5-semiring-contract-reality-findings.md`
- Synthesis (Decisions 4, 5, 6): `docs/plans/2026-04-25-phase-a2-synthesis.md`
**Status:** RCA complete. Remediation proposed. Not implemented.

## Verification of probe findings under current state

Reproduction probes ran against current `worktree-pu` HEAD
(post-Bug-4-walker-fix commit `1ec8cae1` and post-Phase-3a-infra commit
`885beb87`).

### Bug 1 — confirmed: still fails

| Case | Verdict |
|---|---|
| `my @x = map { $_ + 1 } (1, 2, 3);` | **FAIL** |
| `my @x = map { $_ } (1, 2, 3);` | **FAIL** |
| `my @x = map { $_ } 1, 2, 3;` | **FAIL** |
| `my @y = grep { $_ > 0 } (1, -1, 2);` | **FAIL** |
| `my @arr; my @x = map { $_ } @arr;` | PASS |
| `my $r; my @x = map { $_ } $r->@*;` | PASS |

The prompt's framing — "literal list rejects regardless of parens" — is
correct: parenthesization is not the trigger. Both bare and
parenthesized literal lists fail.

### Bug 5 — confirmed parens-rejecting set; bare-rejecting framing falsified

Sweep of 27 builtins in both call forms (`/tmp/bug5-enum-fresh.pl`):

**Parens-rejecting (4 confirmed FAIL parens, PASS bare):**
- `push`, `unshift`, `join`, `substr`

**Bare-rejecting (0 confirmed; empty under current state):**
- The prompt's framing claimed `keys`, `values`, `each`, `split` reject
  in bare form. **Under current HEAD, all four PASS in both forms.**

The prompt's `bm0p3ww3d` probe was likely run before commit `1ec8cae1`
landed the Bug 4 walker fix (or used an inappropriate argument type
such as `keys $x` with `$x` a scalar variable instead of a hash). The
walker fix changes which builtins fail; the bare-rejecting set has been
retired by it.

Net Bug 5 site count under current state: **4 builtins**, all with
`min_arity >= 2` in `Chalk::Grammar::Perl::TypeLibrary`'s signatures.

## Bug 1 root cause

**Mechanism:** `Chalk::Grammar::Perl::TypeLibrary::type_satisfies` does
not model Perl's list-flattening semantics for the `List` type. When a
CallExpression's per-position check finds a scalar type (`Int`,
`Scalar`) at a position whose signature expects `List`,
`type_satisfies('Int', 'List')` returns false and the parse is
rejected. Per Perl semantics, scalars satisfy a `List` signature
position because they flatten into the list at runtime.

**Code path of rejection:**

`lib/Chalk/Bootstrap/Semiring/TypeInference.pm:360-378` (CallExpression
branch of `_complete_type`):

```perl
my $sig_offset = ($alt_idx == 2 || $alt_idx == 3) ? 1 : 0;
for my $i (0 .. $#$item_types) {
    my $actual = $item_types->[$i];
    my $sig_idx = $i + $sig_offset;
    my $expected = $arg_types->[$sig_idx];
    $expected = $arg_types->[-1] if !defined $expected;
    if (!Chalk::Grammar::Perl::TypeLibrary::type_satisfies($actual, $expected)) {
        return undef;
    }
}
```

`type_satisfies` is in `lib/Chalk/Grammar/Perl/TypeLibrary.pm:167-178`:

```perl
sub type_satisfies($actual_type, $required_type) {
    return true if $required_type eq 'Any';
    return true if !defined $actual_type;
    return true if is_subtype($actual_type, $required_type);
    if ($POLYMORPHIC_TYPES{$actual_type}) {
        return true if is_subtype($required_type, $actual_type);
    }
    return false;
}
```

For `map { $_ } (1, 2, 3)`:
- `(1, 2, 3)` is parsed as `ParenExpr` containing one inner Expression.
- `ParenExpr` Action method (`TypeInferenceActions.pm:202-208`) returns
  `{type => $child_type}` from `_get_rightmost_type`. The rightmost
  child is the literal `3`, so the ParenExpr's type is `Int`.
- The outer ExpressionList for the LIST argument sees a single element
  (the ParenExpr) with type `Int`. `item_types = [Int]`, `list_arity = 1`.
- alt=2 sig_offset=1, so position 0 of item_types is checked against
  `arg_types[0+1] = 'List'`.
- `type_satisfies('Int', 'List')`:
  - `is_subtype('Int', 'List')` → false (Int is under Scalar/Num, not List).
  - `Int` is not in `%POLYMORPHIC_TYPES = qw(Scalar Any List)` → polymorphic
    branch skipped.
  - Returns false.
- Reject.

For `map { $_ } 1, 2, 3` (bare):
- ExpressionList accumulates `[Int, Int, Int]` per-position.
- Same per-position loop runs three times; each `type_satisfies('Int',
  'List')` returns false. Reject.

**Why `map { $_ } @arr` works:** `@arr` is `ArrayVariable`, scan-tagged
with `type = 'Array'`. `Array` is_subtype `List` (per the type
hierarchy: `Array => 'List'`). `type_satisfies('Array', 'List')` returns
true via the `is_subtype` branch.

**Confirmed by instrumentation** (`/tmp/bug1-localize.pl`):
```
[CallExpr alt=2] call_sym=map  item_types=[Int]   list_arity=1 -> ZERO  (parens fail)
[CallExpr alt=2] call_sym=map  item_types=[Array] list_arity=1 -> KEEP  (@arr passes)
```

The walker is finding the correct item_types (Bug 4's walker fix is
working). The rejection is in the type-satisfies check, not in the walker.

**Single-sentence root cause:** `type_satisfies` rejects scalar types
against the `List` requirement, but Perl's list-flattening semantics
mean any scalar flattens into a list at runtime, so individual scalars
should satisfy `List` positions.

## Bug 5 root cause

**Mechanism:** TypeInference's `_walk_annotations` prune callback
`_is_completed_sub_expr` (introduced in Bug 4 walker fix, commit
`1ec8cae1`) over-prunes the **root** of the value being walked when the
value's `annotations->{type}` is a HASH containing `valid` but not
`item_types`. This happens specifically for **CallExpression alt=0
(parens form)** where the value's root has been wrapped with
`{valid=1}` from upstream multiplies. The walker stops at the root,
returns undef, and `_get_item_types` / `_get_list_arity` both return
undef. Arity defaults to 1, and the `arity < $sig->{min_arity}` check
rejects builtins whose `min_arity >= 2`.

**Code path of rejection:**

`lib/Chalk/Bootstrap/Semiring/TypeInference.pm:121-125` (the prune
callback):

```perl
my $is_completed_sub_expr = sub ($n) {
    my $type = $n->annotations()->{type};
    return false unless defined $type && ref($type) eq 'HASH';
    return exists $type->{valid} && !exists $type->{item_types};
};
```

This callback is passed to `_walk_annotations` (line 79) by
`_get_item_types` (line 130) and `_get_list_arity` (line 142). The
walker calls `next if defined $prune && $prune->($node);` (line 85)
**before** examining the node — so a pruned root means the walker
returns undef immediately without exploring children.

In `_complete_type`'s CallExpression branch (lines 360-388):
```perl
my $arity = $self->_get_list_arity($value) // 1;
$arity += 1 if ($alt_idx == 2 || $alt_idx == 3);
if ($arity < $sig->{min_arity}) {
    return undef;
}
```

For alt=0 (parens), `_get_list_arity` returns undef, arity defaults to 1,
not incremented (alt=0 not 2 or 3). `min_arity` for `push`/`unshift`/`join`/
`substr` is 2. `1 < 2` → reject.

**Confirmed by instrumentation** (`/tmp/bug5-alt1-vs-alt0.pl`):
```
alt=0  root_type={valid=1}                         items_at_d1=<not at d1>      -> ZERO  (substr parens)
alt=1  root_type=<Context Chalk::Bootstrap::Context> items_at_d1=[Scalar,Int,Int] -> KEEP  (substr bare)
```

For alt=0 parens form, `annotations->{type}` of the root is the HASH
`{valid=>1}`, which the prune callback treats as a "completed sub-expr"
and skips. For alt=1 bare form, `annotations->{type}` of the root is a
Context object (not a HASH), so the prune callback's `ref($type) eq
'HASH'` check returns false, the prune is bypassed, and the walker
descends to find the deeper item_types.

**Why parens-form root has `{valid=1}` HASH while bare-form has Context:**
The CallExpression alt=0 grammar is `Identifier _ ( _ ExpressionList _ )`.
The leading `_` (whitespace) and `(` are scan events that go through TI
multiply with the catch-all path returning `{ valid => true }`. As these
results merge upward via `multiply` (which builds a child-bearing tree
when neither side has `complete` annotation), the merged Context
inherits an outer `{valid=>1}` HASH at the topmost level. For alt=1
bare, the structure is different (`Identifier WS ExpressionList`), and
the merged Context's annotation ends up as a Context object instead of a
HASH at the relevant scope. The exact path of "why HASH vs Context at
the root" is FilterComposite plumbing internal — the relevant fact is
that the prune callback's `ref($type) eq 'HASH'` test creates a
scope-dependent behavior that it didn't intend.

**Why `pop`, `shift`, `splice`, `delete`, `exists`, `length`, `chomp`,
`chop`, `chr`, `ord`, `defined`, `ref`, `scalar`, `bless`, `print`,
`say`, `warn`, `die`, `sprintf`, `split` all PASS in parens form:** all
have `min_arity` of 0 or 1 in `TypeLibrary`. With arity defaulting to 1,
the `arity < min_arity` check passes (1 >= 1). Per-position type
checking is skipped (item_types undef). They pass coincidentally — not
because the walker found the right values, but because there are no
values to find that would have caused a rejection.

**Single-sentence root cause:** The Bug 4 walker fix's prune callback
applies to the root node of `$value` itself, not just to inner
sub-expression boundaries; when the root has the catch-all `{valid=>1}`
HASH annotation (alt=0 paren form), the walker prunes itself at depth
0 and returns undef.

## Categorization per bug

### Bug 1 — Category B with overlap to A

The signature for `map` (`arg_types => ['Code', 'List']`) is correct —
map takes a code block and a list. The defect is in the shared utility
`type_satisfies`: it doesn't model Perl's list-flattening semantics for
the `List` requirement.

This is **Category B (TypeLibrary signature gap)** at `type_satisfies`,
not at the per-builtin signature entries. With overlap to **Category A
(TI logic)** because the alternative shape is to special-case variadic
LIST positions in `_complete_type` rather than fixing the shared
helper. Fixing `type_satisfies` retires more cases at once; fixing
`_complete_type` is more localized but leaves the helper in a
less-correct state.

The overlap with Decision 5 (flow-typing completion): **dissolves under
flow-typing**. When the signature check becomes flow-typed, `(1, 2, 3)`
in a LIST position has its values flowed in; the question becomes "do
these scalar values satisfy a list context?" which is yes by Perl
semantics. But the dissolution is post-Phase 3c at minimum; Bug 1 needs
a Tier 1 patch today.

### Bug 5 — Category A

The defect is entirely within TypeInference's tree-walker logic. The
`_is_completed_sub_expr` prune callback is a Bug 4 walker fix that's
overshooting: it correctly prunes inner CallExpression results, but
incorrectly prunes the walker's own root when that root happens to
carry the catch-all `{valid=>1}` annotation.

This is **Category A (TI logic bug)**. TypeLibrary's signatures are
correct (the parens form *should* succeed because list_arity should
satisfy min_arity).

No Decision 5 dissolution path: Bug 5 is unrelated to flow-typing — the
walker mechanism itself is the defect.

## Coupling analysis

**Bug 1 and Bug 5 are independent bugs.** Different root causes,
different fix sites:

- **Bug 1**: `type_satisfies('Int', 'List')` in `TypeLibrary.pm:167-178`
  returns false; should return true under list-flattening semantics.
- **Bug 5**: `_is_completed_sub_expr` prune callback in
  `TypeInference.pm:121-125` over-prunes the walker's root.

**Cross-effect tests:**

1. *Would fixing Bug 1 retire any Bug 5 site?* No. Bug 5's parens-form
   rejection happens at the `arity < min_arity` check, which fires
   *before* any per-position `type_satisfies` call. Even with permissive
   `type_satisfies`, Bug 5's site set (`push`, `unshift`, `join`,
   `substr` in parens form) would still fail the arity check.

2. *Would fixing Bug 5 retire Bug 1?* No. Bug 1 fails on bare and
   parens forms alike — the trigger is the literal-list semantics on
   the LIST argument, not the call-form. The walker is finding the
   correct item_types in both cases (instrumented: alt=2 parens has
   `item_types=[Int]`, alt=2 bare has `item_types=[Int,Int,Int]`); the
   `type_satisfies` check rejects each.

3. *Common fix site overlap?* Both bugs surface through
   `_complete_type` in `TypeInference.pm`, but the actual defect lines
   are 100+ lines apart and distinct. Same file, same method, same
   region; different mechanisms.

The bugs share a "neighborhood" in the code (CallExpression signature
validation in TypeInference) but are not the same root cause. Treating
them as one fix would mean either:
(a) a single PR touching both lines (defensible if landed together as a
   pair, but not technically a "single" fix);
(b) confusing the reviewers about what mechanism each fix addresses.

**Recommendation: handle as two distinct fixes that may be sequenced
together.**

## Proposed remediation

### Bug 1 — patch `type_satisfies` for List flattening

**File:** `lib/Chalk/Grammar/Perl/TypeLibrary.pm`, `type_satisfies` at
lines 167-178.

**Change:** Add a clause that recognizes Perl's list-flattening
semantics — `List` is satisfied by any concrete type because of
flattening at runtime.

Two implementation options:

**Option 1 (preferred): treat `List` as a permissive supertype.**

```perl
sub type_satisfies($actual_type, $required_type) {
    return true if $required_type eq 'Any';
    return true if !defined $actual_type;
    return true if is_subtype($actual_type, $required_type);
    if ($POLYMORPHIC_TYPES{$actual_type}) {
        return true if is_subtype($required_type, $actual_type);
    }
    # Perl flattens any scalar/array/hash into list context.
    # Any concrete type satisfies a `List` position.
    return true if $required_type eq 'List';
    return false;
}
```

This is the smallest semantic change. It says: "if a signature requires
`List`, accept any actual type." This matches Perl's runtime: scalars
and aggregates both flatten to list elements at the call boundary.

**Option 2: special-case variadic LIST in `_complete_type`.**

In `TypeInference.pm:370-378`, detect when the expected position is
`List` and skip the per-position type check (because flattening makes
the check inappropriate for that slot).

```perl
my $expected = $arg_types->[$sig_idx];
$expected = $arg_types->[-1] if !defined $expected;
next if $expected eq 'List';  # <-- new line: skip per-position check
                              # for variadic LIST positions
if (!Chalk::Grammar::Perl::TypeLibrary::type_satisfies($actual, $expected)) {
    return undef;
}
```

This is more targeted but disables type checking entirely for List
positions, which loses some signal (e.g., `map BLOCK ScalarRef` where
ScalarRef can't actually flatten).

**Choose Option 1.** It models the language correctly and retires the
defect cleanly.

**Caveat:** Option 1 makes `type_satisfies(X, 'List')` always true.
This is correct — Perl's semantics are exactly "any scalar/array/hash
flattens into list context." But it means the `List` slot in a builtin
signature stops being a useful constraint. That's accurate to the
runtime; the type system shouldn't pretend otherwise.

### Bug 5 — restrict the prune callback to non-root nodes

**File:** `lib/Chalk/Bootstrap/Semiring/TypeInference.pm`, prune
callback at lines 121-125 and walker at lines 79-95.

**Change:** Make the prune callback skip the **root** of the walk —
prune only inner descendants. Two implementation options:

**Option 1 (preferred): track depth in the walker, never prune at
depth 0.**

Modify `_walk_annotations` (lines 79-95) to track a depth counter and
only consult the prune callback at depth > 0:

```perl
my sub _walk_annotations($ctx, $callback, $reverse = false, $prune = undef) {
    return undef unless defined $ctx;
    # Stack entries are [node, depth] pairs.
    my @stack = ([$ctx, 0]);
    while (@stack) {
        my ($node, $depth) = pop(@stack)->@*;
        # Prune only inner nodes, never the root (depth 0).
        next if $depth > 0 && defined $prune && $prune->($node);
        my $result = $callback->($node);
        return $result if defined $result;
        my @kids = $node->children()->@*;
        @kids = reverse @kids unless $reverse;
        push @stack, map { [$_, $depth + 1] } @kids;
    }
    return undef;
}
```

This keeps the prune semantic intact for inner CallExpressions (the
Bug 4 fix) while protecting the walker from self-pruning at the root.

**Option 2: refine `_is_completed_sub_expr` to require additional
markers of "completed sub-expression" beyond `valid && !item_types`.**

The defect is that the catch-all `{valid=>1}` (with no other content) is
indistinguishable from a "completed sub-expression result" by the
current predicate. A more discriminating predicate could check for
type specificity (e.g., `exists $type->{type}` or `exists
$type->{call_symbol}`) so that the catch-all `{valid=>1}` doesn't match.

```perl
my $is_completed_sub_expr = sub ($n) {
    my $type = $n->annotations()->{type};
    return false unless defined $type && ref($type) eq 'HASH';
    return false unless exists $type->{valid};
    return false if exists $type->{item_types};
    # Only treat as a completed sub-expr if there's specific content
    # signaling completion, not the bare catch-all.
    return exists $type->{type}
        || exists $type->{call_symbol}
        || exists $type->{op_text}
        || exists $type->{eval_context}
        || exists $type->{method_name};
};
```

This is more discriminating but introduces a list of "complete-content"
slots that needs maintenance as new TI Action methods are added.

**Choose Option 1.** Depth-based root protection is the smallest change
and doesn't introduce a slot enumeration that drifts.

### Combined fix shape

The minimal patch is two changes in two files:

1. `TypeLibrary.pm` line 178 area: add `return true if $required_type
   eq 'List';` before the final `return false;`.
2. `TypeInference.pm` lines 79-95: thread depth through the walker;
   never prune at depth 0.

Both changes are well-bounded (single function each). Both are
testable via the probes already created (`/tmp/bug1-bug5-verify.pl`,
`/tmp/bug5-enum-fresh.pl`).

## Side effects

### Cross-effects with Bug 4 walker fix (commit `1ec8cae1`)

Bug 5's fix preserves Bug 4's walker semantics for inner sub-expressions.
The prune callback still fires for descendants of the walker root —
just not for the root itself. This means:

- Bug 4's "stop at completed sub-expression boundaries" intent is
  preserved.
- Bug 5's failure mode (root-self-pruning) is eliminated.

The walker fix landed without considering the case where the root
itself carries `{valid=>1}`. Adding root protection is consistent with
the original intent.

**Bug 4's acceptance criteria continue to hold:** `map { defined $_ }
@arr` and friends still pass. Verified mentally by tracing: the alt=2
walker root is a Context (not HASH) for those cases, so the depth-0
prune is irrelevant; descendant pruning still skips inner
ExpressionLists from completed sub-calls.

### Cross-effects with Phase 3a-infra (commit `885beb87`)

Phase 3a-infra promotes `$graph` and `$scope` to Context fields. This
does not touch TypeInference or TypeLibrary. No interaction.

### Cross-effects with Decision 4 (semiring contract migration)

TypeInference's contract migration (mixed return types → uniform
Context) is a separate work stream. Per Audit 5 Finding 3 and the
synthesis, the contract migration for TI is "cosmetic with respect to
the external consumer" — wrapping `_complete_type`'s return values in
Contexts doesn't change Bug 1 or Bug 5 mechanisms.

**Sequencing recommendation: Bug 1 + Bug 5 fix BEFORE TI contract
migration.** Same reason as Bug 4 — contract migration on top of buggy
behavior migrates the wrong behavior.

### Cross-effects with Decision 5 (flow-typing completion)

Bug 1 dissolves under flow-typing (the question becomes "do these
scalars flow into list context?" — answered by per-edge type
narrowing). Bug 5's walker mechanism does not exist in the flow-typing
target architecture (flow-typing replaces tree-walking with typed
SSA-like nodes). Both are stopgaps until Decision 5 lands.

Phase 3c is the earliest plausible flow-typing land; Bug 1 + Bug 5 fix
unblocks 4+ files now without delaying flow-typing work.

### Cross-effects with Audit 5 Finding 1 (TI position-dependence)

Audit 5 Finding 1 documents that TI's behavior depends on whether it
is `_sa()` or in `_annotation_semirings()`. Bug 1 and Bug 5 both
manifest only when TI is in `_annotation_semirings()` (i.e.,
`[B,P,T,S,A]` or any stack with TI before SA), because that's the only
configuration where TI's tree-walks find populated annotation slots.
The fixes do not address the position-dependence — they fix what TI
does *when its walker runs.* Position-dependence remains as architectural
documentation drift.

### Cross-effects with Audit 5 Finding 5 (side effects)

Side-effect inventory is unchanged. The fixes do not introduce or remove
side effects in TI's operations.

### Cross-effects with grammar-conformance.t

After the fixes, `t/grammar-conformance.t` should show additional files
passing — those that use `(literal,list)` as block-form-builtin LIST
arguments (Bug 1) or use parens-form `push`/`unshift`/`join`/`substr`
calls (Bug 5). Site count estimate: small (~3-6 files), since most
production code uses bare form for `push`/`unshift` and array/hash
arguments for `map`/`grep`. The audit's observation that
`map { … } $ref->@*` is the dominant pattern in `lib/` (not
`map { … } (1, 2, 3)`) means Bug 1's site count is genuinely small.

## Acceptance criteria

### Bug 1 — minimum acceptance

1. **Minimal failing cases pass:**
   - `my @x = map { $_ } (1, 2, 3);` — full stack `[B,P,T,S,A]`.
   - `my @x = map { $_ + 1 } (1, 2, 3);`
   - `my @x = map { $_ } 1, 2, 3;`
   - `my @y = grep { $_ > 0 } (1, -1, 2);`

2. **Working cases continue to pass:**
   - `my @arr; my @x = map { $_ } @arr;`
   - `my $r; my @x = map { $_ } $r->@*;`
   - `my @x = map { $_ + 1 } @arr;`

3. **No regression in TypeInference unit tests.**

### Bug 5 — minimum acceptance

1. **Minimal failing cases pass (parens form):**
   - `my @a; push(@a, 1);`
   - `my @a; unshift(@a, 1);`
   - `my @a; my $s = join(",", @a);`
   - `my $s; my $t = substr($s, 0, 3);`

2. **Bare form continues to pass:**
   - `my @a; push @a, 1;`
   - `my @a; my $s = join ",", @a;`
   - etc.

3. **Other parens-form builtins continue to pass:**
   - `pop()`, `shift()`, `splice()`, `delete()`, `exists()`, `length()`,
     `chomp()`, `chop()`, `chr()`, `ord()`, `defined()`, `ref()`,
     `scalar()`, `bless()`, `print()`, `say()`, `warn()`, `die()`,
     `sprintf()`, `split()`.

4. **Bug 4's trigger set continues to pass:**
   - `map { defined $_ } @arr;`, `grep { ref $_ } @arr;`, etc.

5. **No regression in `t/grammar-conformance.t`** PASS count.

### Combined acceptance

1. **`t/grammar-conformance.t` PASS count strictly increases** by at
   least the number of files newly enabled by Bug 1 or Bug 5 fixes.
2. **No regression in `t/bootstrap/*.t`** unit tests, especially
   TypeInference unit tests and grammar-ambiguity-fixes.t.
3. **Probe scripts retire:** `/tmp/bug1-bug5-verify.pl`,
   `/tmp/bug5-enum-fresh.pl`, `/tmp/bug1-localize.pl` deleted at end
   of session.

## Sequencing recommendation

**Bug 1 fix and Bug 5 fix should land together as one PR.**

Reasoning:
- Both touch the same conceptual layer (TypeInference's CallExpression
  signature validation).
- Both are Tier 1 in the synthesis taxonomy.
- Combined site count is small (<10 files) — bundling them keeps the
  conformance signal contiguous.
- They are independent enough that landing as separate commits within
  one PR makes review tractable.
- Bug 5 is the more straightforward fix (single-method walker change);
  Bug 1 requires understanding Perl flattening semantics. Reviewer can
  walk through them in either order.

**Sequencing relative to other Tier 1 work:**

- **AFTER Bug 4 fix (commit `1ec8cae1`): already landed.** ✓
- **AFTER Phase 3a-infra (commit `885beb87`): already landed.** ✓
- **BEFORE Phase 3a-migration:** Phase 3a-migration touches Actions.pm
  and SemanticAction; no TypeInference dependency. Independent. Can be
  parallel.
- **BEFORE TypeInference contract migration (Decision 4):** the
  contract migration touches `_complete_type`'s return values. Doing
  Bug 1 + Bug 5 fix first means contract migration starts from correct
  behavior.
- **BEFORE flow-typing completion (Decision 5):** flow-typing replaces
  the rejection mechanism for both bugs. Patching now is a stopgap;
  patching now also unblocks 4+ conformance files in the meantime.

**Final ordering:**

1. **Now**: Bug 1 + Bug 5 fix (this plan, ~2-4 hours total)
2. **Now or parallel**: Phase 3a-migration (different files entirely)
3. **Subsequent**: TypeInference contract migration (Decision 4)
4. **Eventual**: Flow-typing completion (Decision 5) — Bug 1 and Bug 5
   patches can be removed during this work

## Connection to Audit 5 findings

The two bugs interact with Audit 5's findings as follows:

### Audit 5 Finding 1 (TI position-dependence)

Both bugs are gated by Finding 1's mechanism: TI's walker only fires
its signature validation when TI is in `_annotation_semirings()` (not
when TI is `_sa()`). The bugs are invisible in `[B,T]` configurations
because TI's annotations are not stored on shared Context nodes there;
they manifest only in `[B,P,T,S,A]` and similar.

The fixes do not address position-dependence directly — they fix what
TI does *when its walker fires*. Audit 5's documentation update for
the `_sa()` vs `_annotation_semirings()` semantics is independent and
remains valid after these fixes.

### Audit 5 Finding 5 (side effects)

The fixes are pure — no side effects added or removed. TypeInference's
mutation of `%_method_returns` and FilterComposite's compensation
behavior are unchanged.

### Audit 5 additional finding A (SA's class-level state)

Unrelated to these fixes.

### Audit 2 dead-code finding (`_method_returns` registry)

Decision 5 reframes this as forward-looking infrastructure for
flow-typing. These fixes do not interact with the registry.

## Notes for the implementer

1. **Run the probes before the fix** to confirm the baseline matches
   this plan's verification table. If it doesn't, the bug landscape
   has shifted and this plan needs an update.

2. **Run the probes after the fix** to confirm the acceptance criteria
   matrix. Both probes are saved in `/tmp/`; recreate them from this
   plan if they've been deleted.

3. **Watch for `t/grammar-conformance.t` net delta.** Expected:
   strictly positive, on the order of 3-6 files. If the delta is
   larger, investigate — the fix may have retired more cases than
   expected, which is good news but worth understanding.

4. **Flow-typing reference (Decision 5):** when the time comes to
   complete TypeInference, the algorithmic reference is `~/dev/pvm`
   (Go implementation). Bug 1's mechanism (List flattening) and Bug
   5's mechanism (root-prune protection) both go away in that target
   architecture.

5. **Test the combined fix together,** not just individually. Bugs 1
   and 5 don't share a fix site, but they share a code path
   (`_complete_type`'s CallExpression branch). A regression in either
   could mask the other.

End of plan.
