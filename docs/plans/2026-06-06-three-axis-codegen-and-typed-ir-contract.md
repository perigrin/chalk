# Plan: Three-Axis CodeGen + Target-Driven Typed-IR Contract

**Date:** 2026-06-06
**Status:** DRAFT for review. Supersedes the "Phase 3 — C corner" framing in
`docs/plans/2026-06-05-codegen-harness-and-idiom-corpus.md` (Stage 3) and
`docs/plans/2026-06-05-codegen-harness-architecture.md` (C7 triangle as drawn).
The earlier framing treated the second backend as a *verification convenience*
(a C/XS corner to localize bugs). This reframe treats the backends as a
**forcing function on the IR itself**, and turns "Phase 3" from "verify the
codegen" into "establish whether the IR is a real compiler IR."

This is consciously a NEW DIRECTION, recorded as such per plan-discipline: the
project pivots here from "verify a Perl-to-Perl transpiler" toward "build a
standalone optimizing compiler." The harness (Phases 0–2, tier-1 green + curated
tier-2) is the validated foundation this builds on, not something it discards.

## The core reframe

Phases 0–2 verified one property of the IR: **expressiveness** — that the IR,
lowered back to Perl and run under perl, behaves like the source (perl is the
sole oracle). That corner leans entirely on Perl: the Perl emitter re-emits
Perl text, so the IR can remain an untyped soup of "Perl scalars" and Perl's
own runtime supplies all the semantics at execution time. We therefore have
**zero evidence** that the IR carries enough information to compile *without*
Perl's runtime — and that is precisely the property a real compiler needs.

A target that **cannot link libperl** cannot cheat. It forces the IR to either
carry the type / representation / lifetime information needed to lower
runtime-free, or fail loudly. **That failure is the signal.** And — the
load-bearing insight — *the information a runtime-free target forces into the IR
is the same information optimization needs.* "Can lower without a runtime" and
"can optimize beyond Perl's per-op runtime dispatch" are one requirement, not
two. So the standalone target is not a someday-nicety; it is the instrument that
produces, in one artifact, the **IR-completeness gap-map = the standalone-compiler
roadmap = the optimization-opportunity map.**

## The inversion: the IR is defined backward from the targets

We do NOT audit the current (parser-shaped, SemanticAction-produced, untrusted)
IR and design around it. We **decide how typed the IR must be** from the
targets' demands, and the parser's job becomes producing that contract. This is
the same CodeGen-verified-first discipline used throughout: hand-authored graphs
are how we *specify* the IR without waiting for the (paused, untrusted) parser.
A hand-authored typed graph that lowers to LLVM and matches perl IS the
executable specification of the typed IR; the parser must later learn to produce
graphs of that shape. "How typed is the IR today" measures only how much of the
contract the current producer happens to meet — it does not constrain what the
contract *should be*.

## The three CodeGen axes — each tests a DIFFERENT IR property

| Axis | Target | Property tested | Leans on Perl runtime? | Status |
|---|---|---|---|---|
| **Expressiveness** | IR → Perl | Can the IR represent the Perl subset at all? | Yes (re-emits Perl) | tier-1 GREEN, curated tier-2 GREEN |
| **Self-sufficiency** | IR → LLVM IR | Does the IR stand alone, runtime-free? (and: is it typed enough to optimize?) | No (the forcing function) | NEW — this plan |
| **Practicality** | IR → C/XS | Does it cover real interop / shipping use? | Yes (links libperl) | exists but parser-welded + stub `generate($mop)`; reframed below |

These are complementary, not redundant:
- **Perl** carries Perl semantics for free → keeps certifying the FULL corpus
  (strings, hashes, the `feature class` MOP, ADJUST, the tier-2 units) that a
  runtime-free target cannot yet touch. It remains the behavioral oracle-comparison.
- **LLVM** carries NOTHING for free → covers only what the IR can express
  runtime-free (initially the pure-computation slice: arithmetic, control flow,
  integer/numeric values). Its *narrowness is the point* — every idiom it
  cannot lower is a documented IR-underspecification finding.
- **C/XS** is the pragmatic shipping artifact: links libperl so it can cover the
  full corpus, but its laziness (SV* everywhere, runtime dispatch per op) is
  exactly what caps performance at "no faster than standard Perl" (see memory
  `xs_bootstrap_approach`, `xs_performance_investigation`). Once the LLVM axis
  forces real types into the IR, the C/XS backend can SPECIALIZE on them
  (proved-integer `+` → native add, not `Perl_pp_add` with SV unboxing),
  unblocking the "per-class XS + semiring intrinsics" performance goal that is
  currently blocked precisely because the IR lacks the type info to inline on.

## Why LLVM IR specifically (not C/XS, not native asm)

The standalone corner must: (a) execute directly so we still get a
perl-behavior comparison; (b) be low enough to expose representation gaps but
high enough that we are not hand-writing a register allocator; (c) be where a
real optimizing compiler wants to go.

- **LLVM IR** fits all three. `lli` (present at `/usr/lib/llvm-15/bin/lli`,
  LLVM 15 — verified) interprets it directly: no compile, no link, no XS. It is
  typed + SSA, so it *forces* representation decisions (the choke surfaces the
  underspecification). SoN is already an SSA-ish graph (hash-consed, use-def
  chains) — the impedance match to LLVM SSA is BETTER than to Perl source text,
  and it finally exercises the SoN-ness the IR was chosen for (the optimizer's
  IR; see memory `optimization_layer_plan`). It is also a *genuinely different*
  lowering than Perl-text emission, so a bug shared between "emit Perl text" and
  "emit LLVM SSA" is rare and therefore meaningful as an independent check.
- **Native asm (ARM/x86)** is strictly lower-leverage here: host is `x86_64`
  (verified) so ARM needs emulation; x86 asm forces the *same* representation
  questions as LLVM but adds register allocation + calling-convention noise that
  obscures the IR-completeness signal. Asm is a *later lowering of LLVM IR*, not
  a competing choice.
- **C/XS** drags in Perl-embedding complexity (XS, SV marshalling) orthogonal to
  "is the IR correct / self-sufficient." Kept as the practicality axis, not the
  forcing function.

## What "throw away the current C codegen" means (decided: yes, for the welded path)

The current C backend is welded to the untrusted parser:
`_generate_c_files($ir, $sa, $ctx)` (`Target/C.pm:1764`) requires the parser's
SemanticAction + Context and dies without `$ctx->mop()` (`C.pm:1852`); the
`generate($mop)` entry (`C.pm:1722`) is a comment-only STUB (no method bodies).
Un-welding it is reverse-engineering a tangle we do not trust. Per perigrin's
explicit direction (and the global rule requiring permission to rewrite):
**we do not invest in un-welding the existing C path.** The C/XS axis is rebuilt
from a clean free-standing-graph entry, and — critically — built to specialize
on the types the LLVM axis forces into the IR. The hard-won Perl-C-bridge
knowledge in the existing backend (XS wrappers, SV marshalling, chalk.so
architecture) is *reference material*, not code to preserve.

## The typed-IR contract has THREE axes (Q2 finding: latent type ≠ representation)

There is already a worked-out **latent type lattice for Perl** in the repo:
`docs/architecture/perl-type-system-formal.md` (a formal model with a soundness
argument) + `-practical.md`. Lattice: `Int <: Num <: Str <: Scalar`, plus
Ref/Object/ScalarRef/ArrayRef/HashRef/CodeRef, List/Array/Hash, Code, Glob,
Bool, Undef, DualVar, None. This is the type vocabulary for the contract — we do
not invent it. The existing `TypeInference` semiring already does (some of) this
axis at parse time.

BUT — the load-bearing Q2 finding — **that lattice is a LATENT-TYPE system, not
a REPRESENTATION system, and the LLVM contract needs both.** In the formalism, a
value is `Int` if it *survives numify/stringify round-trips and satisfies numeric
contracts* — i.e. `"42"` (a string SV) IS an `Int`, and `42` and `"42"` are
*observationally equivalent*. So "node is typed `Int`" means "this Perl scalar
behaves as an integer under coercion" — it is STILL an SV, still needs libperl to
be a value. That is a different, weaker claim than what LLVM needs: "this is an
`i64` in a register, no SV, no coercion machinery."

Therefore **even `1 + 2` is NOT trivially runtime-free**: `+` on two
`Int`-*typed SVs* still carries SV semantics (magic, overload, tie, the dualvar
possibility, integer-vs-float promotion/overflow). To license lowering to
`i64 add` you need an additional claim the latent lattice does not provide.

So the typed-IR contract is THREE axes:
1. **Latent type** — `Int/Num/Str/Ref/Object/...` from the formal lattice.
   *Have it (the formal docs + `TypeInference` semiring).*
2. **Representation** — boxed-SV vs unboxed (`i64` / `double` / raw pointer /
   struct). Lives ONLY in the late C-backend `StructPromotion` pass today; the
   contract needs it ON THE GRAPH.
3. **Unboxing-validity guards** — the predicates that license eliding the SV
   layer: no magic / no overload / no tie / not a dualvar / integer-stays-integer
   (no overflow-to-NV) / not aliased. NOTE: the formalism's *semantic contracts
   ALREADY name these* — NaN excluded from Num, DualVar ∉ Int/Num, tie/overload
   break operation contracts. The unboxing-blockers ARE the contract-violators.
   This is the same analysis a real optimizer does to use a native `add`.

This is GOOD news for scoping: axis 1 is pre-built and proven; the missing work
is axes 2+3, which is precisely the optimizer's unboxing analysis — a bounded,
well-understood design target, not open research. It also confirms the central
thesis: the LLVM-lowering requirement (axes 2+3) and the optimization requirement
are literally the same analysis.

## The typed-IR contract (the design act — drafted by the LLVM audit)

The LLVM axis's first deliverable is the **typed-IR contract**: for the smallest
computation idiom, decide what type / representation / lifetime annotations each
SoN node MUST carry to lower to LLVM IR runtime-free. This is a *design* act, not
an audit of the current IR. Each subsequent idiom either fits the contract or
forces a documented extension. The contract is drafted as **hand-authored typed
graphs** that lower to LLVM, run via `lli`, and match perl — the executable
specification.

Then (per the chosen "both, in sequence" approach) the current SoN graph +
TypeInference/TypeInferenceActions/StructPromotion are MEASURED against the
contract, organized by the contract's demands (not the existing node taxonomy),
producing the honest baseline: for each contract requirement, does the IR have
it / partially / not at all. Today: type inference exists at parse-time
(`TypeInference`) and representation is decided LATE in the C-backend
`StructPromotion` pass — so the measurement will likely show "types are inferred
but not carried on the graph in a target-ready form," which would make
"plumb representation onto the SoN nodes" finding #1 (and the highest-leverage
work in the project: it unlocks standalone + optimization + fast-XS at once).

## Phases (reshaped Stage 3)

### Phase 3a — Typed-IR contract + LLVM lowering spike (the design act)
- Draft the typed-IR contract for the smallest computation idiom (e.g.
  integer `return 1 + 2`, or an integer-arg arithmetic method).
- Hand-author the typed SoN graph for it. Build a minimal SoN→LLVM-IR lowering.
  Run via `lli`. Compare behavior to perl (S). Green = contract sufficient for
  that idiom.
- DELIVERABLE: the contract (what each node must carry) + a working
  one-idiom SoN→LLVM→lli→perl loop. This is the de-risk (like the D1 / Add spikes).

### Phase 3b — IR-completeness gap-map (contract → measure → corpus)
- Extend the LLVM lowering across the computation slice of the corpus
  (A decls / C assigns / D control / K incr / L logical / arithmetic).
- Every idiom the LLVM path CANNOT lower runtime-free = a documented
  IR-underspecification finding (type missing, representation undecided,
  lifetime unclear). Organize as a gap-map exactly like Phase 1's.
- MEASURE the current IR (TypeInference + StructPromotion) against the contract:
  the honest baseline of how far the current IR is from the contract.
- DELIVERABLE: the IR-completeness gap-map = standalone-compiler roadmap =
  optimization roadmap (one artifact).

### Phase 3c — plumb the contract into the IR (target-driven typing)
- Work the gap-map: add the type/representation/lifetime information the
  contract demands onto the SoN node model (so it is carried on the graph, not
  inferred late). This is the parser's eventual output contract.
- Re-lower to LLVM; drive the computation slice to green (LLVM-output == perl).

### Phase 3d — the L corner becomes a verification corner (three corners: S/P/L)
- The triangle is S (perl, oracle) + P (Perl-codegen, full corpus) + **L
  (LLVM-via-lli, computation slice)**. **L REPLACES C as the second corner** —
  C/XS does NOT join until a typed, verifiable IR exists (3c). Rationale: there
  is no coherent C corner to run before 3c anyway (today's C path is welded +
  stub, and a rebuilt C backend only earns its keep when it can specialize on
  types that do not yet exist). L is precisely the forcing function that
  produces those types, so the ordering is forced, not arbitrary.
- The localization matrix with S/P/L:
  - `P = L ≠ S` → **the IR/graph is wrong** (both lowerings agree, both diverge
    from perl → upstream). This is the third-trusted-leg payoff — obtained
    WITHOUT C.
  - `P ≠ L` → one codegen is wrong; early on almost always "L is incomplete here"
    (L is the directional one). Low-confidence until L's coverage is real —
    trust no single corner at the outset.
  - `L cannot lower where P passes` → **the IR is underspecified for standalone**
    — the gap-map signal; the entire reason L exists.
  So L gives BOTH the IR-correctness localization (`P=L≠S`) AND the
  IR-completeness gap (`L can't lower`) — the two things we want — without
  libperl. Enforce F7 (all corners consume the IDENTICAL graph object — refaddr
  identity).

### Phase 3e (LATER) — C/XS rejoins as the 4th corner, rebuilt + type-specialized
- ONLY once 3c has plumbed types into the IR and L has verified them. Rebuild
  C/XS from a clean free-standing-graph entry that SPECIALIZES on the IR's types
  (proved-integer `+` → native add, not `Perl_pp_add` with SV unboxing), not
  SV* everywhere. This is where the "per-class XS + semiring intrinsics"
  performance goal (memory `xs_bootstrap_approach`) finally unblocks — it was
  blocked precisely because the IR lacked types to specialize on. C/XS is
  deferred not because it is hard but because there is nothing for it to
  specialize on until 3c.

### Phase 4 — B::SoN as the trusted IR/MOP producer (the IR-generation layer)
- The capstone needs an IR-PRODUCER for real lib/ input. It is NOT the chalk
  parser/SemanticAction (untrusted, paused). It is **B::SoN** (`perl -MO=SoN`,
  repo `~/dev/perl5-son`): walk the REAL perl optree → our robust IR/MOP. Reading
  what perl actually compiled (not a re-parse) is the right shape for a trusted
  front end. This is the long-deferred "how does the front end hook to the IR"
  answer — by REPLACING SemanticAction with the optree, not repairing it.
- **Current B::SoN is DIRECTIONAL, not complete/correct** — treated exactly as
  CodeGen was at the start: a sketch of the right shape, output SUSPECT until
  proven, not trusted. It is known-partial (drops field writes, no MOP emission,
  FromOptree bugs). It EARNS trust by being verified THROUGH the now-trusted
  (Phase-3) harness: B::SoN IR → verified CodeGen → run → compare to perl; a
  divergence is a B::SoN bug, never trusted around.
- **Scope DEFERRED until Phase 3 lands** (the typed-IR contract must be concrete
  first); the B::SoN phase shape is decided then. Verification logic only works
  AFTER Phase 3 makes CodeGen trusted.

### Phase 5 — CAPSTONE: run lib/ through B::SoN → CodeGen, confirm == perl
- The OLD framing ("self-host the Earley parser via the harness") was MIS-WIRED:
  it silently assumed an IR-producer that did not trustworthily exist. Corrected
  chain: source → B::SoN (Phase 4) → CodeGen (Phase 3) → run → compare to perl.
  Well-posed only once BOTH layers exist — hence Phase 5, blocked by Phase 4.
- The composition of two independently-verified layers applied to the hardest,
  largest real workload (lib/, ultimately the Earley parser). A green capstone
  certifies the whole optree→IR→CodeGen path is sound on real complex code — not
  merely that a transpiler round-trips.

## Acceptance criteria (staged)
- **3a:** typed-IR contract drafted; ONE computation idiom lowers SoN→LLVM IR,
  runs via `lli`, behavior matches perl. Hand-authored typed graph = the spec.
- **3b:** computation-slice IR-completeness gap-map exists (per-idiom: lowers /
  underspecified-why); current-IR baseline measured against the contract.
- **3c:** the contract's type/representation info is carried on the SoN graph;
  computation slice is LLVM-green (lli-output == perl).
- **3d:** three-corner comparator (S/P/L) with F7; `P=L≠S` localizes to IR;
  `L can't lower` produces the underspecification gap. (Perl axis stays
  full-corpus oracle; C is NOT a corner yet.)
- **3e (later):** C/XS rejoins as 4th corner, rebuilt to specialize on IR types
  (post-3c only).
- **Phase 4 (B::SoN, scope deferred till Phase 3 lands):** B::SoN produces IR/MOP
  from the optree that passes the well-typed-graph invariant and lowers via the
  verified CodeGen to behavior matching perl (the directional producer verified
  through the trusted instrument; MOP-emission gap closed).
- **Phase 5 (capstone):** representative lib/ units lower B::SoN → CodeGen to
  behavior matching perl; ultimately the Earley parser parses like the original.
  perl is the sole oracle throughout.

## Invariants preserved from the harness plan
- perl remains the SOLE behavioral oracle (S). LLVM/C outputs are compared to
  perl, never to each other as ground truth, never to Chalk's own prior output.
- CodeGen-verified-first / target-driven IR: the IR contract is defined from the
  backend demands; the parser comes to meet it. Hand-authored graphs specify it.
- Gap-map-first, directional: red = work-list; a MISCOMPILE (emitted-but-wrong)
  is a correctness alarm, never backlog. For LLVM, "cannot lower runtime-free" is
  a GAP (IR underspecified); "lowered but wrong behavior" is a MISCOMPILE.
- Out of scope here: SemanticAction rewrite (still paused), B::SoN integration
  (later), parser-to-IR bridge (becomes well-posed once the contract is set).

## Open questions for review
1. ~~Four-corner vs LLVM-replaces-C?~~ **RESOLVED (perigrin): LLVM REPLACES C as
   the second corner until a typed, verifiable IR exists (3c). Corners are S/P/L;
   C rejoins as a 4th corner in 3e, post-3c, rebuilt to specialize on types.**
2. ~~Computation-slice scope — does `1+2` drag in SV semantics?~~ **RESOLVED: YES,
   it does.** The existing `perl-type-system-formal.md` lattice is LATENT-TYPE,
   not representation — `Int`-typed still means "an SV that behaves as int." The
   contract needs two MORE axes (representation + unboxing guards) on top of the
   latent type before ANY idiom is runtime-free. Axis 1 is pre-built; axes 2+3
   are the optimizer's unboxing analysis. See "three axes" section above. Open
   sub-question that remains: what is the SMALLEST guarded slice (literal-int
   arithmetic with no variables/SVs at all, e.g. `return 1 + 2`) where axes 2+3
   are trivially provable — that is the true 3a starting idiom.
3. Phase 3c contract size: **likely needs its own representation-type design doc**
   (the latent-type lattice is done in `perl-type-system-formal.md`; the
   representation + unboxing-guard layer is NEW and is the real design work).
   It is a SMALL lattice (boxed-SV / i64 / double / ptr / struct) but the GUARDS
   are the substance. Draft it as part of 3a's contract act, validated by the
   one-idiom lowering.
4. Sequencing vs tier-3 / capstone: this reshaped Phase 3 is foundational and
   large. Do tier-3 (broaden the Perl-axis corpus) and the capstone wait behind
   it, or proceed in parallel on the Perl axis while 3a/3b/3c build the LLVM axis?
