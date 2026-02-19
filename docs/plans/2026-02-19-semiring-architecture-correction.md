# Semiring Architecture Correction (Revised)

**Supersedes**: The original version of this document and
`2026-02-19-composite-filter-pipeline.md` (which proposed die-at-add-time;
replaced by the survivor-list design below).

## Problem

The Bootstrap semiring implementation has diverged from `chalk-parse-perl-plan.md`
in four ways:

1. **`selects_alternative` exists but the plan never specified it.** It introduces
   an implicit priority ordering among semirings, violating the plan's stated
   contract that semirings are order-agnostic.

2. **Rejection logic lives in `add()` instead of `multiply()`/`on_complete()`.**
   Structural and TypeInference disambiguate in `add()`/`selects_alternative()`
   where they should filter invalid derivations during construction.

3. **`add()` creates merged values.** Structural's `add()` synthesizes new hash
   values by ORing tags from both sides, instead of preserving the original
   alternatives.

4. **Structural encodes incorrect heuristics as absolute preferences.**
   Preferences like `is_block > is_hash` are context-dependent (block in statement
   context, hash in expression context) but implemented as unconditional rules.
   Many preferences compensate for gaps in other semirings or the grammar rather
   than performing genuine structural disambiguation.

## Core Architecture

### Semiring Operations

Each operation has a distinct role:

- **`multiply`/`on_complete`**: Build a derivation. Rejection is multiplication
  by zero — the semiring annihilator. If an intermediate step or completed rule
  is invalid, return zero. The parser skips propagation of zero-valued
  completions.

- **`on_complete`**: The final multiply step with whole-rule context. Some
  semirings (TypeInference) need all children before deciding validity.
  Precedence can validate incrementally in `multiply` because precedence
  violations are detectable as soon as the operator arrives.

- **`add`**: Combine alternative derivations. Receives a survivor list and a new
  value. Returns an updated survivor list. Zeros are handled upstream and must
  never reach `add()`.

### The Annihilator Property

Rejection is not a separate mechanism — it is multiplication by zero. The
semiring annihilator property guarantees `multiply(anything, zero) = zero`.
An invalid derivation step returns zero, killing the entire path. The parser
already checks for this:

```perl
# Earley.pm line 121
next if $semiring->is_zero($completed_value);
```

The parser filters zeros at multiply/on_complete/on_scan boundaries. The
current ambiguity guard lives in `SemanticAction.add()`, which dies when it
receives two IR trees it cannot distinguish. In the new design, SemanticAction
stops dying — it returns `[$left, $right]` like any other semiring. The
end-of-parse assertion (see below) takes over as the ambiguity guard.

### FilterComposite Value Representation

The composite semiring is renamed from `Composite` to `FilterComposite` to
reflect its disambiguation semantics. FilterComposite assumes all component
semirings use **filter semantics** in `add()`: each per-semiring `add()` returns
original objects (`[$left]`, `[$right]`, or `[$left, $right]`), never
synthesized/merged values. This is a design choice for our parser's
disambiguation use case, not a universal semiring law. An accumulating composite
(e.g., for probability semirings) would need a different implementation.

**Note on algebraic properties**: FilterComposite with Pareto-optimal `add()` is
not a distributive semiring in the strict algebraic sense.
`multiply(A, add(B, C))` may differ from `add(multiply(A, B), multiply(A, C))`
because Pareto filtering in `add()` can eliminate alternatives before `multiply`
sees them. This does not affect parsing correctness: the Boolean component
guarantees correct recognition, and the remaining semirings provide a
disambiguation overlay. FilterComposite is a semiring-like structure optimized
for filtering, not a classical semiring optimized for accumulation.

The parser (Earley.pm) treats semiring values as opaque. It calls `multiply`,
`add`, `on_complete`, `on_scan`, and `is_zero` without inspecting value
contents. All internal structure is FilterComposite's concern.

A FilterComposite value is a **list of survivor tuples**. Each tuple contains
one component per semiring. FilterComposite broadcasts every operation across
survivors:

- **`zero()`**: Returns an empty list `[]`.
- **`one()`**: Returns a list containing one tuple of per-semiring ones:
  `[[$bool_one, $prec_one, $type_one, $struct_one, $sem_one]]`.
- **`is_zero($value)`**: True if the survivor list is empty.
- **`multiply($list_a, $list_b)`**: Cartesian product — for each tuple in
  `$list_a` and each tuple in `$list_b`, call per-semiring multiply. Drop any
  result tuple where a component is zero. Return the surviving list.
- **`on_complete($list)`**: Map over each survivor tuple, call per-semiring
  on_complete. Drop any tuple where a component returns zero.
- **`on_scan($list)`**: Same broadcast pattern as on_complete.
- **`add($list_a, $list_b)`**: Insert each tuple from `$list_b` into `$list_a`
  one at a time using `_add_single`, which computes the Pareto-optimal survivor
  set (see below).

The cartesian product in multiply is M×N per-semiring calls where M and N are
the survivor counts. In practice both are small (usually 1, occasionally 2-3).
A configurable survivor cap (e.g., 32) with a diagnostic die guards against
runaway ambiguity from insufficient disambiguation. Future Aycock optimizations
will reduce redundant table states, further bounding survivor counts.

**Earley.pm changes are minimal:**

1. Generalize the try/catch around `add()` (line 280-290) from "Ambiguity in
   rule" to "Error in rule" — the parser provides location context without
   interpreting the exception.
2. Add an end-of-parse survivor-count assertion in `_run_parse` (see below).
3. All three `add()` call sites (lines 224, 281, 341) must be verified to work
   with FilterComposite values.

### Hash-Consing

Each semiring hash-conses its values during `multiply` and `on_complete`. Two
derivation paths that produce the same context yield the same object (same
`refaddr`). This provides four properties:

1. **Deduplication in `add()`**: Identity check (`refaddr($left) == refaddr($right)`)
   collapses equivalent alternatives with zero comparison cost.
2. **No merged values**: `add()` never synthesizes new values. It returns
   `[$left]`, `[$right]`, or `[$left, $right]` — always original objects.
3. **Commutativity**: Identity is symmetric. Numeric/flag comparisons are
   symmetric. No arbitrary tie-breaking needed.
4. **Idempotency**: `add(a, a)` collapses via identity check to `[$a]`. This
   is important for Earley parsing where the same derivation may be added
   multiple times.

**Invariant: all semiring methods that return values must hash-cons them.** The
parser never constructs values directly — it calls `one()`, `on_scan()`,
`multiply()`, and `on_complete()`, all of which are semiring methods. A value
created outside the hash-cons table breaks identity-based deduplication for all
downstream nodes that include it as a child.

#### Per-Semiring Hash-Consing Mechanisms

- **Boolean**: Two values (true/false). Trivially two-valued; no hash-cons
  table needed.
- **Precedence**: Key is `(level, assoc)`. String key `"$level:$assoc"` or
  packed integer into a lookup table. Two values with the same level and
  associativity yield the same object — equal-level comparison never reaches
  the preference logic. The `op` (operator text) and `is_operator` flag are
  excluded from the key: they are consumed during multiply to determine level
  and associativity, and are not needed for identity comparison after
  on_complete.
- **TypeInference**: Key is `(rule, position, children_refaddrs)`. Tree nodes
  hash-consed bottom-up during multiply. Each multiply call produces a node
  keyed by its children's identities. Two derivations with identical children
  at the same rule position get the same Context node.
- **Structural**: Bitfield of boolean tags. 8 tags = 8 bits = 256 possible
  values. Identity is integer `==`. Same tag set = same integer = same object.
- **SemanticAction**: Hash-consed IR nodes keyed by `(operation, input_node_ids)`.
  The Sea of Nodes approach — identical derivations produce the same IR node.

### Transitivity Constraint

**All per-semiring preferences MUST be transitive** (form a strict partial
order: irreflexive, antisymmetric, transitive). Non-transitive preferences
produce order-dependent results regardless of the merge algorithm.

Hash-consing makes irreflexivity trivial — identical values collapse via
identity check before any preference comparison. Antisymmetry follows from
filter semantics: `add(A, B)` returns `[$left]` or `[$right]`, and these are
mutually exclusive outcomes for the same pair.

Current semirings satisfy transitivity:

- **Precedence**: Total order on numbers (with PostfixExpression/Assignment
  special case — see below). Transitive by construction.
- **Structural**: Identity check only — equality is transitive by definition.
- **TypeInference**: Binary flag comparison. Transitive.
- **Boolean**: No preferences.
- **SemanticAction**: No preferences (both always survive).

Any future semiring or change to comparison logic must maintain all three
properties (irreflexivity, antisymmetry, transitivity).

### Single-Preference Invariant

**For any pair of tuples, at most one semiring may express a directional
preference.** If semiring A says left_loses and semiring B says right_loses for
the same pair, the composite `add()` is not associative — the result depends on
evaluation order.

This invariant holds by construction: each semiring evaluates an orthogonal
dimension (operator levels, ambiguous unary flag, structural identity, etc.).
Two semirings expressing contradictory directional preferences means one is
making a judgment outside its domain.

FilterComposite's `_filter_compare` algorithm enforces this at runtime with a
diagnostic die (see below). A violation indicates a semiring bug, not a parser
problem.

**Note on composite transitivity**: Per-semiring transitivity plus the
single-preference invariant do NOT guarantee composite transitivity. Semiring S1
may prefer A over B, while semiring S2 (different semiring) prefers B over C,
and neither has a preference for (A, C). The composite says A beats B, B beats
C, but A and C are incomparable. The survivor-list algorithm handles this
correctly — it computes the Pareto-optimal set, which does not require
transitivity of the composite preference relation.

### Survivor Lists

`add($list_a, $list_b)` inserts each element of `$list_b` into `$list_a` one
at a time:

```perl
method add($list_a, $list_b) {
    my $result = $list_a;
    for my $new ($list_b->@*) {
        $result = $self->_add_single($result, $new);
    }
    return $result;
}
```

Each `_add_single` call computes the Pareto-optimal survivor set. Since
`_add_single` is order-independent (given per-semiring transitivity), iterating
over `$list_b` elements in any order produces the same result.

```perl
method _add_single($survivors, $new) {
    my $new_dominated = false;
    my @dominated_indices;

    for my ($i, $existing) (indexed $survivors->@*) {
        my $cmp = $self->_filter_compare($existing, $new);
        if ($cmp eq 'right_loses') {
            $new_dominated = true;
        } elsif ($cmp eq 'left_loses') {
            push @dominated_indices, $i;
        }
    }

    # If new is dominated, return survivors unchanged.
    # A dominated value MUST NOT filter existing survivors —
    # it may beat survivors that are not dominated by anything
    # in the final set, producing incorrect results.
    if ($new_dominated) {
        return $survivors;
    }

    # New survived — filter out anything it beats.
    if (!@dominated_indices) {
        return [@$survivors, $new];
    }

    my %skip = map { $_ => 1 } @dominated_indices;
    my @kept;
    for my ($i, $existing) (indexed $survivors->@*) {
        push @kept, $existing unless $skip{$i};
    }
    push @kept, $new;
    return \@kept;
}
```

**Key correctness property**: if `$new` is dominated by any existing survivor,
it has no filtering power. This prevents a transient value from incorrectly
eliminating survivors. Without this rule, the algorithm produces
order-dependent results: survivors [A, B] + new C where A beats C and C beats B
would incorrectly drop B (which is not dominated by anything that survives).

**Survivor lists are unordered sets.** The array representation is an
implementation detail — element order carries no semantic meaning. The
end-of-parse assertion checks `@survivors == 1`, at which point ordering is
irrelevant. No code should rely on survivor list ordering.

Individual semirings return the uniform type from their `add()`:

- `[$left]` — right filtered out
- `[$right]` — left filtered out
- `[$left, $right]` — cannot distinguish, both survive

### FilterComposite.\_filter\_compare()

```perl
method _filter_compare($left, $right) {
    my $verdict = 'neither';

    for my ($i, $semiring) (indexed $semirings->@*) {
        my $li = $left->[$i];
        my $ri = $right->[$i];

        die "Zero reached add() at semiring $i"
            if $semiring->is_zero($li) || $semiring->is_zero($ri);

        # Identity guard: if both components are the same hash-consed
        # object, skip comparison. This avoids false directional
        # preferences from hash-consing misses and is a performance win.
        next if refaddr($li) == refaddr($ri);

        my $result = $semiring->add($li, $ri);

        if ($result->@* == 1) {
            my $r = $result->[0];
            if (refaddr($r) == refaddr($ri)) {
                my $this = 'left_loses';
                die "Semiring conflict: $verdict vs $this at semiring $i"
                    if $verdict ne 'neither' && $verdict ne $this;
                $verdict = $this;
            } elsif (refaddr($r) == refaddr($li)) {
                my $this = 'right_loses';
                die "Semiring conflict: $verdict vs $this at semiring $i"
                    if $verdict ne 'neither' && $verdict ne $this;
                $verdict = $this;
            } else {
                die "Semiring $i add() returned novel object — "
                    . "filter semantics required by FilterComposite";
            }
        }
    }

    return $verdict;
}
```

The algorithm checks all semirings — no early return. The identity guard
(`refaddr($li) == refaddr($ri)`) skips comparison when both components are the
same hash-consed object, preventing false directional preferences from
hash-consing misses. Three diagnostic dies enforce the FilterComposite contract
as **correctness prerequisites**, not just diagnostics — without them,
`_add_single` would produce incoherent results:

1. **Zero in add()**: A zero value reached add() — the parser should have
   filtered it upstream.
2. **Semiring conflict**: Two semirings disagree on direction — one is making
   a judgment outside its domain. Fix the overreaching semiring. The
   `_add_single` algorithm requires `_filter_compare` to never return
   contradictory signals for the same pair.
3. **Novel object**: A per-semiring add() returned a synthesized value instead
   of an original — that semiring doesn't fit FilterComposite's filter model.

Early return can be added as a performance optimization once the invariants
are empirically validated across the full test suite.

**When a conflict diagnostic fires**: examine the pair of tuples to understand
why each semiring expressed a preference. Determine which preference is
legitimate and which is overreach. Fix the overreaching semiring — either remove
the preference or tighten its on_complete to reject the path earlier so the
pair never reaches add().

### End-of-Parse Assertion

```perl
my $final = $item->{value};
# FilterComposite extracts the survivor list
my @survivors = $composite->survivors($final);
if (@survivors != 1) {
    die "Ambiguous parse: " . scalar(@survivors)
        . " alternatives survived all semirings";
}
```

This is an **invariant check**, not a disambiguation step. It MUST NOT contain
selection logic. If it fires, the correct response is to identify which semiring
failed to prune the ambiguous alternative, and fix that semiring or the grammar.

This assertion is temporary. Future iterations may run multiple surviving parses
through codegen and select by execution success.

## Where Each Semiring Operates

### Boolean

- **multiply**: AND — both sides must be true
- **on_complete**: always true (recognition only)
- **add**: trivially two-valued; identity check collapses, then OR

### Precedence

- **multiply**: Validates left-operand level against operator level. Returns
  zero for precedence violations.
- **on_complete**: Annotates completed rules with precedence info (operator
  level, associativity). Rejects invalid targets for PostfixExpression.
- **add**: Hash-cons key is `(level, assoc)`. `op` and `is_operator` are
  excluded — they are construction-time information consumed during multiply,
  not needed for identity comparison. Identity check collapses equal precedence
  contexts — two values with the same level and associativity are the same
  hash-consed object, so `refaddr` matches and they collapse to `[$left]`.
  For non-identical values: higher level (more constraining) preferred.
  PostfixExpression (level<0) preferred over AssignmentExpression (level>=100).
  This special case is transitive: PostfixExpr always beats Assignment, and
  normal numeric order applies within each range. All comparisons are symmetric
  (commutative).

### TypeInference

- **multiply**: Builds Context tree preserving children. Hash-conses nodes
  by `(rule, position, children_refaddrs)`. Propagates zero.
- **on_complete**: Whole-rule validation. Rejects keywords as identifiers at
  Atom/CallExpression. Tags types, operator text, call symbols. This is where
  TypeInference needs whole-rule context — it cannot reject `class` at scan
  time because `class => "Foo"` is valid as a fat-arrow key.
- **add**: Compares `ambiguous_unary` flag. Binary preference: `[$left]` if
  right has ambiguous unary and left does not. `[$left, $right]` when both or
  neither have it.

### Structural

**Redesigned.** Structural builds hash-consed structural contexts during
`multiply`/`on_complete`, using a bitfield representation (8 tags = 8 bits =
256 possible values). `add()` performs identity comparison only — no preferences.

- **multiply**: Builds hash-consed structural context from children.
- **on_complete**: Annotates completed rules with structural information using
  the full Context tree. Block, HashConstructor, CallExpression, etc. are
  tagged with context-aware information (not just flat boolean flags). Returns
  zero for structurally invalid interpretations based on rule position and
  content — e.g., rejecting a hash interpretation where content contains
  semicolons, or rejecting a block interpretation in expression-only position.
- **add**: Identity check via integer `==` on the bitfield. Same tag set =
  same integer = collapse to `[$left]`. Different tag sets = `[$left, $right]`.
  **No preferences, no tag comparisons, no tie-breaking.**

This eliminates all current Structural preferences. Disambiguation that
Structural's `add()` currently handles falls into three categories:

1. **Identical derivations**: Hash-consing collapses them automatically.
2. **Context-dependent choices** (block vs hash): Move to `on_complete` with
   full context tree, or resolved by TypeInference/grammar structure.
3. **Compensating for other semirings** (call vs non-call, binop preferences):
   Should be handled by Precedence, TypeInference, or grammar tightening.

Cases where removing a preference causes the end-of-parse assertion to fire
indicate a missing rejection in `on_complete` or a grammar ambiguity. These
are fixed at their source, not papered over in `add()`.

Test files most likely affected by Structural preference removal:
`grammar-ambiguity-fixes.t`, `semiring-structural.t`, `concise-per-file.t`.

### SemanticAction

- **multiply**: Builds Context tree with IR nodes as focus. Hash-conses IR
  nodes by `(operation, input_node_ids)` — the Sea of Nodes approach.
- **on_complete**: Applies semantic action via `extend`, produces IR for the
  completed rule. Equivalent derivations produce the same hash-consed IR node.
- **add**: Returns `[$left, $right]` — SemanticAction cannot distinguish
  between two IR graphs. Both survive. Identical graphs collapse at the
  FilterComposite level because their containing tuples have identical
  components across all semirings (hash-consed identity).

SemanticAction runs on every survivor in the flat FilterComposite pipeline.
With hash-consed IR, building IR for alternatives that later collapse is a
cache hit — the same node is returned. No wasted work.

## Retired Axiom: One Parse Before IR

The old design specified:

```
ChalkSyntax = Composite(Boolean, Precedence, Structural, TypeInference)
ChalkIR     = Composite(ChalkSyntax, SemanticAction)
```

This enforced "one unambiguous parse before IR generation." The new design
retires this axiom. All five semirings participate in a flat FilterComposite
pipeline. Ambiguity flows through the entire pipeline, with every semiring —
including SemanticAction — participating in pruning via `add()` and collapsing
via hash-consing.

The flat design is simpler, more uniform, and equally correct. The old axiom
protected SemanticAction from ambiguity it couldn't handle. Hash-consed IR
removes that limitation.

### Documentation Updates Required

The old two-tier axiom (`ChalkSyntax`/`ChalkIR` separation) appears in other
documents. These must be updated during migration to reflect the flat
FilterComposite design. Grep for `ChalkSyntax`, `ChalkIR`, `selects_alternative`,
and "one unambiguous parse" to find all references. Known candidates:

- `docs/semiring-architecture.md`
- `docs/chalk-parse-perl-plan.md`
- `.worktrees/bootstrap/CLAUDE.md`
- `docs/precedence-semiring.md`
- MEMORY.md (`selects_alternative()` protocol references)

## Migration Strategy: Incremental

Move rejection logic from `selects_alternative` to `multiply`/`on_complete`/`add`,
case by case. FilterComposite evolves incrementally alongside the migration —
no big-bang rewrite phase.

### Phase 1: Structural Hash-Consing + Case Migration

1. **Hash-cons Structural values as bitfield.** This is the simplest hash-cons
   (8 bits = 256 values, a lookup table). Identity collapse handles the
   "same tag set, different refaddr" cases immediately. This touches all
   value-producing methods: `zero()`, `one()`, `is_zero()`, `multiply()`,
   `on_scan()`, all 15+ `on_complete` branches (Block, HashConstructor,
   VariableDeclaration, PostfixDeref, Subscript, CallExpression, MethodCall,
   BinaryExpression, ExpressionList, ExpressionStatement, UseDeclaration,
   ParenExpr, ArrayConstructor, StatementList/Program, catch-all), and
   `add()`. The `is_zero` check changes from `!$value->{valid}` to
   `$value == 0`.

2. **Add a shim to Composite's `add()`** that unwraps the new `[$left]`/
   `[$left, $right]` return convention. During transition, the shim unwraps
   `[$x]` to `$x` (compatible with current scalar convention) and dies on
   `[$x, $y]` (multiple survivors require the full FilterComposite rewrite in
   Phase 3). This allows semirings to migrate their `add()` return type one
   at a time without a big-bang Composite rewrite. The shim is removed in
   Phase 3 when FilterComposite replaces Composite.

3. **Empirically validate "pick left" cases (2, 7, 13)** before migration.
   For each, temporarily remove the "pick left" from selects_alternative and
   run the full test suite. If SemanticAction dies, the tie-break was hiding
   a real ambiguity that needs a different fix (grammar tightening or another
   semiring's on_complete). Do this early — discovering hidden ambiguities
   mid-migration is more disruptive than discovering them upfront.

4. **Migrate each selects_alternative case** one at a time:
   a. Move the logic to `on_complete` (for context-dependent rejections) or
      `add()` (for legitimate comparisons with survivor-list returns). Verify
      tests pass — selects_alternative still works as safety net.
   b. Remove the case from selects_alternative. Verify tests still pass.
   c. Verify the surviving alternative is correct by hand-tracing one real
      input through the new path.

   During Phase 1, SemanticAction's `add()` die serves as a canary. If
   removing a Structural preference causes SemanticAction to die, the case
   is not purely structural — investigate before proceeding.

### Phase 2: Remaining Hash-Consing + SemanticAction

1. **Precedence**: Hash-cons by `(level, assoc)`. Identity collapses equal
   levels.
2. **TypeInference**: Hash-cons Context nodes by `(rule, position, children)`.
3. **SemanticAction**: Hash-cons IR nodes by `(operation, inputs)`. Change
   `add()` from die to `[$left, $right]`.

### Phase 3: FilterComposite Completion

1. **Rename Composite to FilterComposite.**
2. **Rewrite value representation** as list of tuples with broadcast
   multiply/on_complete/on_scan/is_zero.
3. **Implement `_add_single` and `_filter_compare`** with full diagnostics.
4. **Delete `selects_alternative`** from all semiring files.
5. **Generalize Earley.pm try/catch** from "Ambiguity" to "Error" context.
   Consider whether all three `add()` call sites (lines 224, 281, 341) need
   try/catch wrappers, since `_filter_compare` can die on conflict, novel
   object, or zero-in-add violations.
6. **Verify all three Earley.pm add() call sites** (lines 224, 281, 341).
7. **Add end-of-parse assertion** and survivor cap.

### Case Inventory

**Precedence** (4 preference branches in current `add()`):

| # | Branch | Current Behavior | Disposition |
|---|--------|-----------------|-------------|
| P1 | defined level vs undefined | prefer defined | identity collapse via hash-consing |
| P2 | undefined level vs defined | prefer defined (reverse) | identity collapse via hash-consing |
| P3 | PostfixExpr (level<0) vs Assignment (level>=100) | prefer PostfixExpr | `add()` with survivor-list return |
| P4 | higher level vs lower level | prefer higher | `add()` with survivor-list return |

Hash-cons by `(level, assoc)`. Identity collapses equal levels (P1/P2 become
identity checks after hash-consing since undefined-level values hash-cons
distinctly from defined-level values). P3 and P4 are legitimate directional
preferences that remain in `add()`. The PostfixExpression/Assignment special
case is transitive: PostfixExpr always beats Assignment, normal numeric order
within each range. All comparisons are commutative.

**TypeInference** (1 case):
- `ambiguous_unary` — binary flag comparison. Move to `add()` with
  survivor-list return.

**Structural** (14 cases → 0 after redesign):

| # | Case | Current Behavior | Disposition |
|---|------|-----------------|-------------|
| 1 | `is_list` vs non-`is_list` | prefer non-list | on_complete rejection or grammar |
| 2 | both `is_list` | pick left | identity collapse via hash-consing |
| 3 | `is_call` vs non-`is_call` | prefer call | on_complete or Precedence |
| 4 | both `is_call`: `is_deref` vs not | prefer non-deref | on_complete rejection |
| 5 | both `is_call`: `is_method` vs not | prefer non-method | on_complete rejection |
| 6 | both `is_call`: `is_binop` vs not | prefer non-binop | on_complete or Precedence |
| 7 | both `is_call`, identical tags | pick left | identity collapse via hash-consing |
| 8 | non-call: `is_binop` vs not | prefer non-binop | Precedence |
| 9 | non-call: `is_deref` vs not | prefer non-deref | on_complete rejection |
| 10 | `is_block` vs non-`is_block` | prefer block | on_complete with context |
| 11 | both `is_block`: `is_hash` vs not | prefer non-hash | on_complete with context |
| 12 | neither `is_block`: `is_hash` present | prefer hash | on_complete with context |
| 13 | `is_vardecl` vs non-`is_vardecl` | prefer vardecl | on_complete or TypeInference |
| 14 | both `is_binop`, identical tags | pick left | identity collapse via hash-consing |

Cases 2, 7, 14 are arbitrary "pick left" tie-breakers where both sides have
identical tag sets. With hash-consing (same bitfield = same object), these
collapse automatically. If two derivations have identical structural tags but
produce different IR, that is a genuine grammar ambiguity — the end-of-parse
assertion fires, exposing a problem that was previously papered over.

## What This Solves

- **`selects_alternative` elimination**: No coordination protocol needed. Each
  semiring prunes independently via `multiply`/`on_complete` (zeros) and `add`
  (survivor lists with hash-consed identity).
- **Merged value elimination**: `add` returns survivor lists of original
  hash-consed objects. Never synthesizes new values.
- **Implicit ordering dependency**: Gone. Semirings are order-agnostic for
  correctness. Ordering affects only performance and diagnostic quality.
- **Block/hash false preference**: Eliminated. Context-dependent disambiguation
  moves to `on_complete` where rule position and content are available.
- **Associativity/commutativity**: Hash-consing makes identity checks trivially
  commutative, associative, and idempotent. Precedence comparisons are a total
  order. The single-preference invariant ensures FilterComposite correctness.
  No non-transitive preferences exist.

### Enables a Solution For

- **Fat-arrow keyword problem**: The architecture enables fixing `class => "Foo"`
  by letting TypeInference or Structural handle it at ExpressionList or
  BinaryExpression on_complete, where the `=>` context is visible. The LHS of
  a fat arrow is always a string, making the keyword-vs-identifier distinction
  irrelevant in that context. The core challenge is that keyword rejection at
  Atom on_complete happens before the fat-arrow context is visible at
  BinaryExpression on_complete. Possible approaches include deferring keyword
  rejection to Expression on_complete, adding a FatArrowKey grammar rule, or a
  two-pass approach. The specific disambiguation rule is migration work — the
  architecture removes the constraint that forced the current premature
  rejection at Atom, but the fix must be designed and tested. See MEMORY.md
  "TypeInference Fat-Arrow Keyword Issue" for history of prior attempts and
  known failure modes.

## Completion Criteria

1. `selects_alternative` deleted from all semiring files
2. All semirings' `add()` returns `[$left]`, `[$right]`, or `[$left, $right]`
3. All semirings hash-cons their values via `one()`, `on_scan()`, `multiply()`,
   and `on_complete()` — no value construction outside the hash-cons table
4. FilterComposite value is a list of tuples with broadcast operations
5. FilterComposite `_add_single` implements Pareto-optimal survivor computation
6. `_filter_compare` checks all semirings with conflict and novel-object
   diagnostics
7. SemanticAction.add() returns `[$left, $right]` (no die)
8. All 12 test suites pass: semiring-type-inference, semiring-structural,
   semiring-precedence, semiring-composite, grammar-ambiguity-fixes,
   earley-zero-propagation, concise-actions, concise-validation,
   concise-per-file, perl-actions-fixup, perl-actions-tier-c, type-library
9. End-of-parse assertion fires zero times during the full test suite,
   excluding inputs already marked TODO
10. All three Earley.pm `add()` call sites verified with FilterComposite values
11. No semiring's `add()` creates merged/synthesized values
12. Documentation updated to reflect flat FilterComposite design

## Future Work

- **TypeInference extend redesign**: Replace `_tags()` flat merge with
  comonad `extend`-based annotation. Prerequisite: this architecture correction.
- **Type-directed SemanticAction.add()**: Compare IR graphs by type-completeness
  and simplicity. Prerequisite: TypeInference extend redesign.
- **Semiring ordering optimization**: Profile and reorder for performance once
  correctness is established. Add early return to `_filter_compare`.
- **Multiple top-level survivors**: Relax end-of-parse assertion to run multiple
  parses through codegen and select by execution success.
- **Grammar tightening**: If end-of-parse assertion fires during migration,
  investigate whether the grammar has a genuine ambiguity or a semiring needs
  a new rejection rule in `on_complete`.

## Verification

```bash
SHELL=/bin/bash /bin/bash -c 'cd /home/perigrin/dev/chalk/.worktrees/bootstrap && \
  for t in semiring-type-inference semiring-structural semiring-precedence \
    semiring-composite grammar-ambiguity-fixes earley-zero-propagation \
    concise-actions concise-validation concise-per-file \
    perl-actions-fixup perl-actions-tier-c type-library; do \
    result=$($HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/bootstrap/lib \
      t/bootstrap/$t.t 2>&1 | tail -1); echo "$t: $result"; done'
```
