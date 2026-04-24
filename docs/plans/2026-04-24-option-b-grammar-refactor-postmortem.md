# Option B Grammar Refactor — Postmortem & Deferred Work

**Status:** Rolled back 2026-04-24. Work deferred pending deeper design.
**Follow-up:** 2026-04-24 later same day — Boolean::add wrapper commits
(`2c066ae8`, `eafd6cc3`) also reverted, along with the survival test and
the walker, after discovering the entire investigation premise was
false. See "2026-04-24 follow-up" section below.

**Author:** perigrin + Claude, 2026-04-24.

**Context:** During wrapper-loss investigation, we noticed `42;` parsed
through the Perl grammar triggered one `Boolean::add(both-nonzero)` call
— a "genuine ambiguity" in a trivial input. Tracing the merge showed it
was `ExpressionStatement alt 0 (Expression)` vs `alt 1 (ExpressionList)`,
because `ExpressionList ::= Expression | ...` admitted single-element
lists. Structural's disambiguation at
`lib/Chalk/Bootstrap/Semiring/Structural.pm:197` preferred the simpler
`Expression` alt.

This is the same shape of pseudo-ambiguity the seven documented classes
in `docs/architecture/ambiguity-classes.md` describe, but was not itself
listed. The impulse — correct in principle — was to clean this up so the
ambiguity corpus only sees "real" classes.

## What we tried (Option B)

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

Plus 8 call-site rewrites to expose `Expression | ExpressionList` (or
`(Expression | ExpressionList)?`) wherever "1 or more" was intended
under the old shape.

## What we discovered

**The refactor reduces ambiguity for trivial cases** (`42;` has no
Boolean::add merge afterward) **but does not eliminate it for list-ops**
(`push @arr, $x`, `print 1, 2`, etc.). The Class 5 ambiguity
(named-unary vs list-op) is inherent to Perl and cannot be resolved at
grammar shape alone — it requires a semiring with knowledge of builtin
signatures to decide whether the call is list-op (consume all args) or
named-unary (consume first arg).

For `push @arr, $x` under the new grammar:

- `CallExpression alt 4` (`QualifiedIdentifier WS Expression`): matches
  `push @arr` with `, $x` left over (which parent rules absorb).
- `CallExpression alt 5` (`QualifiedIdentifier WS ExpressionList`):
  matches the whole thing as one call.

Both succeed recognition. They differ structurally in which derivation
"owns" the trailing argument. Disambiguation currently happens via
Structural + TypeInference + the old ExpressionList alt shape — none of
which remain valid after the refactor without substantial rework.

Downstream breakage observed: `t/bootstrap/grammar-builtin-call.t` test
6 fails because `SimpleStatement` receives 4 derivations (ExpressionStatement
with Constant focus, ExpressionStatement with Call focus, ExpressionList
returning [Call, Constant], ExpressionList returning [Call, Constant])
and the merge winner's top Context loses its `rule` field, leaving
`focus = undef`.

## Why this is a multi-day refactor, not an hour-long fix

Exploration (agent dispatch, see conversation) surfaced that the
following would all need updating coherently:

1. **Structural.pm line 159**: MethodCall alt-index check `(0 || 2)` —
   alt indices shifted; 3 alts became 8. (Done in attempt, reverted.)
2. **Structural.pm line 183**: ExpressionList `$alt_idx >= 1` — old
   alt 0 was bare Expression; new grammar has no bare-Expression alt.
3. **Structural.pm line 197**: ExpressionStatement alt 1 disambiguation
   — becomes vacuous when alts are input-disjoint for trivial cases
   but may still matter for list-op cases (unclear).
4. **TypeInferenceActions.pm line 173**: ExpressionList method switches
   on alt_idx; all indices shifted. (Done in attempt, reverted.)
5. **Precedence.pm**: CallExpression "pass through" logic (line 430-437)
   may need to distinguish single-arg vs multi-arg calls.
6. **The new Class 5 ambiguity** at `CallExpression alt 4 vs alt 5` needs
   a disambiguation rule. Cleanest path is likely TypeInference
   comparing list_arity against the builtin's signature — but that
   infrastructure currently relies on the old ExpressionList alt shape.
7. **Semantic action audits**: `Perl::Actions::CallExpression`,
   `ExpressionList`, `MethodCall`, `ArrayConstructor`, `HashConstructor`
   all need verification that they still produce correct IR under the
   new alt indices.

Each of these interacts with the others. A staged incremental fix
requires a clear acceptance test for each stage, and most of the
candidate "acceptance tests" depend on infrastructure that itself was
tuned for the old grammar.

## What was committed anyway

The **walker visited-set fix** (`5ac40a7b`) and the **synthetic
regression guard** (`4d119b04`) stay in. They're orthogonal to Option B
— they would be needed regardless.

The grammar, Structural, and TypeInferenceActions changes were reverted.

## What remains worth doing

**Short-term**: accept that `42;` produces 1 spurious `add` call per
trivial expression statement. The cost is small (one Boolean::add per
ExpressionStatement) and Structural correctly picks the right parse.
The ambiguity corpus will eventually want to exempt this case.

**Medium-term**: When we return to grammar refactoring, approach it as a
dedicated multi-day effort with:
- A concrete acceptance test per change (the `ambiguity-perl-survival.t`
  red test is one; more will be needed).
- An ordering plan that lets each change land independently.
- A rollback strategy per change.
- Honest scope: probably 2-5 days of focused work.

**Long-term**: The Invariant #1 claim in `ambiguity-classes.md` ("Grammar
+ Boolean produces ambiguity ONLY in these seven classes") is currently
**unproven** because the wrapper-loss bug makes Boolean-level ambiguity
invisible. The corpus cannot verify it. Fixing wrapper-loss is
prerequisite to validating the ambiguity contract — which is why we
went down this path to begin with.

## Lessons

1. **Brainstorming sized the change optimistically.** The claim "Option
   B's branches admit disjoint inputs so no new ambiguity" was partially
   true (eliminates trivial case) but fully false for list-op cases.
   The disjointness property holds at `ExpressionList`'s own rule
   level but not at every consumer's alternatives.

2. **"Fix first principles" is principled, but principle alone doesn't
   eliminate ambiguity that is semantically real.** Class 5 is inherent
   to Perl. No grammar shape removes it.

3. **Validation should come before work.** We committed to a 1-2 hour
   estimate without a test that would prove success. When the work
   expanded, we had no signal to say "this specific change is right"
   except running existing tests and hoping.

4. **The `t/bootstrap/ambiguity-perl-survival.t` red test** (added
   alongside this postmortem) is the test Option B was missing. It
   asserts that *any* ambiguous wrapper survives into the returned
   Context for known-ambiguous inputs. Currently TODO-failing. Any
   future wrapper-loss fix can measure itself against this.

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
verify. It currently can't because of wrapper-loss. Fix wrapper-loss,
then verify the invariant mechanically. The new survival test is step
1 of this.

**Flaw class 4: Disambiguation infrastructure drift.** Structural's
per-rule tagging relies on alt_idx stability. Any grammar change can
silently break it. Write a test that parses a corpus of representative
Perl snippets and asserts the *structural tag values* match expected
— treating them as an observable contract. If the tags drift, we learn
immediately. Currently there's no such test.

**Flaw class 5: Hidden grammar ambiguities.** Scan the grammar for
pseudo-ambiguities (rules admitting the same input in multiple ways)
and either document them as classes or eliminate them. The class 8
case (`ExpressionStatement Expression | ExpressionList`) is an example.
A mechanical grammar-ambiguity-detector tool would be a valuable
addition — it doesn't exist today.

**Of these, classes 2 and 4 are the cheapest and most valuable starting
points.** Both are implementable without the wrapper-loss fix. Class 3
requires wrapper-loss fixed first.

The uneasy truth: we don't currently have infrastructure to prove the
system is flaw-free. The work items above would establish it. Roughly
ordered: class 4 (1-2 days) → class 2 (2-3 days) → class 1 (open-ended,
bound by reference-impl choice) → class 3 (blocked on wrapper-loss) →
class 5 (ongoing).

## 2026-04-24 follow-up: the premise was false

After the rollback, we asked: "wait, does Boolean even run in the
FilterComposite production path?" Investigation of
`lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:16-22`:

```perl
method _annotation_semirings() {
    return grep {
        blessed($_) && $_->can('slot_name') && defined $_->slot_name()
    } $semirings->@[0 .. $#{ $semirings } - 1];
}
```

Boolean's `slot_name()` returns `undef` (documented at
`lib/Chalk/Bootstrap/Semiring/Boolean.pm:80-83` and in commit
`d0ddfb44`'s message). Therefore `_annotation_semirings()` filters it
out. FilterComposite never calls Boolean's `multiply` or `add` on
anything.

Boolean is vestigial in FilterComposite — present in the constructor
array for symbolic symmetry but never executed. The actual
yes/no-recognition role is played by `Chalk::Bootstrap::Context`'s
`is_zero` field, which every semiring respects.

**Implications for wrapper-loss**:

1. The commits `2c066ae8` and `eafd6cc3` added wrapper behavior to
   `Boolean::add`. FilterComposite never calls that code path.
2. The wrappers only appear when Boolean is used *standalone* (via
   `build_perl_recognizer`, which constructs Earley with Boolean as
   the semiring parameter, bypassing FilterComposite).
3. The "wrapper-loss" phenomenon is specific to the Boolean-standalone
   codepath. It does not affect production parsing.
4. The use case for Boolean-standalone-with-wrappers was the ambiguity
   corpus (verify Invariant #1 in `ambiguity-classes.md`). That use
   case has better alternatives: (a) count-only audit via `add`
   instrumentation without wrapping, (b) classify-at-creation via
   side channel, (c) capture FilterComposite's `_filter_compare`
   losers.

**What we reverted in the follow-up**:

- Commit `2c066ae8` (Boolean::add preserves both derivations).
- Commit `eafd6cc3` (Boolean::add tags wrapper with `ambiguous`).
- `t/bootstrap/ambiguity-perl-survival.t` — the red test measuring a
  fix we no longer need.
- `t/bootstrap/ambiguity-analysis.t` — tests for the walker that
  inspected the no-longer-existing tags.
- `t/bootstrap/lib/AmbiguityAnalysis.pm` — the walker itself.

**What we kept**:

- `t/bootstrap/ambiguity-synthetic.t` — the Earley merge-count
  regression guard is still useful; it counts `add` calls not wrappers.
- `t/bootstrap/filtercomposite-production-check.t` — confirms
  production IR is sound; orthogonal to the wrapper investigation.
- This postmortem — captures both the Option B attempt and the
  Boolean-standalone premise discovery.
- The design note
  `docs/plans/2026-04-23-earley-reification-overwrites-add-merge-design.md`
  is left in place as history, but its conclusion (that line 590 in
  Earley.pm overwrites wrappers) is moot — wrappers no longer exist.

**Removing Boolean's vestigial presence in FilterComposite**: a follow-up
cleanup. Boolean is still in the `semirings` array but never invoked.
Removing it from the constructor would simplify the design. That's a
separate, smaller change tracked as a follow-up task.

**Lesson of the follow-up**: we spent a session chasing a bug in a
codepath that isn't used. The red flag was present earlier (`slot_name
=> undef` documented in commit `d0ddfb44`), but I didn't connect it to
wrapper-loss until perigrin asked "what?" on my offhand statement that
FilterComposite bypasses Boolean's `add`. Reading Boolean as an input
to every disambiguation decision was wrong; Context's `is_zero` flag
already fills that role.
