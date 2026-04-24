# Option B Grammar Refactor — Postmortem & Deferred Work

**Status:** Rolled back 2026-04-24 after one specific implementation
approach didn't pass tests. The broader question — can we eliminate the
`Expression vs ExpressionList(single)` pseudo-ambiguity — remains open.

**Update 2026-04-24 late day:** The Boolean-vestigial observation that
followed the rollback led to a separate fix (Boolean now actively
participates in FilterComposite). See "2026-04-24 follow-up" section.

**Author:** perigrin + Claude, 2026-04-24.

## What prompted the attempt

While investigating something else, we noticed `42;` parsed through the
Perl grammar triggered one `Boolean::add(both-nonzero)` call — a
"genuine ambiguity" in a trivial input. Tracing the merge showed it was
`ExpressionStatement alt 0 (Expression)` vs `alt 1 (ExpressionList)`,
because `ExpressionList ::= Expression | ...` admitted single-element
lists. Structural's disambiguation at
`lib/Chalk/Bootstrap/Semiring/Structural.pm:197` preferred the simpler
`Expression` alt.

This pseudo-ambiguity is not listed among the seven classes in
`docs/architecture/ambiguity-classes.md`, but it has the same shape.
Principled impulse: clean it up so the grammar admits ambiguity only
for the documented classes.

## What Option B tried

Refactor `ExpressionList` to require ≥2 elements, making it structurally
disjoint from bare `Expression`:

```
ExpressionList ::= ExpressionList _ /,/ _ Expression
                 | ExpressionList _ /=>/ _ Expression
                 | Expression _ /,/ _ Expression
                 | Expression _ /=>/ _ Expression
                 | ExpressionList _ /,/
                 | Expression _ /,/ ;
```

Plus 8 call-site rewrites to expose `Expression | ExpressionList`
(or similar) wherever "1 or more" was intended under the old shape.

## What actually happened

**For trivial cases, the refactor worked.** `42;` no longer produced an
`ExpressionList(Expression)` alternative; only the bare `Expression`
alt matched at `ExpressionStatement`.

**`grammar-builtin-call.t` test 6 failed** on `push @arr, $x`. The
refactored grammar created a new ambiguity at `CallExpression`'s
no-paren form:

- `CallExpression alt 4` (`QualifiedIdentifier WS Expression`):
  matches `push @arr` as the body Expression, with `, $x` left for
  parent rules to absorb.
- `CallExpression alt 5` (`QualifiedIdentifier WS ExpressionList`):
  matches the whole thing as one call with multi-arg ExpressionList.

Both succeed recognition. They differ in which derivation owns the
trailing argument. The existing disambiguation infrastructure was
tuned for the old `ExpressionList` alt shape — specifically:

- `Structural.pm:159` (MethodCall alt-index check): 3 alts became 8,
  the `(0 || 2)` check was now wrong.
- `Structural.pm:183` (ExpressionList alts ≥1): remapped but not yet
  correct for the new alt layout.
- `Structural.pm:197` (ExpressionStatement alt 1): arguably no longer
  needed under new alts.
- `TypeInferenceActions.pm:173` (ExpressionList method): switches on
  `$alt_idx`; all indices shifted.

I updated (1) and (4) during the attempt, but test 6 still failed
because the new `CallExpression alt 4 vs alt 5` choice had no
disambiguation rule. `push @arr, $x` ended up producing four parallel
derivations at SimpleStatement and the merge chose badly.

## What I incorrectly concluded at the time

I wrote in earlier drafts of this postmortem:

> "Class 5 ambiguity is inherent to Perl and cannot be resolved at
>  grammar shape alone."

**That was wrong in a specific way.** There *is* a real ambiguity at
the grammar level in the refactored shape — `push @arr, $x` admits two
derivation trees. What I got wrong was the framing of *why* the grammar
can't resolve it.

The accurate framing (per perigrin): **the ambiguity needs to be
decided by a semiring with access to a type library that knows the
arity of all functions in scope.** `push` is a list-op in Perl's type
library; its signature says it consumes its argument list. The grammar
doesn't carry arity information, so the grammar alone can't decide
which derivation is correct. But a semiring that consults the type
library can.

This is a crucial distinction from my earlier "inherent to Perl"
framing. The ambiguity isn't mystical — it's fully resolvable. The
resolution just belongs to the **TypeInference semiring**, which
already has `builtin_lookup` access to the type library and already
tracks `list_arity` on `ExpressionList`. TypeInference should zero
out derivations where the call's argument count doesn't match the
builtin's signature. Structural should not be making this call — it
doesn't have access to signatures.

What I actually did wrong in the Option B attempt:

1. **I never established this was Class 5** (named-unary vs list-op)
   specifically. The ambiguity I hit has the same flavor but I didn't
   verify the mechanism.
2. **I didn't reach for TypeInference.** When test 6 failed, I tried
   to patch it via Structural tagging updates and gave up when that
   proved fiddly. The principled fix is updating TypeInference's
   `CallExpression` handling to be signature-aware, which is where
   the type library lives and where this decision belongs.
3. **I generalized prematurely.** One failing test became "Option B
   can't work"; in reality it was "Option B, with Structural-only
   disambiguation, doesn't work — but I never tried moving the
   disambiguation to TypeInference where it belongs."

## The principled path forward (not explored in this session)

The `CallExpression alt 4 vs alt 5` ambiguity that test 6 exposed is
resolvable at the TypeInference layer, not the grammar layer. Specifically:

**TypeInference becomes signature-aware at CallExpression completion.**

When `CallExpression` completes, TypeInference already knows the
`call_symbol` (the QualifiedIdentifier text, e.g., `"push"`) and has
access to the type library via `builtin_lookup`. It also knows the
`list_arity` of its ExpressionList child (if any) or the single-value
arity of its Expression child. The missing piece: TypeInference should
consult the builtin's signature and **zero out derivations whose
argument shape doesn't match**.

For `push @arr, $x`:
- `CallExpression alt 4` (push with single arg `@arr`, leftover `, $x`)
  — signature says push takes a list ≥1, but the argument presented to
  THIS CallExpression is arity 1. More importantly, the grammar-level
  problem is that the leftover `, $x` ends up parsed by an outer rule.
  TypeInference needs to recognize that a list-op with more input
  available should consume it — i.e., prefer the longer match.
- `CallExpression alt 5` (push with ExpressionList `@arr, $x`)
  — signature says push takes a list, arity 2 satisfies. Valid.

The right TypeInference rule is roughly: "for a list-op builtin in
`QualifiedIdentifier WS ExpressionList` position, prefer the derivation
with higher arity." That's a few lines in TypeInferenceActions, not a
grammar refactor.

Alternative grammar shapes that might avoid the ambiguity entirely:

1. **Keep `ExpressionList?` unchanged at CallExpression call sites.**
   Restrict `ExpressionList` to ≥2 only where the original
   pseudo-ambiguity lives (ExpressionStatement). Minimum-scope.

2. **Introduce a helper rule `ArgList` that admits 1+ expressions**
   for use at call sites; keep `ExpressionList` as strict ≥2 at list
   contexts. `ArgList ::= Expression | ArgList _ sep _ Expression | ...`.
   Preserves "1+ args" semantics without re-introducing the overlap
   at list contexts.

These are grammar workarounds for what is fundamentally a semantic
question (what's the arity of this call?). The principled answer puts
the decision at TypeInference. The grammar workarounds are acceptable
if TypeInference-signature-awareness proves more work than expected,
but they are workarounds, not the right fix.

None of these were attempted. The correct story is that we ran out of
time/appetite in the session, not that the approach is impossible.

## Why this is at least a multi-day refactor

Independent of which alternative we pursue, the full grammar refactor
(any form of Option B) requires coherent updates across:

1. Grammar (`docs/chalk-bootstrap.bnf`) — the alt shape.
2. Structural.pm tagging blocks at lines 159, 183, 197 — alt indices
   they switch on.
3. TypeInferenceActions.pm ExpressionList method — alt dispatch.
4. Precedence.pm CallExpression handling — may need arity awareness
   depending on which alternative we pick.
5. Semantic action audits — Perl::Actions::CallExpression,
   ExpressionList, MethodCall, ArrayConstructor, HashConstructor.
6. Test coverage for each disambiguation rule — to assert it still
   picks the right derivation after the change.

Each of these interacts with the others. Honest scope: 2-5 days of
focused work with good test harnesses. Not an hour.

## What was committed anyway

The **walker visited-set fix** (`5ac40a7b`) and the **synthetic
regression guard** (`4d119b04`) stay in. They're orthogonal to Option B
— they would be needed regardless.

The grammar, Structural, and TypeInferenceActions changes were reverted.

## What remains worth doing

**Short-term**: accept that `42;` produces 1 spurious `add` call per
trivial expression statement under the current grammar. The cost is
small and Structural correctly picks the right parse. Document this
pseudo-ambiguity as a known class-8-candidate until we refactor.

**Medium-term**: When we return to Option B, pick one of the four
alternatives above and pursue it with:

- A concrete acceptance test per change (the synthetic probe pattern
  is a good template — assert specific `add`-call counts on specific
  inputs).
- An ordering plan that lets each change land independently.
- A rollback strategy per change.

**Long-term**: Invariant #1 in `ambiguity-classes.md` ("Grammar + Boolean
produces ambiguity ONLY in these seven classes") can now be mechanically
verified, since Boolean actively participates in FilterComposite (see
follow-up section) and its `add`-merge counts are observable via
instrumentation. That's the corpus infrastructure we originally wanted.

## Lessons

1. **Brainstorming sized the change optimistically.** The claim "Option
   B's branches admit disjoint inputs so no new ambiguity" held for
   `ExpressionList`'s own rule but did not carry through to every call
   site's alternative set. I should have walked through at least one
   specific call site (CallExpression) before accepting the brainstorm.

2. **"Premature generalization from one failing test."** When test 6
   failed, I concluded Option B couldn't work. In reality I had hit
   one disambiguation gap in one specific implementation. The right
   response was to either fix the gap or try a different Option B
   shape, not to abandon the approach.

3. **Validation should come before work.** We committed to a 1-2 hour
   estimate without a test that would prove success. When the work
   expanded, we had no signal to say "this specific change is right"
   except running existing tests and hoping.

4. **"Inherent to Perl" is a rationalization trap.** If I find myself
   reaching for "this is inherent" as an explanation for why a specific
   attempt didn't work, I should stop and ask: inherent to the
   language, or inherent to *my chosen formalization* of the language?
   Those are usually different.

## How to prove there are no fundamental flaws

This question was raised during Option B's retreat: if Option B failed,
how can we trust that Chalk's system is sound? A concrete plan:

**Flaw class 1: Earley invariant violations.** Write differential
tests against a reference Earley implementation (or against a
known-correct small-grammar oracle). The synthetic probe
(`ambiguity-synthetic.t`) already does this for add-merge counts on
tiny grammars. Expanding that to cover: completion ordering, nullable
handling, left-recursion, Leo-equivalence.

**Flaw class 2: Semiring algebra violations.** Boolean, Precedence,
TypeInference, Structural, and SemanticAction are all declared
semirings. Each should satisfy the semiring laws: `add` commutative and
associative, `multiply` associative, `multiply` distributes over `add`,
zero is absorbing, one is identity. Write property-based tests
(Chalk::Test::Property or similar) that exercise these laws. Currently
none exist — that's a real gap.

**Flaw class 3: Grammar invariants violated silently.** Invariant #1 of
`ambiguity-classes.md` is an architectural claim that the corpus should
verify. Now that Boolean actively participates in FilterComposite, we
can instrument `Boolean::add` to count both-non-zero merges during
real parses and assert the count matches the expected documented
classes. No wrapper-loss workaround needed.

**Flaw class 4: Disambiguation infrastructure drift.** Structural's
per-rule tagging relies on alt_idx stability. Any grammar change can
silently break it — as Option B's attempt demonstrated. Write a test
that parses a corpus of representative Perl snippets and asserts the
*structural tag values* match expected — treating them as an
observable contract. If the tags drift, we learn immediately.
Currently there's no such test. Option B would have benefited from one.

**Flaw class 5: Hidden grammar ambiguities.** Scan the grammar for
pseudo-ambiguities (rules admitting the same input in multiple ways)
and either document them as classes or eliminate them. The
`ExpressionStatement Expression | ExpressionList` case is an example;
others likely exist. A mechanical grammar-ambiguity-detector tool
would be a valuable addition — it doesn't exist today.

**Of these, classes 2 and 4 are the cheapest and most valuable starting
points.** Both are implementable independently of any grammar refactor.

Rough ordering: class 4 (1-2 days) → class 2 (2-3 days) → class 1
(open-ended, bound by reference-impl choice) → class 3 (possible now
that Boolean is active) → class 5 (ongoing).

## 2026-04-24 follow-up: Boolean was vestigial; now it isn't

After the Option B rollback, we asked: "does Boolean even run in the
FilterComposite production path?" Investigation of
`lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:16-22` showed:

```perl
method _annotation_semirings() {
    return grep {
        blessed($_) && $_->can('slot_name') && defined $_->slot_name()
    } $semirings->@[0 .. $#{ $semirings } - 1];
}
```

Boolean's `slot_name()` returned `undef`, so `_annotation_semirings()`
filtered it out. FilterComposite never called Boolean's `multiply`
or `add` on anything flowing through parse.

Two paths from there:

**Path 1 (first attempted, then reverted)**: remove Boolean from the
TestPipeline constructor array. This made the array match the runtime
reality (Boolean wasn't running anyway). perigrin correctly pushed
back: that treats the symptom (Boolean in array does nothing) rather
than the cause (Boolean should do something). Reverted as commit
`eae2b39c`.

**Path 2 (committed as `23034e7b`)**: activate Boolean as a real filter
semiring. Change `slot_name` from `undef` to `'boolean'`, have `multiply`
write `annotations->{boolean} = true` on non-zero results, leave `add`
semantics unchanged (deterministic left tie-break, which under
FilterComposite's `_filter_compare` protocol signals "no preference"
and defers to lower-priority filters).

**Verification** (commit `23034e7b`): 786 tests pass across the tight
9-file set. New test `boolean-active-in-composite.t` asserts Boolean's
multiply fires 156 times during a `1 + 2` parse and that the returned
Context has `annotations->{boolean}` populated. Boolean is now
genuinely part of the filter stack.

**What this unlocks**: the ambiguity corpus can now instrument
`Boolean::add` under FilterComposite to count merges per parse. This
replaces the wrapper-based approach (commits `2c066ae8`/`eafd6cc3`,
reverted as `434b03b7`/`6ea3e63b`) with instrumentation on an active
codepath. No wrapper-loss investigation needed.

**Reverted in the wrapper-loss cleanup** (`6d7bf7f0`, `434b03b7`,
`6ea3e63b`):

- Commit `2c066ae8` (Boolean::add preserves both derivations).
- Commit `eafd6cc3` (Boolean::add tags wrapper with `ambiguous`).
- `t/bootstrap/ambiguity-perl-survival.t` — the red test measuring a
  fix we no longer need.
- `t/bootstrap/ambiguity-analysis.t` — tests for the walker that
  inspected the no-longer-existing tags.
- `t/bootstrap/lib/AmbiguityAnalysis.pm` — the walker itself.

**Kept**:

- `t/bootstrap/ambiguity-synthetic.t` — Earley merge-count regression
  guard; still useful because it counts `add` calls, not wrappers.
- `t/bootstrap/filtercomposite-production-check.t` — confirms
  production IR is sound; orthogonal.
- `t/bootstrap/boolean-active-in-composite.t` — new, ensures Boolean
  doesn't silently regress to vestigial status.
- This postmortem — captures Option B's failure mode and the Boolean
  activation that followed.
- The design note
  `docs/plans/2026-04-23-earley-reification-overwrites-add-merge-design.md`
  is left as history. Its specific conclusion (Earley.pm line 590
  overwrites wrappers) is moot now that wrappers don't exist, but the
  investigation process documented there may be useful.

**Lesson of the follow-up**: the red flag for Boolean-vestigial-ness
was present in commit `d0ddfb44`'s message ("Boolean: undef (operates
through is_zero only, no annotation slot)") but I didn't connect it to
wrapper-loss until perigrin asked "what?" on my offhand statement that
FilterComposite bypasses Boolean's `add`. Reading slot_name=undef as
"Boolean is properly handled elsewhere" rather than "Boolean is
silently not running" was the framing error.
