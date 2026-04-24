# Semiring Contract Drift — Three Semirings Violate (Context, Context) -> Context

**Status:** Finding / design note. No code changes yet.

**Author:** perigrin + Claude, 2026-04-24.

**Origin:** While designing grammar-audit instrumentation, I claimed Boolean was anomalous for storing Context-typed values in its annotation slot. perigrin challenged the claim. Checking the record showed the opposite: **Boolean is the one honoring the documented contract**, while Precedence, Structural, and TypeInference drifted away from it.

## The contract

`docs/plans/2026-04-12-unified-context-design.md` line 179:

> Each semiring's operation is pure: `(Context, Context) -> Context`.

Commit `f3d5fb43` (2026-04-12, "Boolean semiring returns Contexts (unified-context Step B)") reinforces:

> Every semiring (TI, Precedence, Structural, SemanticAction, FilterComposite) already obeys the `(Context, Context) -> Context` invariant documented in docs/plans/2026-04-12-unified-context-design.md. Boolean was the last holdout, returning bare `true` from one()/multiply()/add() and an arrayref singleton from zero().

That commit's claim "every [other] semiring already obeys" was likely *aspirational* at the time, or was true for a narrow definition of "obey" that got lost in later changes. The current code doesn't obey.

## Current violations

Verified by reading the code 2026-04-24:

| Semiring | zero() returns | one() returns | multiply() returns | Contract? |
|---|---|---|---|---|
| Boolean | Context (is_zero=true) | Context (is_zero=false) | Context | **honors** |
| SemanticAction | undef | Context | Context (via `_mul_ctx` or `_complete_sa`) | partially (zero violates) |
| Precedence | hash ref `_intern(false,...)` | hash ref `_intern(true,...)` | hash ref | **violates** |
| Structural | integer `-1` | integer `0` | integer | **violates** |
| TypeInference | undef | Context wrapping tag hash | **mixed** — tag hash for scan/complete, Context otherwise | **violates** |
| FilterComposite | Context (is_zero=true) | Context | Context (via `_wrap_sa_result`) | honors |

Three full violations (Precedence, Structural, TypeInference), one partial (SemanticAction's `zero()`), and Boolean + FilterComposite honoring.

## How the system still works

FilterComposite papers over the drift via per-semiring slot-value accommodation:

1. Each non-compliant semiring has a private `_slot_val` helper that unwraps the slot value from a Context if one is passed, or returns the raw value. See `Precedence.pm:86-92`, `Structural.pm:57-64`, `TypeInference.pm` inline in multiply.

2. FilterComposite's `_filter_compare` reads `$left->annotations()->{$slot}` and `$right->annotations()->{$slot}` — i.e., extracts the raw slot value before calling the semiring's `add`. See `FilterComposite.pm:198-199`.

3. FilterComposite's `_wrap_sa_result` places each semiring's multiply result directly into the winner's annotation slot. If the semiring returned a scalar, the slot holds a scalar. If it returned a Context, the slot holds a Context. See `FilterComposite.pm:96-98`.

4. TypeInference's mixed-type multiply is explicitly special-cased in FilterComposite. See `FilterComposite.pm:149-152` ("TI returns a tag hash directly for complete events").

So the drift is **known to FilterComposite** and accommodated. But it's accommodation, not adherence. The contract is not being enforced.

## Why this matters

1. **Reasoning about the system is harder than it should be.** Every time I look at a semiring's output I have to check whether it returns Contexts or scalars, and in what cases. The contract existed to eliminate that overhead.

2. **New work gets written to whatever pattern is visible.** If I'm writing a semiring tomorrow and grep the codebase, I see mixed patterns. The contract says "Context in, Context out" but the code says "sometimes scalar." Without an enforcement mechanism, drift compounds.

3. **My claim earlier today ("Boolean stores Contexts, unlike others") exemplifies the confusion.** I read the code and concluded Boolean was the anomaly. It took perigrin pointing at the record to correct me. If the system had been contract-compliant, this confusion wouldn't have arisen — all semirings would have returned Contexts.

4. **Audit and instrumentation work is cleaner when all semirings return Contexts.** Grammar-ambiguity audit wants to record merge events on winner Contexts. If every semiring's output is a Context with known annotation slots, the audit writes a single traversal. With mixed scalar/Context slot values, the audit needs per-slot logic to decode.

5. **Semiring-law testing (flaw-class 2 in the Option B postmortem) is impossible while the contract isn't enforced.** The laws (associativity, distributivity, etc.) are stated over the semiring's carrier set. The current carrier set is underspecified — "sometimes Context, sometimes scalar, depends on the op." Law tests need a uniform type to check against.

## Why fixing this is non-trivial

Each of the three non-compliant semirings has hot-path performance reasons for scalar values:

- **Structural** uses bitwise OR on integers for tag combination. Wrapping the integer in a Context for every multiply is a lot of allocation.
- **Precedence** uses hash-cons on small fixed-shape hashrefs. Hash refs are dirt cheap; Contexts have more fields.
- **TypeInference** uses tag hashes for scan/complete events as a lightweight result type.

Bringing them into contract means:

1. Either the scalar values get wrapped in singleton Contexts (lazy-initialized, hash-consed) that carry the scalar in `focus` or in a specific annotation, OR
2. The contract itself gets relaxed to acknowledge "each semiring's value type is its own, but must at least always be the *same* type per semiring (no mixed scalar/Context within one semiring)."

Option 2 is the softer fix and arguably more honest — the current system isn't `(Context, Context) -> Context` in practice; it's `(T, T) -> T` where T is per-semiring. Fixing the contract to match observed practice is less disruptive than fixing the implementations to match the aspirational contract.

## Proposed direction

**Short-term (0-day)**: document the drift (this note). Make future readers aware that the contract in `docs/plans/2026-04-12-unified-context-design.md` is aspirational, not enforced, and that three semirings violate it.

**Medium-term (1-2 days per semiring)**: bring semirings into contract one at a time. Cheapest first:

1. **SemanticAction.zero()** — currently returns `undef`. Easy fix: return a Context with `is_zero=true`, matching Boolean/FilterComposite.
2. **TypeInference**: eliminate mixed types. Decide: always return Context wrapping the tag hash in `focus`, or always return tag hashes without Context wrapping. Structural follows similar pattern either way.
3. **Precedence**: wrap hash refs in Contexts. Slightly more work because hash-cons identity has to survive wrapping.
4. **Structural**: wrap integers in Contexts. Most invasive because integer equality and bitwise ops are everywhere.

Each step has a concrete acceptance test: its slot contract is uniform across all call paths.

**Long-term**: once all semirings honor `(Context, Context) -> Context`, write a test that asserts the contract mechanically — e.g., `is_zero($x)` iff `$x->is_zero()`, for every semiring.

**Optional long-term alternative**: relax the contract to `(T, T) -> T` with T per-semiring. Write this as an update to `2026-04-12-unified-context-design.md` acknowledging the non-uniform carrier set. Less principled but matches reality.

## What this means for current work

1. The grammar-audit instrumentation (next design step) should proceed by recording merges as **annotations on FilterComposite's winner Context**. Because FilterComposite itself does return Contexts, this part of the system honors the contract and the annotation-based log works naturally.

2. **Do not "fix" Boolean's Context-returning behavior to match Precedence/Structural.** That would be regressing the one compliant semiring toward the non-compliant pattern. The arrow should point the other way.

3. **The Boolean activation in commit `23034e7b` is correct.** My earlier proposal to revert it on grounds of "wrong slot contract" was wrong; Boolean is the one doing slot contract correctly.

## Record of this mistake

The direct trigger for this note was my claim:

> "Boolean stores Contexts, unlike others which store scalars. That's an inconsistency I introduced."

perigrin correctly challenged: "Validate this." The validation found the opposite — Boolean is compliant; others aren't. I had invented an explanation that reversed the actual situation, and would have reverted a correct commit on that basis.

The lesson: **when a claim about system design contradicts a documented design, check the document before acting on the claim.** The record said `(Context, Context) -> Context`. I claimed Boolean violated it. I should have read the record first.
