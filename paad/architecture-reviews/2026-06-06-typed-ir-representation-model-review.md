# Architecture Review: Typed-IR Representation Model

ABOUTME: Skeptical soundness review of the proposed typed-IR representation model.
ABOUTME: Diagnoses hash-consing-vs-representation, Coerce-node, trust-boundary, and Scalar-fallback risks; proposes no fixes.

**Date:** 2026-06-06
**Reviewer role:** skeptic / pressure-tester (read-only, diagnosis only)
**Documents under review:**
- `docs/architecture/typed-ir-representation.md` (the MODEL)
- `docs/architecture/perl-type-system-formal.md` (the latent lattice it builds on)
- `docs/plans/2026-06-06-three-axis-codegen-and-typed-ir-contract.md` (the Phase 3 plan it serves)

**Code consulted (model-meets-reality):**
- `lib/Chalk/IR/Node.pm` (content_hash, control_in, schedule_data)
- `lib/Chalk/IR/NodeFactory.pm` (hash-consing in `make()`)
- `lib/Chalk/IR/Node/Constant.pm` (const_type in content_hash)
- `lib/Chalk/IR/Node/BinOp.pm`, `Add.pm`, `Phi.pm`
- `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` (today's late representation decision)
- `t/spike/llvm/add.ll` (the proven trivial case)

---

## TL;DR / BOTTOM LINE

The model is **directionally sound and worth committing to as the Phase 3 thesis**
— the SSA-single-representation insight, coercion-as-explicit-edge, and
optimization=lowering equivalence are genuinely right and must be protected.

BUT it has **one real soundness hole that the doc must close before 3a starts**,
and three smaller design gaps. The hole is the **hash-consing-vs-representation
contradiction (Risk H1)**: the doc asserts "a value has ONE representation" AND
relies on hash-consing, but does not say whether representation is *in* or *out*
of `content_hash`. The code (`Node.pm:79`, `Constant.pm:15`) makes this a
concrete fork with opposite consequences, and the doc currently has it both ways.
This is decidable on paper now; it should not be discovered empirically at 3c.

The `1 + 2` spike proves nothing about any of this, exactly as the task framing
warns: `t/spike/llvm/add.ll` has no variables, no shared literals, no coercion,
no Scalar, no Phi, no overflow — it exercises zero of the model's load-bearing
claims.

Verdict: **SOUND ENOUGH to commit as the thesis; NOT sound enough to start 3a
until H1 is resolved in the doc and the coverage-measure gap (Risk H3) is added
to the plan.** Specific holes to close listed at the end.

---

## STRENGTHS (ranked — protect these through Phase 3)

### S1. Coercion-as-explicit-edge is the correct, load-bearing decision (protect hardest)
Making Perl's implicit coercions into explicit `Coerce` nodes
(`typed-ir-representation.md` §2) is the single most valuable idea here. It
localizes ALL the messy Perl semantics (NaN, dualvar, locale, `"0 but true"`,
warnings) onto one node kind instead of smearing it across every operation.
This is exactly how real typed SSA IRs work (LLVM's explicit `sitofp`/`zext`),
and it is what lets `Add` have a clean contract ("Num operands in, Num out").
Everything else in the model depends on this. It is right. Keep it.

### S2. Single-representation-at-rest is the correct SSA discipline
"A def has one definite representation" (§1) is the property that makes lowering
mechanical. It is the difference between "an IR" and "a tree the runtime
interprets." It also matches what SoN already half-is (SSA, hash-consed,
use-def chains — `Node.pm:13-17`). Protect it — but see H1: it is in *tension*
with hash-consing and must be reconciled, not just asserted.

### S3. optimization == lowering equivalence is a genuine insight, not a slogan
The plan's claim (three-axis doc, "the information a runtime-free target forces
into the IR is the same information optimization needs") is correct and well
-argued. The unboxing guards (no magic/overload/tie/dualvar, integer-stays
-integer) ARE the formal doc's semantic-contract violators (formal doc Examples
3, 4; NaN ∉ Num, DualVar ∉ Num/Int). The two documents genuinely compose on
this point. This reframing — that the LLVM corner is a forcing function, not a
nicety — is the strongest part of the plan and should be preserved verbatim.

### S4. Scalar-as-TOP fallback is conceptually correct
Treating boxed-SV as the top of a representation lattice (§4), the always
-correct conservative fallback, is the right shape. It mirrors `Scalar` near the
top of the latent lattice and gives a principled home for genuinely-dynamic
values. The *concept* is sound; the *risk* is purely operational (H3 — it can
become a silent escape hatch). Protect the concept; instrument against the abuse.

### S5. CodeGen-verified-first via hand-authored typed graphs is the right trust model
Specifying the contract with hand-authored graphs that lower to LLVM and match
perl (§"Validation plan") keeps the untrusted parser out of the loop. This is
consistent with how the rest of the harness works and is the correct way to
pin a contract before the producer exists. (But see H2: it relocates the
coercion-placement judgment into the hand-author's head — that needs a
checkable invariant, not just trust.)

---

## FLAWS / RISKS (ranked High / Med / Low)

### H1 — HIGH — Hash-consing vs representation is an unresolved contradiction (the real hole)

This is the central soundness question and the doc currently answers it both ways.

**The facts from code:**
- `Node.pm:79-81`: `content_hash() = join('|', operation(), serialized_inputs())`.
- `Node.pm:29-31`: `control_in` is **explicitly excluded** from content_hash, with
  a comment naming the exact rule: "side-effect vs pure-data uses of the same
  content ... should still hash-cons to the same node; control_in is a per-use
  decoration." `schedule_data` (`Node.pm:33-39`) is excluded for the same reason.
- `Constant.pm:15-19`: Constant overrides content_hash to include `const_type`
  (values observed in `lib/`: `number`, `string`, `bool`, `regex`, `variable`,
  `identifier`). So a *lexical category* IS already in the hash.
- `NodeFactory.pm:251-265`: data nodes (incl. Constant, Add) are deduplicated by
  content_hash — identical content returns the SAME object (`make()` returns
  `$cache{$hash}`).

**Why this is a contradiction, not just an open question:**
The model says (§1) "a value at rest has exactly ONE representation." Under
hash-consing, "a value at rest" = "one shared node." So the model is asserting:
one shared node carries one representation. Now force the fork the spike flagged:

- **If representation is IN content_hash** (like `const_type`): then
  `Constant(1, repr=Int)` and `Constant(1, repr=Scalar)` are TWO DISTINCT nodes.
  This *preserves* "one node = one representation" — good — but it **breaks value
  identity**: the literal `1` is no longer one def. Any pass that assumes
  "same literal = same node" (CSE, the existing hash-cons dedup itself, and
  crucially the formal doc's observational-equivalence premise that `42` and the
  boxed `42` are *the same value*) now sees two unequal nodes for one Perl value.
  The model's own §1 wording ("there is no register that is secretly both") is
  satisfied, but at the cost of the SoN invariant that content equality = identity.
- **If representation is OUT of content_hash** (like `control_in`, a post
  -construction annotation): then ONE shared `Constant(1)` node carries ONE
  representation field. This preserves value identity — good — but it **fails the
  moment the same literal legitimately needs two representations in one program.**
  And it can: `my $x = 1 + 2.5;  my $s = "v" . 1;` — the literal `1` is wanted as
  `Int`/`i64` in the arithmetic context (well, `Num`/double after the `2.5`
  coercion) and as `Str` in the concat. Hash-consing collapses both `1`s to one
  node; a single representation field cannot serve both. The shared-node model
  then FAILS: it must either split the node (back to the IN case) or pick one
  representation and force a Coerce on the other edge.

**The likely-correct resolution (and why the doc must state it):**
The escape is: **representation is OUT of content_hash; the per-edge
representation needs are reconciled by Coerce nodes, NOT by the def's single
representation.** I.e. `Constant(1)` is ONE node with representation `Int`; the
`Str` consumer gets a `Coerce[Int->Str]` on its *edge*. This is internally
consistent with §2 (coercion lives on edges) and keeps value identity. It means
"a value has ONE representation" is true of the DEF only; CONSUMERS that need a
different representation get it via an explicit Coerce, exactly as §2 already
says for type. **This is almost certainly the intended model — but the doc never
says it, and §1's phrasing ("one representation," full stop) reads as if it
applies globally.** Open question #2 in the doc ("a new Coerce node, or an
annotation on edges") is the same hole wearing a different hat.

Note the subtlety that makes this non-trivial: `const_type` is ALREADY in the
hash (`Constant.pm:15`). So Constant is *already* split by lexical category
(`number` vs `string`). If representation tracks `const_type` 1:1 this looks
solved — but it does not, because `const_type=number` does not distinguish
`i64` from `double`, and the SAME `number` literal `1` can need `i64` in one
context and `double` (after promotion) in another. So even with `const_type` in
the hash, the two-representations-of-one-literal case survives. The doc must
pick: representation rides `const_type` (IN hash, accept value-identity split)
or rides an excluded edge-reconciled annotation (OUT of hash, like control_in).
**It cannot be silent, and §1 as written implies the OUT model while leaving
the failure case unaddressed.**

VERDICT on the central question: **representation must be OUT of content_hash
and treated like `control_in` — a per-use decoration — with cross
-representation needs resolved by Coerce nodes on edges, NOT by the def. The doc
asserts single-representation-per-def in language that does not make this
explicit, and does not address the same-literal-two-representations case at all.
This is a real hole and is closeable on paper today.**

### H2 — HIGH — Coercion placement is an unverifiable hand judgment with no enforceable invariant

§"What this contract demands of the parser" makes coercion-insertion the
producer's job and §"Validation plan" hands that job to the hand-author until
the parser exists. The doc states the *intended* invariant ("every operation's
operands already have the operation's required representation") but provides **no
checkable predicate** to enforce it. Consequences:

- The latent-vs-representation judgment (the hard part the formal doc spends 1200
  lines on) is moved into the hand-author's head, where it can be gotten wrong
  silently. A hand-authored graph that *omits* a needed `Coerce[Str->Num]` will
  still lower (to whatever the operand's representation happens to be) and may
  even pass the perl comparison for the chosen test input, while being wrong for
  a different input — a false green.
- There IS a natural enforceable invariant available and the doc should name it
  as a harness check: *for every operation node, assert each operand's
  representation == the operation's declared required representation; the only
  legal bridge is a Coerce node.* This is a cheap, total, local graph-validation
  pass. Without it, "correctly-typed graph" is defined but not checked, and the
  whole CodeGen-verified-first discipline rests on un-audited hand judgment.
- This interacts with H1: if representation is an edge/annotation reconciled by
  Coerce, the invariant is checkable; if representation is a single def field,
  the invariant is ambiguous (which consumer's requirement does the def satisfy?).

This is HIGH because the entire trust story ("hand-authored graphs ARE the spec")
is only as good as the spec's checkability, and right now it is not checkable.

### H3 — HIGH — Scalar fallback is a silent escape hatch with no coverage measure (false-green risk)

§4 and the plan's gap-map both lean on "can't pin a representation -> Scalar ->
libperl call." The doc explicitly says this "is not a failure ... NOT a bug." That
framing is the danger: **it makes falling back indistinguishable from giving up.**

- The plan (three-axis doc, Phase 3d localization matrix) treats "L cannot lower"
  as the gap signal. But under §4, a value going `Scalar` does NOT make L "unable
  to lower" — L *can* lower it, to a libperl call. So an LLVM corner that emits
  libperl calls for everything-hard will **report green** (lli runs it, output
  matches perl) while proving the IR is self-sufficient for *nothing*. The plan's
  own stated purpose — "a target that cannot link libperl cannot cheat" — is
  defeated the instant the LLVM lowering is *allowed* to emit libperl calls for
  Scalar values, which §4 explicitly permits.
- There is a latent contradiction between the two docs here: the plan says the
  LLVM target "carries NOTHING for free ... covers only what the IR can express
  runtime-free" and uses lli specifically because it "cannot link libperl." But
  the representation model's §4 fallback IS libperl calls. Either lli links
  libperl (then it CAN cheat, and §4 is the cheat) or it cannot (then §4's
  fallback is un-lowerable on the LLVM corner and "Scalar" means "gap," not
  "libperl call"). The docs must agree on which it is. As written they disagree.
- **There is no measure of "fraction of the program lowered runtime-free vs
  fell back to Scalar."** Without that metric, the gap-map cannot distinguish
  "legitimately dynamic -> Scalar" (fine) from "we gave up -> Scalar" (the thing
  the whole axis exists to surface). A required deliverable should be a
  per-idiom runtime-free-coverage number (e.g. % of value-defs with a non-Scalar
  representation, % of operations lowered to native ops vs libperl). Green
  without that number proves nothing.

HIGH because it can make the entire LLVM axis report success while measuring
nothing — the exact false-green the plan was designed to prevent.

### M1 — MED — Int=i64 ignores Perl's overflow-to-NV; "Int stays Int" is a guard the model names but does not model

The spike uses `i64` (`add.ll`: `add i64`). Perl IVs are platform-width and
**silently promote to NV (double) on overflow** — `2**62 + 2**62` becomes a
double in real perl. The plan's three-axis doc names this exact guard
("integer-stays-integer (no overflow-to-NV)") as an unboxing-validity predicate,
which is good. But the representation model (`typed-ir-representation.md`) does
NOT address it: §1 lists `i64` as a representation and the spike adds two `i64`s
with no overflow check. So:

- For the trivial constant-fold case (`1 + 2`) it is fine (3 fits i64, and a
  literal-fold proves nothing about runtime overflow).
- For ANY runtime `Int + Int` it is not fine without either (a) a static proof
  the result cannot overflow, or (b) an overflow-check that, on overflow, takes a
  `Coerce[Int->Num]` (i64->double) path. That is *another Coerce edge*, and it
  means faithful Perl-int `+` is NOT a clean `i64 add` — it leaks Perl semantics
  back into the "clean computation slice."
- This is the first place the "computation slice is clean" claim cracks. It is
  MED not HIGH only because the guard is already named in the plan and the
  resolution (overflow -> Coerce edge, or a proven-no-overflow guard) fits the
  model. But the representation doc should state it, because as written it implies
  `Int -> i64 add` is unconditionally safe, and it is not.

### M2 — MED — Coerce node hash-consing and DAG-safety are unspecified (and interact with H1)

The doc (open question #2) has not decided whether Coerce is a node or an edge
annotation, and says nothing about whether Coerce nodes are hash-consed.

- If Coerce IS a hash-consed data node (it would flow through
  `NodeFactory.make()` like any other, `NodeFactory.pm:251`), then two consumers
  needing the same `Coerce[Str->Num]($x)` share ONE Coerce node — SSA-clean,
  good. Its content_hash would be `Coerce|<x.id>` (+ from/to repr if those are
  in the hash — which loops back to H1). Inserting it adds a normal use-def edge
  via `_register_consumers` (`NodeFactory.pm:139-153`); no cycle risk for a
  forward data coercion (it consumes `$x`, produces a new value; consumers point
  at the Coerce, not back at `$x`). So the DAG is preserved for the simple case.
- The risk is the NON-simple case the doc has not considered: a Coerce inserted
  on a Phi input, or on a loop-carried value. `Phi.pm:14` hashes on
  `region + inputs`; `set_backedge` (`Phi.pm:18-23`) mutates an input after
  construction. If a Coerce is inserted between a Phi and its backedge value,
  the ordering of hash-consing vs backedge-wiring matters and is unspecified.
  This is where coercion insertion *could* interact badly with the existing
  mutable-Phi machinery. The doc should at least flag loop/Phi Coerce placement
  as out-of-scope-for-now rather than leave it silent.

MED: the common case is clean; the Phi/loop case is a real unanswered question
that will bite at the first loop-carried coerced value (well beyond `1+2`).

### M3 — MED — Bool, Undef, Ref representations are unaddressed; DualVar handling is only gestured at

The model addresses Int/Num/Str/Scalar and says DualVar -> Scalar (§4). But the
formal lattice has Bool, Undef, Ref (+ subtypes), List/Array/Hash, Code, Glob,
None. The representation doc is silent on all of these except by implication
("everything else -> Scalar"). That implication is probably fine for Bool/Undef
early (box them), but:

- `Undef` -> Scalar means even `my $x;` forces a boxed SV, which is fine but
  worth stating (it caps how much of a real program lowers runtime-free — see H3
  coverage measure).
- `Ref`/`ArrayRef`/`HashRef` -> "raw pointer or struct" (§1 lists `ptr`/`struct`)
  but the doc never maps the lattice's Ref subtypes onto `ptr`/`struct`. This is
  open-question-#1 territory and acknowledged ("decide as idioms force it"), so
  it is a documented deferral, not a hidden gap. Acceptable as deferred, but the
  DualVar claim deserves a sentence: DualVar -> Scalar is correct (formal doc
  Example 4 proves DualVar ∈ Scalar, ∉ Num, ∉ Str), and the model's §4 captures
  it correctly *as long as* the unboxing guard "not a dualvar" is checked before
  any value is given Int/Num representation. The model names that guard
  (§"unboxing guards ... not a dualvar") so this composes — but the composition
  is implicit and should be made explicit, because a DualVar that slips through
  to an `i64` representation is a miscompile, not a gap.

### L1 — LOW — `const_type` vocabulary does not match either lattice cleanly
`Constant.pm` uses `number` (not `Int`/`Num`), plus `bool`, `regex`, `variable`,
`identifier` — a lexical-category vocabulary, not the formal lattice's type
vocabulary and not the representation lattice's (`i64`/`double`/...). The model
will have to map `const_type=number` onto {Int|Num} x {i64|double}, and
`const_type` does not carry enough information to do it (no int-vs-float
distinction; `1` and `1.0` may both be `number`). Low severity (it is a parser
-side concern and the contract is defined backward from the target anyway), but
it means "the IR already has const_type so representation is half-done" would be
a false comfort — const_type is lexical, not representational.

### L2 — LOW — "subtyping IS the set of legal Coerce nodes" is elegant but under-specified for non-chain coercions
§3 maps `Int<:Num<:Str` to insertable Coerce nodes. Clean for the total order.
But the formal lattice is NOT a chain (Ref branch, List branch, DualVar off to
the side). "Subtyping = legal coercions" needs a story for coercions that are
NOT subtype-directed (e.g. `Num->Str` is down-cast-ish stringification; `Ref->Num`
is address-taking, lossy, and NOT a subtype relation at all yet Perl does it).
The model's §3 conflates "subtype edge" with "legal coercion," but Perl has legal
coercions that are not subtype edges (ref-to-number). Low because these all land
in Scalar/fallback early, but the doc's clean identification "subtyping = legal
coercions" is too strong as stated.

---

## ANSWERS TO THE SPECIFIC QUESTIONS

1. **Hash-consing vs representation** — answered definitively in H1. Representation
   MUST be out of content_hash (per-use decoration, like `control_in` at
   `Node.pm:29-31`), with cross-representation needs reconciled by Coerce nodes on
   edges. If put IN the hash (like `const_type`, `Constant.pm:15`), value identity
   breaks. The doc's §1 wording implies the OUT model but never says it and never
   addresses same-literal-two-representations — that is the hole to close.

2. **Coerce + SSA + hash-consing** — M2. If Coerce is a hash-consed data node,
   shared coercions correctly share one node (SSA-clean, no cycle for forward
   data coercions; `NodeFactory.pm:139-153` handles the use-def edge). The
   unanswered case is Coerce on Phi/backedge inputs (`Phi.pm:18-23` mutates
   inputs post-construction) — ordering of consing vs backedge-wiring is
   unspecified. Flag as out-of-scope until loops are in scope.

3. **Where Coerce nodes come from / trust boundary** — H2. For hand-authored
   graphs the human inserts them; this relocates the latent-vs-representation
   judgment into the author's head with NO checkable invariant. There IS a cheap
   enforceable one ("every operand's representation == the op's required
   representation; only Coerce bridges") and the harness should run it. Without
   it, correct coercion placement is an unverifiable hand judgment and a
   false-green vector.

4. **Scalar fallback as escape hatch** — H3. Real and serious. §4 permits the
   LLVM corner to emit libperl calls for Scalar, which directly contradicts the
   plan's "cannot link libperl, cannot cheat" rationale and lets the corner go
   green while proving nothing. A runtime-free-coverage measure (% defs with
   non-Scalar repr; % ops lowered native vs libperl) is REQUIRED, not optional,
   and the two docs must agree on whether lli may call libperl at all.

5. **Int=i64** — M1. The model does not handle overflow-to-NV. Faithful runtime
   `Int+Int` needs either a proven-no-overflow guard or an overflow->`Coerce[Int
   ->Num]` path — another Coerce edge — so the "clean computation slice" leaks
   Perl semantics. The plan names the guard; the representation doc must too.

6. **Model vs formal doc consistency** — Mostly composes (S3). DualVar->Scalar is
   correct (formal Example 4) IF the "not a dualvar" guard is checked before
   granting Int/Num repr (M3). Gaps: Bool/Undef/Ref representations unaddressed
   (deferred, acceptable); "subtyping = legal coercions" too strong for non
   -subtype coercions like Ref->Num (L2).

---

## HOLES TO CLOSE IN THE DOC BEFORE 3a (concrete)

1. **(H1, blocking)** State explicitly: representation is OUT of content_hash, a
   per-use decoration like `control_in`; the def carries one representation;
   consumers needing another get an explicit Coerce on their edge. Address the
   same-literal-two-representations case directly. Resolve open-question #2 the
   same way (Coerce is a node; representation is not in its identity hash, or is
   — pick one, with H1's reasoning).
2. **(H2, blocking)** Define the checkable invariant and commit the harness to
   running it: "for every operation node, each operand's representation equals the
   op's required representation; the only legal bridge is a Coerce node." Make
   "correctly-typed graph" a checked property, not a hand judgment.
3. **(H3, blocking)** Decide whether the LLVM corner may emit libperl calls at
   all. If yes, add a mandatory runtime-free-coverage metric per idiom so green
   cannot hide universal fallback. If no, redefine "Scalar value" on the L corner
   as "gap" (un-lowerable), aligning with the plan's no-libperl rationale. Make
   the two docs agree.
4. **(M1, before any runtime Int op)** State the overflow-to-NV guard in the
   representation doc: `Int->i64 add` is only safe under proven-no-overflow OR an
   overflow->Coerce(Int->Num) path.
5. **(M3, cheap)** One sentence each: DualVar->Scalar is gated on the "not a
   dualvar" guard (else miscompile); Bool/Undef->Scalar early; Ref-subtype repr
   deferred (already open-question #1).

None of these require code changes; all are doc decisions, and all are decidable
on paper now. The `1+2` spike is real but proves only the toolchain and the
trivial no-coercion/no-Scalar/no-variable/no-overflow case — it should not be
read as validating any of the above.
