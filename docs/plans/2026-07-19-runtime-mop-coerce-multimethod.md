# Runtime MOP as inlined IR: `coerce` as a multimethod over the type lattice

**Status:** DESIGN NOTE (2026-07-19). Captures a multi-session architecture
discussion. No code yet. Grounds itself in
`docs/architecture/perl-type-system-formal.md` and
`docs/architecture/perl-type-system-practical.md`.

## ASSESSMENT #2 (2026-07-19, independent Fable review, empty context, HIGH effort)

The SECOND review (after all corrections + the NEW type-derivation thread) found:
**pilot CORE sound; the type-DERIVATION thread NOT sound as written.** All fixes
applied (see [ASSESS-CORRECTED] / [DEMOTED] markers). Findings:
- BLOCKER F1: "subtype edges DERIVE from operation-compatibility (Liskov)" is a
  FALSE EQUIVALENCE with round-trip membership — Str-ops work SILENTLY on a Ref
  (would admit Ref<:Str, which the lattice REJECTS); `"hello"+1` WARNS+returns 1
  (doesn't "fail"). The derivation thread is DEMOTED to a DIAGNOSTIC (banner added
  at the CONSEQUENCE paragraph).
- BLOCKER F2 [REVISED — perigrin: I blamed the wrong artifact]: scalar()-identity and
  the lattice DISAGREE on Glob, and the LATTICE is probably wrong — a glob VALUE
  passes the formal doc's Scalar membership, so `Glob(value) <: Scalar` (the tree's
  disjoint-sibling placement is the error). F2 partially survives only because `*foo`
  is TWO types (glob VALUE <: Scalar vs glob SLOT = symbol-table entry), which the
  lattice conflates, so "Scalar derivable COMPLETELY from scalar()" still overclaims.
  Glob value/slot conflation added as a known-incomplete-lattice gap.
- F3/F4/F5/F7/F8 stale survivors PATCHED: "no true Level-0" -> small permanent floor
  (both quote-sites); "multimethod on the LCA Scalar" -> the VTABLE MECHANISM (LCA is
  Any not Scalar); chr-mandates-Int -> use index/bitwise instead (chr's from-type is
  CodePoint); "0 Concat hits" was FALSE (Concat IS lowered, Context.pm:415); "chr/pack
  diverge at 128" was FALSE (diverge at 256; pack("C") silently wraps — same
  loss-class chr was disqualified for, so the pack rationale is BYTE-semantics not
  loss-freeness).
- F10/F11 pilot gaps NAMED in the sequence: prove the inliner on a LOOP+EFFECT
  callee first (never exercised); ByteBuf tier split (TYPE is SoNGraph-tier, its
  PRIMITIVE OPS are the intrinsic floor).
- **NEW MECHANISM (perigrin, folded in): `coerce` is a VTABLE LOOKUP returning a
  coderef — `Type->coerce(From,To)->($value)` — NOT a derived multimethod. This
  DISSOLVES F1 (coercions are POPULATED entries, not DERIVED edges).**
Verdict: sound basis for building the PILOT (after F10/F11 named); NOT a basis for
"lattice-generation machinery" (the derivation thread is a diagnostic only).

## ASSESSMENT #3 (2026-07-19, independent Fable review, empty context, medium effort)

The THIRD review (after the vtable mechanism + Liskov/Glob corrections) confirmed
the CORE sound and found the pilot sequence still TWO STEPS SHORT of buildable, one
new live wrong-answer, and two overclaims. All fixes applied ([ASSESS3] markers):
- **BLOCKER-adjacent G1 (companion doc 90/10 split NOT defensible):** the companion's
  "10% backend, mostly ALREADY DONE" leans on "F5/F8 inlining already handles
  top-level sub calls," but (a) `_lower_call_direct` INLINES ONLY (no `define`+`call`;
  the callee's own comment says real call emission is unbuilt — F3), (b) it lowers
  only a SINGLE-Return value subgraph and DROPS effectful callee bodies (the
  default-pure effect-drop class), and (c) THIS doc itself (FULL PILOT SEQUENCE) calls
  that same machinery "the pilot's biggest UNPROVEN mechanism." For the protocol's
  actual targets (lex.t/subval.t = files that DEFINE subs the program CALLS),
  inter-graph calls are a THIRD unbudgeted line item, not a rounding error. Companion
  doc corrected; "already handles this"/"already emits referenced sub graphs" deleted.
- **G2 (live wrong-answer, 5th+6th coercion site):** consolidation named FOUR sites;
  there are SIX. `_lower_print` Int arm (Context.pm:5648, printf `%d` of a TRUNCATED
  i32) and the Int return epilogue (LLVM.pm:1291, `trunc i64 -> i32`) are int->str
  renderers that DIVERGE from `_emit_int_to_str` TODAY: `print 4294967296` -> "0" but
  `"$n"` -> "4294967296" (measured; real perl prints 4294967296). The behavior oracle
  uses small ints so the gate can't catch it. Added to the step-1 list with the
  i32-truncation bug named.
- **G3 (missing pilot step — cross-compilation snippet availability):** step-3's
  inliner resolves callees against the LOADED GRAPH SET of ONE payload
  (`_resolve_direct_calls`, JSON.pm:570); nothing persists a compiled metaclass-method
  graph ACROSS compilations. The vtable cell for gen-1 needs a snippet-library /
  preload (Graal has exactly this). Added as a new step between 3 and 4.
- **G4 (stage-1 syntax unparseable by gen-0):** `sub Str (Int $v){}` is a MEASURED
  compile error in gen-0 perl 5.42 ("signature parameter must start with $/@/%").
  Added: pick the registration mechanism (explicit populate call), typed-sig syntax is
  a separate deferrable feature.
- **G5 (closure rhetoric overclaims):** "the metacircle is closed over the COMPILER
  ITSELF" contradicts this doc's OWN [ASSESS] demotion (coerce(OPTree,SoNGraph) NOT
  liftable; the two frontends never reconcile). Reifying OPTree as a Type Object closes
  the DESCRIPTION, not the IMPLEMENTATION. Corrected to DESCRIPTIVE closure; impl
  closure runs through the Earley frontend, B::SoN a permanently-foreign gen-0 cell.
  TERMINATION is unaffected (external gen-0 + floor is the standard argument).
- **G6 (GVN criterion claims a status-quo differentiator):** two `Stringify(Int)` of
  one value ALREADY GVN to one node today (hash-consed IR + id-keyed lowering cache).
  The REAL win is CROSS-SITE (a Stringify use and an eq-operand stringification of the
  same value merging into one Coerce node — those call `_emit_int_to_str` directly, no
  node). Restated criterion (c); pinned the body-splice to LOWERING time so the pure
  merge survives.
- **G7 (I/O absent from the floor):** the floor hypothesis lists arithmetic/memory/
  control but the doc's OWN motivating walls include file I/O (mod.t) and `print`/
  strtod are libc host-calls (not composable from the floor). Added a host-interface/IO
  intrinsic category.
- **G8 (demotion is a banner, not an edit):** two retained sentences still assert the
  refuted claims verbatim ("`"hello"+1` fails"; "Liskov, which the membership test
  operationally IS"). Edited in place.
- Verified-accurate (no finding): all six primary lib/ code citations
  (`_emit_int_to_str`/`_lower_coerce`/`_str_compare_operand`/`_coerce_ref_to_num`/
  `_lower_concat`/`_lower_call_direct`), `%_REPR_RANK`, RightShift/BitAnd-typed-Int;
  formal.md Lemma 2 supports `Int<:Num<:Str<:Scalar`; the byte-identical/GVN gate
  contradiction was genuinely fixed (behavior-identical at all four sites); the
  companion's PRODUCER claims (walks `\%main::` only, the wrap rewrite, Return-rooted
  `lower`) are all accurate.
Verdict: CORE sound to build the pilot on; add G3+G4 steps to make the sequence
buildable; the bare-file 90/10 split is wrong (inter-graph calls are a third line
item).

## ASSESSMENT #1 (2026-07-19, independent Fable review, empty context, medium effort)

An adversarial review (validated every codebase claim against source) found the
ARCHITECTURE sound and its codebase claims accurate, but the PILOT section
unsound. Corrections applied below; the review's verdict + the two BLOCKERs:

- **BLOCKER (pilot gate is self-contradictory):** "byte-identical to
  `_emit_int_to_str`" (the stage-2 gate) CANNOT coexist with "two `Stringify(Int)`
  GVN to one" (a success criterion) — GVN merging two renderers into one CHANGES
  the output. And byte-identity is unachievable anyway: today's `_emit_int_to_str`
  is a TEXTUAL emitter with fresh-counter SSA names / `s2i.loop.N` labels
  interleaved into the consumer's block; a graph-inlined+scheduled subset method
  produces different SSA naming/block order. FIX: the gate is BEHAVIOR-IDENTICAL
  (stdout/exit vs the corpus `behavior` blocks), NOT byte-identical, PLUS a planned
  IR-contract rewrite.
- **BLOCKER (hidden subset-vocabulary prerequisite):** the claim
  "`_emit_int_to_str`'s body IS expressible in the subset / Level-0 is already
  implemented, nothing new to build" is FALSE today. The renderer does `store i8`
  (byte writes) + `add i8 $ch,48` (char production); the SUBSET has NO construct
  that lowers to a byte-write or `chr` (verified: no chr/lvalue-substr in the
  corpus or Context.pm). So the pilot needs NEW gen-0 backend surface (a
  byte-buffer/`chr` primitive) — a SECOND chicken-and-egg the doc had not
  addressed (only the Int-metaclass one, via staged bootstrap). The pilot is NOT
  minimum-risk without this prereq named.
- IMPORTANT corrections applied: (1) Level-0 has TWO incompatible definitions
  ("no true Level-0 / state" vs "irreducible substrate") — reconciled below to "a
  small PERMANENT intrinsic base (the backend's primitive lowering) + liftable
  everything-else"; (2) the oracle S9-S12 ir-blocks are INVALIDATED by the
  Stringify-node deletion the pilot proposes (corpus dual contract) — oracle
  scoped to BEHAVIOR blocks + a planned ir-block rewrite; (3) a FOURTH scattered
  coercion site exists — `_coerce_ref_to_num` (Context.pm:1627), the exact
  fast/slow divergence the Graal critique warns of — added to the consolidation;
  (4) "B::SoN is DESTINED TO BE LIFTED like _emit_int_to_str" OVERCLAIMS —
  `OPTree` is libperl's C struct reachable only via the B XS layer; subset code
  has no FFI/C-struct reflection to walk it. The naming (`coerce(OPTree,SoNGraph)`)
  stands; the "same lift" is DEMOTED to a naming claim. Also: Chalk's real
  self-hosting frontend (Earley) goes SourceText->SoN DIRECTLY, bypassing OPTree —
  the two frontends were never reconciled.
- VERDICT: "The architecture stands on verified ground. What blocks building is
  the pilot." All codebase claims checked out EXCEPT the 4th-site enumeration miss.
  Metacircularity/termination argument sound in substance (standard staged
  bootstrap). Minor: round-trip membership is DUAL (syntactic + behavioral) in
  formal.md, not just syntactic; stale "off-chain = residual" phrase at the
  open/closed-lattice paragraph; INT64_MIN overflow edge (Context.pm:954) also
  inherited by any lift. See inline `[ASSESS]` markers.

## Problem this reframes

The B::SoN file-drain work keeps bottoming out in *runtime* capabilities, not
codegen rules: num.t needs float->string formatting; mod.t test 8 needs file
I/O; regex files need a matcher. The naive fix is a linked C runtime library
(`chalk_rt`) that codegen calls. This note argues for a different architecture
that is more native to Chalk (Sea of Nodes + self-hosting + a MOP) and produces
*more efficient* output than a linked runtime.

## The core claim

**The runtime is not a library. It is the MOP's own metaclass methods, written
in the Perl subset, compiled to Chalk IR, and INLINED as IR subgraphs into
programs BEFORE the optimizer runs — so the metalayer dissolves into the Sea of
Nodes and is optimized away wherever types are statically known.**

This is how real Sea-of-Nodes compilers handle their metalayer:

- **HotSpot C2** (origin of Sea of Nodes): "the runtime is not a callee, it's a
  node type." Hot ops (`String.equals`, `arraycopy`) are *intrinsified* — a
  hand-built IR subgraph spliced into the caller. Allocation is a high-level
  `AllocateNode` *macro-expanded late* into a subgraph, so escape analysis can
  DELETE it (scalar replacement) — impossible across a `call malloc` boundary.
- **Graal** made this first-class: **snippets** — pieces of the runtime written
  in the source language, compiled to IR, inlined at *lowering* time. Graal
  lowers in tiers (high = abstract `LoadFieldNode`/`InstanceOfNode`; mid/low =
  each abstract node replaced by its snippet IR), and re-optimizes AFTER
  inlining so the snippet's null-checks/loads fold and share with the program.
- **V8/TurboFan**: speculative lowering — inline a *specialized*, guarded
  subgraph based on type feedback, then optimize it in the Sea.

**Why inlining-as-IR beats a linked runtime (Sea-of-Nodes mechanics):** a `call`
node is an optimization barrier — unknown effects kill the memory/effect state
(loads can't move, stores can't be eliminated around it), it's opaque to
constant-folding/GVN/DCE, and it blocks escape analysis. Inlining the metalayer
as IR unlocks all of these *for the metalayer ops*: a `Coerce(Str->Num)` of a
constant folds; two `Stringify(Int)` of the same value GVN to one (hash-consing,
FREE in Chalk); an unused coercion DCEs; a known-range int specializes its
renderer.

**Chalk is already ~2/3 of a Graal-style system:** Sea-of-Nodes IR, hash-consing,
use-def chains, `Coerce`/`Stringify` already as NODES, a MOP metalayer, and type
inference that resolves most meta-ops away. if.t/cond.t/elsif.t already compile
to tight code with nothing linked BECAUSE they have zero residual meta-ops. That
is the Graal model working, unnamed. What is missing is the deliberate
**snippet-lowering tier**.

## The improvement on Graal/C2: self-hosted snippets

Graal snippets and C2 intrinsics are HAND-WRITTEN in a special dialect and are a
known correctness pain: the fast inlined path can DIVERGE from the slow library
implementation of the same method (two implementations, bug-for-bug sync).

**Chalk's self-hosting removes this.** A metaclass method (e.g. `Int` coerced to
`Str`) is written ONCE in the subset. Chalk compiles it to IR through the normal
pipeline. That single artifact IS:
- the DEFINITION of the operation,
- the INLINED snippet (spliced into callers via the existing direct-call
  inlining — `_lower_call_direct` + the F5/F6/F8 arg-binding),
- the LINKED routine (compiled once, CALLED for residual/too-big cases).

Inline-vs-call becomes a pure codegen policy (size/benefit), not two hand-synced
implementations. And the runtime inherits every backend: compile the SAME method
through LLVM for a native routine, through XS/C for the XS one (whose body can
just delegate to libperl — the per-target "pick your runtime" point). This is
self-hosting AT THE RUNTIME LAYER: the runtime is Chalk-compiled Chalk code.

## `Stringify` and `Coerce` unify into ONE multimethod: `coerce`

`Stringify(Int)` is not a special node — it is `coerce(Int, Str, value)`. The
current node zoo collapses:

| current node / site | is really | gen-0 form (TODAY) |
|---|---|---|
| `Stringify(Int)` | `coerce(Int, Str, v)` | `_emit_int_to_str` |
| `Coerce(Str->Num)` (strtod) | `coerce(Str, Num, v)` | `chalk_str_to_num` |
| `Coerce(Int->Num)` (sitofp) | `coerce(Int, Num, v)` | `_lower_coerce` arm |
| `Coerce(Bool->Str)` (select) | `coerce(Bool, Str, v)` | `_lower_coerce` arm |
| int-in-`eq` (`_str_compare_operand`) | `coerce(Int, Str, v)` + compare | `_str_compare_operand` |

**CRITICAL (do not lose this): `_emit_int_to_str` and `chalk_str_to_num` ARE
`coerce` methods — they are the runtime's coerce generic function, ALREADY
IMPLEMENTED, just in gen-0 form (hand-emitted Perl) and SCATTERED across the sites
above instead of unified.** `_emit_int_to_str` = `coerce(Int,Str)`;
`chalk_str_to_num` = `coerce(Str,Num)`; each `_lower_coerce` arm = a `coerce(A,B)`.
They are not "helpers near the runtime" — they are the runtime, unrecognized as
such. The pilot is therefore NAMING WHAT ALREADY EXISTS (unify + lift into
self-compiled subset methods), not adding a new thing.

Coercion is inherently BINARY in its type signature — the implementation depends
on BOTH the from-type and the to-type — so it is a **multimethod** dispatched on
`(From, To)`, not a method owned by either side. Perl-the-language has no
multimethods, but **the MOP is not Perl** — the metalayer is allowed a richer
dispatch model than the language it implements (as CLOS's MOP uses generic
functions to implement a language). Users still write single-dispatch Perl.

**MECHANISM — coerce is a VTABLE LOOKUP returning a coderef (perigrin 2026-07-19;
this REPLACES the earlier "multimethod lives on the LCA Scalar" framing, which the
assessment flagged stale — the LCA of the types coerce ranges over is `Any`, not
Scalar, since coerce also spans List/Ref/representation types):**
```perl
# Type->coerce(From, To) is a VTABLE LOOKUP on the TWO type params, returning a
# CODEREF that maps a From-value to a To-value:
Type->coerce($from, $to)   # -> sub To (From $v) { ... }   (a compiled coercion fn)

# coerce(From, To, value) is then trivially:
sub coerce($from, $to, $value) { Type->coerce($from, $to)->($value) }
```
So `coerce` is a 2-D VTABLE keyed by `(From, To)`, each cell holding a coderef (or
EMPTY -> GAP). **The coercions are ENTRIES you POPULATE, not edges you DERIVE** —
this is what dissolves the "derive edges from operation-compatibility" unsoundness
(see the DERIVATION-THREAD DEMOTION note below): the vtable IS the coercion
relation, populated explicitly; nothing claims it derives from operations. `Type->
coerce` IS multiple dispatch done right (lookup `(From,To)` -> the method reified as
a coderef). The `sub To (From $v)` signature (a type-annotation syntax perigrin has
experimented with — a function NAMED BY its return type taking a TYPED arg) states
exactly a coercion's type: `From -> To`.

Two payoffs of the CURRIED form `Type->coerce(From,To)` (returns the coderef ONCE):
- MEMOIZATION is natural: a hot loop coercing many Ints looks up ONCE, calls N
  times. `coerce($f,$t,$v)` re-looks-up each call; the curried form doesn't.
- STATIC RESOLUTION = compile-time lookup + inline: when `(From,To)` is known at
  compile time (the resolved case), the compiler does the vtable lookup AT COMPILE
  TIME and inlines the coderef's IR — this IS the Graal-snippet inlining, now with a
  clean mechanism (static (From,To) -> compile-time lookup -> splice the coderef).
The vtable is the STABLE INTERFACE; the coderef in each cell is what the pilot LIFTS
(gen-0: the cell for (Int,Str) holds `_emit_int_to_str`; gen-1: a self-compiled
`sub Str (Int $v){...}` — stage-2 SWAPS the vtable ENTRY).

Resolution over the type lattice (most-specific / MRO over a tuple, Chalk already
MRO-walks single `:isa` in `_stamp_method_call_reprs`) is a REFINEMENT of the flat
vtable: a general cell (e.g. `(Scalar, Str)`) provides fallback, specific cells
(`(Int, Str)`) override — so you populate the pairs that need special handling, not
N^2. (The lattice provides fallback ORDERING for lookup; it does NOT DERIVE the
entries.)

**Ambiguity rule (two regimes):**
- CLOSED primitive lattice (`Int<:Num<:Str`, the ~20 known coercion pairs, both
  types compile-time-known): define specific methods for every pair; no
  ambiguity possible; all resolve at compile time -> inline -> optimize away.
- OPEN lattice (user overload — an open method set, NOT "off-chain"; [ASSESS]
  residual is driven by static-pair-knowledge, not on/off-chain, see below): needs
  a defined precedence rule (CLOS-style leftmost-arg-dominates, or Julia-style
  ambiguity-is-an-error). This is the residual runtime MOP; scoped out for now.

## `coerce` SPANS REPRESENTATION TYPES TOO — the compiler passes ARE coercions

(perigrin) `coerce` does NOT range only over the primitive VALUE lattice. It ranges
over the WHOLE MOP type lattice — which, in a self-hosting MOP, includes the
COMPILER'S OWN types. If `OPTree` and `SoNGraph` are user-defined types in the same
MOP (they will be, once the metalayer describes the compiler's own structures),
then `coerce(OPTree, SoNGraph, $main_root) -> the __PROGRAM__ graph` is LITERALLY
the same operation as `coerce(Int, Str, $v)`: value of type A -> value of type B,
dispatched on `(A, B)`. "Translation/compilation" is NOT a different category from
"value coercion" — that distinction was a C-compiler assumption (compiler internals
live outside the language) that a self-hosting MOP rejects. `OPTree` and `SoNGraph`
have NO subtype relation (like `Ref`/`Str`) — but per the membership-vs-validity
split above, that just means the coercion doesn't PROVE membership; it is a valid
coercion.

**The whole pipeline becomes uniform — every pass is a coercion:**
```
coerce(SourceText, OPTree,   $file)      -> optree      (perl's parser)
coerce(OPTree,     SoNGraph, $main_root) -> __PROGRAM__ (B::SoN)
coerce(SoNGraph,   LLVMIR,   $program)   -> the .ll     (Target::LLVM->lower)
coerce(SoNGraph,   XSCode,   $program)   -> the .xs/.c  (Target::C)
```
`Target::LLVM->lower` IS `coerce(SoNGraph, LLVMIR)`. Per-target backend dispatch
(`if LLVM .. elsif C ..`) becomes MULTIMETHOD RESOLUTION ON THE TARGET REPR TYPE —
unifying "pick your backend/runtime" with the coerce multimethod. (Futamura /
nanopass: a compiler is a sequence of type-directed transformations — here through
the MOP instead of hardcoded.)

**Same metacircularity + bootstrap, one level up. `B::SoN` IS gen-0's
`coerce(OPTree, SoNGraph)`** — exactly as `_emit_int_to_str` is gen-0's
`coerce(Int, Str)`, in the sense that both are hand-written gen-0 implementations
of a coercion. So the COMPILER PASSES and the RUNTIME value coercions are the SAME
KIND of thing (a coercion), bootstrapped from an external gen-0.

**[ASSESS] But the "same LIFT applies to the whole compiler" claim OVERCLAIMS —
DEMOTED to a NAMING claim.** `coerce(Int,Str)` can be lifted (its FROM-type `Int`
is Chalk-native). `coerce(OPTree,SoNGraph)` CANNOT be lifted the same way: `OPTree`
is LIBPERL'S C STRUCT, reachable only through the B XS layer (perl5-son's producer
is interpreted Perl walking B). A self-compiled subset `coerce(OPTree,SoNGraph)`
would need the subset to traverse foreign C structures (`op_next`, SV internals) —
a capability with NO design (no FFI, no C-struct reflection in the MOP). "Reflect
only as much structure as needed" does not answer HOW subset code reads an OP. So
`B::SoN` is renamed to `coerce(OPTree,SoNGraph)` (the naming/uniformity holds) but
is NOT "destined to be lifted" like the value coercions. Also unreconciled: the
uniform-pipeline table's `coerce(SourceText,OPTree)` = perl's C parser is
un-liftable in principle, AND Chalk's REAL self-hosting frontend (the Earley
parser) goes SourceText->SoN DIRECTLY, BYPASSING OPTree — the design has two
frontends (B::SoN-via-optree for t/-drains; Earley-direct for self-hosting) it
never reconciles. The value-coercion lift (the pilot) is the sound, liftable case;
the compiler-pass "lift" is aspirational and blocked on C-struct reflection.

**Naming consequence:** `_discover_and_translate` (which does optree->SoN) is NOT
"translate_optree" (a special compiler verb) — it is `coerce(OPTree, SoNGraph)`, a
MOP multimethod, uniform with `coerce(Int,Str)`. `coerce` was never a naming
COLLISION with the value case — it is the SAME operation, correctly reused. (See
the bare-file-protocol doc; the rename target is `coerce(OPTree, SoNGraph)`.)

## CLOSURE CONDITION: TYPES are a superset of CLASSES; the MOP must reify types

(perigrin) The above REQUIRES (not just implies) that `OPTree`/`SoNGraph` exist as
TYPE OBJECTS in the MOP the multimethod dispatches against. The precise structure —
correcting an earlier CLASS/TYPE conflation (perigrin: "a class is a KIND of type
but not all types represent classes; List is not representable as a class"):

**THREE distinct levels (do not collapse them):**
1. **Type** — the general notion: classifies values, participates in subtyping/
   coercion/dispatch. `Int`, `Str`, `List`, `OPTree`, `Scalar` are all types.
2. **Class** — a KIND of type: has instance-identity, fields, methods, `:isa` — what
   user `class` syntax declares and what native `OBJECT` values instantiate. A
   PROPER SUBSET of types.
3. **Type Object / metaclass** — the REIFICATION: the runtime object REPRESENTING a
   type, so `coerce(A,B)` can dispatch on it. EVERY type has one, class or not.
   (A Type Object is itself an object, so it has a class = the type's metaclass —
   coherent even for a non-class type: the List TYPE OBJECT has a class even though
   `List` isn't a class.)

Relationships: every class is a type; NOT every type is a class; every type has a
Type Object.

**THE PRIMARY AXIS (perigrin): does the type INTRINSICALLY EXIST — i.e. does a
BUILT-IN OPERATION/CONTEXT range over it — INDEPENDENT of whether a class is ever
WRITTEN.** (Refines an earlier over-statement that mandatory types are "unwritten":
whether a type is WRITTEN DOWN is ORTHOGONAL to whether it intrinsically exists.)
- **INTRINSIC / grammar-mandatory** — the type is the DOMAIN or CODOMAIN of a
  built-in operation, so it MUST exist for that operation to have meaning. An
  operation mandates the type it ACTUALLY ranges over — CRITICALLY, `+` mandates
  `Num` NOT `Int` (perigrin's correction): `+ : Num x Num -> Num`; `5+3` works
  BECAUSE `Int<:Num` (the Int is a valid Num), but `+` never sees Int-ness (`5.5+3.5`
  is the SAME op, exact, no truncation). So `+` demands `Num`; it says NOTHING about
  `Int`.
  - `+`/`*`/`/`/comparison -> mandate `Num` (exact on non-integers -> domain is Num).
  - **`Int` is mandated by ops whose domain IS integers** (they TRUNCATE a non-integer
    Num to reach it): `chr(N)` (codepoint), array/string INDEX `$a[i]`, BITWISE
    `& | ^ << >>` (bit patterns — Num is nonsense), REPETITION `x N` (count), RANGE
    `..` (endpoints), `sprintf "%d"`. MEASURED: `chr(65.7)="A"`, `$a[1.9]` -> `$a[1]`,
    `5.5 & 3.5` = `5 & 3`, `"ab" x 2.9` = 2 copies — all TRUNCATE.
  - LIST CONTEXT returns a `List` -> `List` exists. `$`-sigil -> `Scalar`; `undef` ->
    `Undef`; `eq`/`.`/`length` -> `Str`; `@`/`%` -> Array/Hash.
  **DIAGNOSTIC (the signature): an operation's TRUE domain is revealed by where it
  COERCES-DOWN / TRUNCATES.** `+` never truncates -> domain is `Num`. `chr`/index/
  bitwise TRUNCATE their Num arg -> domain is `Int` (the truncation IS `coerce(Num,
  Int)` firing at the op boundary because the op demands Int). Coerce-at-boundary is
  the fingerprint of the narrower true domain.
  The type IS the semantic domain of the language's intrinsic operations. It exists
  whether or not anyone writes `class Int {}`. `Int`/`List` MIGHT get a written class
  LATER (to reify methods/behavior) if useful — **written-ness REIFIES, it does not
  CREATE**; the type was already mandated by chr/index/list-context/etc.
- **NOT INTRINSIC (= "user-defined" in perigrin's sense):** NO built-in operation
  ranges over it; the language is complete without it; it exists ONLY because
  something CHOSE to introduce it. `Point`/`Counter` (a program's `class`),
  `SoNGraph`/`ByteBuf` (Chalk introduces them), `OPTree` (libperl). ALL EQUALLY
  "user-defined" = no intrinsic operation demands them.

**TEST for "is this type in the mandatory core":** is there a BUILT-IN operation
whose domain/codomain is this type? YES -> intrinsic (write a class or not, doesn't
matter). NO -> optional extension. This is WHY `ByteBuf` is demand-driven
backend-internal: no built-in operation ranges over a ByteBuf, so it need not be in
the core lattice.

**[DEMOTED 2026-07-19 — 2nd (Fable, high-effort) assessment: this whole
"derivation" thread is a DIAGNOSTIC/HEURISTIC, NOT a sound generator. Two BLOCKERs
refute "the lattice DERIVES from operations":**
- **F1 (I was DEFINITELY wrong here — perigrin): subtype edges do NOT fall out of
  operation-compatibility (Liskov), and I stated Liskov WRONG on top of that.** TWO
  errors compounded: (i) Liskov-substitutability and the round-trip membership test
  are DIFFERENT criteria — I asserted they coincide; they don't. (ii) I applied the
  WRONG DIRECTION: Liskov `A<:B` = "an A is substitutable where a B is EXPECTED" (B's
  CLIENTS still work), NOT "B's operations apply to A" — I conflated those. Measured
  proof it over-generates: `length($hashref)`=20 and `$ref . "x"` warn ZERO (every
  Str op applies SILENTLY to a Ref) -> "ops apply" would give `Ref <: Str`, which the
  lattice REJECTS (Ref fails round-trip); and my "verification" that `"hello"+1`
  fails was warnings-as-failure (it WARNS and returns 1, doesn't fail). The round-trip
  LATTICE is fine; the claim that op-compatibility DERIVES it is UNSOUND, on the type
  theory, not just a stray counterexample.
- **F2 [REVISED — perigrin: I picked the wrong culprit]: the `scalar()`-identity
  test and the doc's lattice DISAGREE on Glob, and the LATTICE is probably the wrong
  one.** Measured: a glob VALUE (`my $g = *STDOUT`) stores in a $-var (`reftype(\$g)`=
  GLOB), survives scalar copy with identity, has a string form (`"*main::STDOUT"`) —
  it passes the formal doc's OWN Scalar membership criterion ("stored/retrieved from
  a scalar var AND maintains identity through scalar ops", formal.md). So
  `Glob(value) <: Scalar` is likely TRUE, and practical.md's ASCII tree (Glob a
  DISJOINT sibling of Scalar) is the ERROR — not the scalar() test. BUT F2 still
  partially lands against the ORIGINAL claim ("Scalar derivable COMPLETELY from
  scalar()"): `*foo` is OVERLOADED — a glob VALUE (an rv, scalar-storable, `<:Scalar`)
  vs a glob SLOT (`*alias=*arr`, a symbol-table entry, NOT a scalar). "Glob" is TWO
  types the lattice conflates; scalar() cleanly classifies the VALUE, is murky on the
  SLOT — so "Scalar fully derivable from scalar()" overclaims because "Glob" isn't a
  well-defined single type to test. NET: the scalar() test is SOUNDER than I said;
  the lattice's Glob node is wrong/conflated (a KNOWN-INCOMPLETE-LATTICE gap, added
  below). This does NOT rescue F1 (Liskov) — that stands, independent of Glob.
- Also (F6): the residue is NOT an exhaustive partition — the INTERPRETATION axis
  (Int-vs-CodePoint, the doc's own "mini-DualVar": operation-invisible, same i64)
  belongs in the residue but was omitted; Code/Glob/None were never run through the
  test.
So the CORRECT status: types-as-operation-domains is a useful DIAGNOSTIC for which
types are tractable vs hard (the residue = the known hard problems), NOT a way to
GENERATE the lattice or its edges. The lattice + its edges are round-trip-DEFINED
(and, for coerce, VTABLE-POPULATED — see MECHANISM above), not operation-derived.
The paragraphs below are RETAINED as the diagnostic intuition, with "DERIVE" read as
"correlate with", NOT "generate".]**

**(diagnostic, not a generator) If a type IS the domain of its operations, the
lattice and the operation set CORRELATE: `Num` = domain of {+,-,*,/,<,==,...};
`Int` = domain of {chr[but see CodePoint below], index, bitwise, x-repeat, .., %d};
`Str` = domain of
{eq,.,length,...}; `List` = domain of {list-ctx, flatten, wantarray,...}. SUBTYPE
EDGES CORRELATE WITH operation compatibility (`Int <: Num` correlates with every op
valid on Num being valid on Int). [ASSESS3 G8: earlier text here said "Liskov, which
the membership test operationally IS" — that is the FALSE EQUIVALENCE F1 refuted.
Liskov (`A<:B` = an A substitutes where a B is EXPECTED, B's clients still work) is
NOT the round-trip membership test, and op-compatibility does NOT soundly derive
edges (Str-ops apply SILENTLY to a Ref yet Ref is NOT <: Str). This is a CORRELATION
a DIAGNOSTIC observes, not a derivation rule.] And the COERCIONS CORRELATE WITH
domain-boundary mismatches: `chr(5.7)` needs
`coerce(Num,Int)` (truncate) to get from the Num-you-have to the Int-chr-wants — that
downcast-at-the-boundary correlates with a lattice edge. [ASSESS-CORRECTED F5: `chr`
is a POOR flagship example — the later CodePoint correction (below) rules chr's
from-type is `CodePoint` NOT `Int`, so chr does NOT cleanly "mandate Int"; Int is
mandated by index/bitwise/x/`..`/%d instead. Use THOSE as the Int-domain witnesses,
not chr.] The intuition (an op's domain correlates with a type; a boundary
truncation correlates with a coercion) is a DIAGNOSTIC, not a generator (see the
demotion banner: op-compatibility does NOT soundly derive edges — F1). `List`-the-
non-class still has a Type Object because list-context (an intrinsic) ranges over it
— being a type = being an operation-domain, ORTHOGONAL to being class-shaped.

**BUT — CAN we derive the FULL lattice from operations? NO. Stress-tested
2026-07-19; operations derive the CORE but THREE regions are UNDERIVABLE, and each
is a KNOWN hard problem (so op-derivability is a DIAGNOSTIC, not a complete
generator):**
- DERIVES: the subtype CHAIN (Int/Num/Str/Char), the Ref subtree (`\`->Ref;
  deref-ops partition Array/Hash/Code-Ref; reftype discriminates), and the
  coercions. It CORRELATES with even the surprising `Num<:Str` (every Str op works
  on a Num). [ASSESS3 G8: earlier text claimed `"hello"+1` "fails" as the witness for
  "Str NOT<:Num" — that is FALSE. `"hello"+1` WARNS and returns 1 under `use
  warnings`; it does NOT fail. So op-compatibility does not even cleanly SIGNAL the
  non-edge. This is why the whole thread is a diagnostic, not a generator.]
- [CORRECTED — was "UNDERIVABLE #1: the top Scalar/Any"; perigrin gave TWO fixes]
  **(a) `Scalar` IS the TOP OF SCALARS, NOT the whole-lattice top — `Scalar` and
  `List` are DISJOINT siblings under `Any/Unknown`** (a List is not a Scalar —
  different context category). So the true top is `Any`, not `Scalar`.
  **(b) `Scalar` IS operation-derivable after all — as the CODOMAIN of `scalar()`.**
  Measured: `scalar(@a)=3` (Int), `scalar((1,2,3))=3` (Int, last elem),
  `scalar("hi")="hi"` (Str), `scalar(\@a)`=Ref — the OUTPUT TYPE varies with input,
  so the ONLY type assignable to `scalar(EXPR)` knowing nothing about EXPR is
  `Scalar` = the JOIN of all possible scalar outputs = the top of the scalar
  sub-lattice. `scalar()`/scalar-context is the operation that PRODUCES the
  most-general scalar value, so its CODOMAIN IS `Scalar`. **SHARPENED PRINCIPLE: a
  type is op-derivable if some op has it as DOMAIN *OR CODOMAIN* — and a SUB-LATTICE
  TOP is derived via a CODOMAIN (the op that produces the most-general value), NOT a
  domain (no op consumes ONLY the most-general type — everything does).** I had
  under-weighted codomains.
  **What REMAINS underivable is `Any` (the REAL top) specifically** — the join
  ACROSS the disjoint context categories (Scalar ⊔ List ⊔ Code ⊔ Glob). No single op
  produces `Any`, because context FORCES scalar-or-list (nothing crosses the
  Scalar/List disjointness). So `Any` is the closure/fixed-point residue (= the
  formal doc's "circular definition" region, formal.md:19), but each SUB-LATTICE top
  (`Scalar` via scalar(), presumably `List` via list-context) IS derivable.
  **(c) THE FULL CLOSURE (perigrin): `scalar()` is the IDENTITY coercion ON scalars —
  which IS the `<: Scalar` membership test.** Measured: `scalar(42)==42`,
  `scalar("hi") eq "hi"`, `scalar($ref)==$ref` — a NO-OP on any scalar. So
  `X <: Scalar` iff `scalar()` is IDENTITY on X — exactly the formal doc's membership
  `C(v) ≡ id(v)` with `C = scalar()`. This gives `scalar()` triple duty from ONE
  operation: the NODE (`Scalar` = its codomain), the DOWN-EDGES (`X<:Scalar` = it's
  identity on X), and the TOP-PROPERTY (Scalar is the sub-lattice top BECAUSE its
  edge-defining coercion is IDENTITY on all members). So `Scalar` is derivable
  COMPLETELY (node+subtree+top) from `scalar()`, fully retiring "the top is an
  underivable lub."
  **TWO STRENGTHS of subtype edge (both valid under round-trip, measured):**
  IDENTITY (`Int<:Scalar` via `scalar()` — a NO-OP; "Int already IS a Scalar") vs
  INVERTIBLE (`Int<:Str` via stringify — `65->"65"->65`, transforms-but-recovers;
  "Int CONVERTS to Str and back"). A sub-lattice TOP is characterized by IDENTITY
  coercion on all members (strongest); the chain edges are INVERTIBILITY (weaker).
- UNDERIVABLE #2 — REPRESENTATION-distinguished types (`IV` vs `UV`; byte-vs-Unicode
  Str): NO operation distinguishes IV from UV (identical ops; differ only in
  range/representation). Operation-INVISIBLE by construction. **THIS EXPLAINS THE UV
  BUG (019f77d8): UV is a latent miscompile PRECISELY because no operation
  distinguishes it, so the signed-i64 assumption slips through.** byte-vs-Unicode Str
  is the same category (deferred UTF-8, 019f51e7).
- UNDERIVABLE #3 — REFLECTION-layer types (`DualVar`; partly `Bool`): DualVar is
  created by no ordinary op (only `Scalar::Util::dualvar`, a reflective constructor)
  and detected only by probing. Bool is PARTLY op-derivable — comparison/`!` codomain
  IS Bool (`is_bool(5>3)`=true) but `&&`/`||` return an OPERAND not a Bool
  (`is_bool(5&&3)`=false), so the ops you'd expect DON'T mandate it. **DualVar being
  underivable = WHY it is residual runtime MOP** (can't be resolved by op-domain
  machinery; must be a runtime object).
- (Also: even where an op derives a type, it does NOT derive the type's VALIDITY
  refinement — `chr`'s domain is Int but the VALID domain is [0,0x10FFFF]-surrogates,
  a predicate the domain-view can't express.)

VERDICT (revised after the scalar()/Any corrections): lattice = (operation-derivable
core — now INCLUDING each SUB-LATTICE top, e.g. `Scalar` via scalar()'s codomain) +
(a closure ONLY for `Any`, the join across the disjoint context categories Scalar/
List/Code/Glob — no op crosses that disjointness) + (a REPRESENTATION axis orthogonal
to operations) + (a REFLECTION layer). Operations give the CORE + the sub-lattice
tops (via codomains). The genuinely un-derivable residue narrows to {`Any`-the-real-
top (context-category join), representation axis = the UV bug, reflection layer =
DualVar/residual-MOP}. Op-derivability PARTITIONS the lattice into "tractable core
(build this — now bigger, includes sub-lattice tops) vs the residues" — a strong
DIAGNOSTIC. Key lesson: DON'T under-weight CODOMAINS — the most-general types are
derived by the ops that PRODUCE them (scalar()), not consume them.

**Secondary sub-classification of the NOT-mandatory bucket — only bears on
LIFTABILITY, not on whether the lattice needs the type:** user-class (`Point`,
native/liftable), compiler-internal (`SoNGraph`/`ByteBuf`, native/LIFTABLE),
foreign (`OPTree`, FOREIGN C struct/NOT-liftable). `SoNGraph`+`ByteBuf` are the same
sub-tier (native, liftable); `OPTree` differs only here (foreign), NOT on the
primary axis.

**Orthogonal: class-shaped vs not.** `List` is grammar-mandatory AND non-class (an
ephemeral list-context sequence, no instance-identity — you cannot `class List{}`),
yet has a Type Object (`coerce(List,Scalar)` = list->length/last is real). So "being
a dispatchable type in the MOP" does NOT require "being a class" — the MOP reifies
non-class types too.

> **The lattice's NON-NEGOTIABLE CORE is exactly the GRAMMAR-MANDATORY types
> (Scalar/List/Undef/Num/Str/Int/Bool/Hash/Array/Ref — the syntax presupposes them).
> Everything else is a NOT-GRAMMAR-MANDATORY extension the MOP reifies ON DEMAND:
> user classes (Point), compiler-internal types (SoNGraph, ByteBuf), foreign types
> (OPTree) — all equally "user-defined" = grammar-agnostic. The MOP reifies TYPES
> (a Type Object each), class or not, whichever tier. WHO-defined-it / native-vs-
> foreign is a SECONDARY axis bearing only on LIFTABILITY, not on lattice-necessity.**

**This capability ALREADY EXISTS and is load-bearing — the primitive types ARE the
proof.** `Int`/`Str`/`Num`/`Scalar` are metaclasses in the lattice that NO USER
ever declared (there is no `class Int` production); they exist at the meta layer as
first-class type objects, dispatched against by repr inference, WITHOUT source
declaration. So `OPTree` is to `SoNGraph` as `Int` is to `Str`: a metaclass with no
grammar origin, participating in `coerce`. The requirement is not "build a new
capability" but "RECOGNIZE that the existing capability (metaclasses without grammar
origin — the primitive types) GENERALIZES to the compiler's own types."

**Mechanism: DESCRIBED, not declared.** The MOP is populated by `declare_*/seal`
(the JSON replay), not only by parsing `class`. `Int`/`Str` get DECLARED INTO the
MOP by the bootstrap, not parsed from source. `OPTree`/`SoNGraph` get declared the
same way — bootstrap-seeded primitive/built-in metaclasses. The grammar is ONE
source of metaclasses (user `class`); the bootstrap is ANOTHER (primitives +
compiler types); the MOP is the UNION.

**CLOS precedent (this is not novel — and it has BOTH gaps):** CLOS distinguishes
class-kinds AND has types that aren't classes:
- `standard-class` — user `defclass` (grammar-declared, class-shaped).
- `built-in-class` — `integer`/`string`/`cons` — class-shaped types you CANNOT
  `defclass` (= gap 1: no grammar origin). Chalk's `Int`/`OPTree` are here.
- `deftype` / TYPE SPECIFIERS — `list`, `null`, `(or ...)`, `(integer 0 10)` — TYPES
  you dispatch on that are NOT classes and NOT `defclass`-able at all (= gap 2:
  not-a-class). Chalk's `List` is here.
CLOS NEEDED the type/class split for exactly this reason: `list`/`null`/
`(integer 0 10)` are dispatchable types that aren't classes. Chalk inherits the
same need the moment `List` is in its lattice. So Chalk needs metaclass reification
across the four "who defines it" tiers: user grammar-`class` (`Point`), bootstrap
class-shaped (`Int`), COMPILER-AUTHOR class-shaped in Chalk source (`SoNGraph`/
`ByteBuf` — native/liftable) vs FOREIGN (`OPTree` — non-liftable), AND non-class
types (`List`) — a Type Object without class machinery.

**Why this is the CLOSURE condition for the whole design:** "everything is an OBJECT
via the MOP" is only TOTAL if the compiler's OWN values (a `SoNGraph`, an `OPTree`)
have metaclasses — else the metacircle LEAKS exactly at the compiler-internals
boundary. User-types-at-the-meta-layer plugs that hole for the DESCRIPTION: the
compiler's types are in the MOP, so the compiler's values have metaclasses, so
naming/dispatch is closed over the compiler's own values, not just user programs.

**[ASSESS3 G5 — the closure is DESCRIPTIVE, not IMPLEMENTATION-level.** Reifying
`OPTree` as a Type Object closes the DESCRIPTION (it has a metaclass; `coerce` can
NAME `coerce(OPTree,SoNGraph)`). It does NOT close the IMPLEMENTATION: per this doc's
own [ASSESS] demotion, `coerce(OPTree,SoNGraph)` is NOT liftable (OPTree is libperl's
C struct, no subset FFI), and `coerce(SourceText,OPTree)` is un-liftable in principle
— the vtable cell for those coercions is FOREVER foreign gen-0 Perl walking B. So
"closed over the COMPILER ITSELF" overstates: the metacircle still LEAKS at the
compiler-internals boundary in implementation. The IMPLEMENTATION closure the design
actually has runs through the EARLEY frontend (SourceText -> SoN over NATIVE types),
which makes B::SoN permanent scaffolding OUTSIDE the circle — a permanently-foreign
gen-0 cell. TERMINATION is unaffected (external gen-0 grounding + the permanent floor
is the standard staged-bootstrap argument and is sound); only this closure claim was
too strong.]**

**Discipline (how much to reflect):** `OPTree`/`SoNGraph` must be USEFUL metaclasses,
not just labels — the MOP must describe enough of their STRUCTURE for a `coerce` to
walk an OPTree's ops and build a SoNGraph's nodes. But reflect ONLY as much
compiler-type structure as a LIFTED coercion needs (demand-driven, like everything
else) — not the whole compiler speculatively. The compiler's data model becomes a
REGION of the type lattice, reflected exactly to the depth a coercion touches.

## THE LATTICE (corrected from the architecture docs)

From `perl-type-system-practical.md` (canonical) and `-formal.md` (proofs). The
subtyping chain is LINEAR, derived from a coercion ROUND-TRIP membership test
(`A <: B` iff every A-value survives B's round-trip — [ASSESS] formal.md's
membership is DUAL: syntactic round-trip AND behavioral contract, e.g. "NaN"
survives the Num round-trip syntactically but FAILS behavior; the one-line "iff"
here drops the behavioral half), NOT from machine representation:

```
Any/Unknown
├── Scalar
│   ├── Undef
│   ├── Bool                    *is_bool edge case; see formal.md L483
│   ├── Str                     Str <: Scalar
│   │   └── Num                 Num <: Str  (!!) numbers round-trip through
│   │       └── Int             Int <: Num   stringification; arbitrary Str
│   │                                        does NOT round-trip through numify
│   ├── DualVar                 independent str + num faces (Scalar-not-Str)
│   ├── Regex                   also a Ref w/ reftype REGEXP (dual-located)
│   └── Ref
│       ├── ScalarRef ArrayRef HashRef CodeRef GlobRef
│       └── Object              Object <: Ref; blessed = Object ∩ HashRef etc.
├── List
│   ├── Array   Hash
├── Code   Glob   None
```

**Key facts that correct the naive tree:**
- `Int <: Num <: Str <: Scalar` — a linear NESTING chain. Int is the DEEPEST
  (most specific); Str is the most GENERAL of the three. `Num <: Str` is the
  surprising one: a number IS a special string (it round-trips through
  stringification), but not vice versa.
- Bool, Undef, DualVar, Regex, Ref are DIRECT Scalar children — SIBLINGS of Str,
  OFF the numeric chain. They fail the Str round-trip test (a Ref stringifies to
  "HASH(0x..)" which doesn't parse back).
- **`_REPR_RANK = Int(0) < Num(1) < Str(2)` in the loader IS this chain** — its
  "join = max rank" is the lattice LUB; its silence on Bool/Undef/Ref is CORRECT
  (they are incomparable/off-chain, so no rank, and the `'join'`/`'same'` repr
  rules bailing on them is right, not a bug).

**CRITICAL: round-trip proves MEMBERSHIP ONLY — it is ORTHOGONAL to coercion
validity** (perigrin, correcting an earlier conflation). The round-trip test does
exactly ONE job: define/prove subtype membership (`A <: B` iff every A round-trips
through B). It says NOTHING about whether `coerce(A,B)` exists, is total, or is
sound. TWO INDEPENDENT AXES:
1. MEMBERSHIP (does A <: B?) — round-trip. Governs lattice structure + which
   coercions are subtype-UPCASTS.
2. COERCION VALIDITY/TOTALITY — a SEPARATE per-`(A,B)` property.
Counterexample that pins it: **`coerce(Ref, Str)`** (a ref stringifies to
"HASH(0x..)") is NOT round-trippable (so `Ref ⊄ Str`) YET is a completely VALID,
TOTAL, always-succeeds coercion. Non-round-trippable does NOT mean lossy/invalid;
it means "does not prove membership." Likewise `coerce(Num,Str)` and
`coerce(OPTree,SoNGraph)` — valid coercions between types with no (relevant)
subtype relation. A coercion GAPs only when the specific `(A,B,value)` has NO
DEFINED METHOD — unrelated to whether A<:B.

Direction: an UPCAST (Int->Num->Str, along the subtype chain) is often
identity/cheap; a coercion between INCOMPARABLE types (Ref->Str, OPTree->SoNGraph)
is valid and may be total or may GAP-on-a-specific-value — but incomparability
itself does NOT cause the GAP.

**Resolved-inline vs residual-runtime is driven by STATIC-PAIR-KNOWLEDGE, NOT
on/off-chain** (correcting an earlier wrong cut):
- If the `(from, to)` pair is STATICALLY KNOWN at compile time -> resolved ->
  inlined -> optimized away. This includes on-chain value coercions (num.t,
  string-compare) AND `coerce(OPTree,SoNGraph)` (both repr types known — it runs
  entirely at compile time = the compiler itself) AND `coerce(Ref,Str)` when the
  operand's type is known.
- If the FROM-TYPE is NOT statically known (a genuinely runtime-polymorphic value)
  -> RESIDUAL runtime dispatch. DualVar/magic/overload are residual because the
  from-type isn't statically pinned, NOT because they are "off-chain". (Off-chain
  and residual are correlated but the real driver is static-pair-knowledge.) The
  formal doc names DualVar a first-class Scalar-child with independent str/num
  faces — a metaclass with independent `coerce(_,Str)` and `coerce(_,Num)`.

**OBJECT is where the lattice and the MOP COINCIDE (the clean seam).** Perl 5.38+
`feature class` introduced a NEW reftype: a native class instance has
`reftype() eq 'OBJECT'` (measured 2026-07-19), NOT the underlying HASH/ARRAY.
This is CATEGORICALLY different from a legacy blessed hashref:
- **Native OBJECT** (Chalk's ONLY object model — Chalk uses `class`, not `bless`):
  OPAQUE. No underlying storage kind; cannot be dereferenced as HASH/ARRAY. Its
  ENTIRE interface is its MOP class (methods + class-defined field accessors).
  Each user class is a subtype (`Point <: OBJECT <: Ref`). Its `coerce(_,Str)` is
  overload-or-default; its dispatch is MRO on `:isa` — i.e. `OBJECT` is the ONE
  Ref subtype whose behavior IS the MOP. Every other reftype (HASH/ARRAY/CODE)
  has structural operations independent of any class. So for `OBJECT`, "the type
  lattice" and "the MOP" are the SAME structure — the seam this whole design
  reaches for.
- **Legacy blessed refs** = INTERSECTION types (`Object ∩ HashRef`, ...):
  dual-interface (both `$o->{k}` and `$o->method`). The formal doc spends
  paragraphs on these, but they are the LEGACY path Chalk EXCLUDES. The
  opacity of native OBJECT is exactly what lets Chalk resolve dispatch
  statically and fix field offsets (no `$obj->{arbitrary}` escape hatch), so the
  MOP is the complete interface. Do not model the intersection types.

The lattice doc's ASCII tree lists `Object` as one Ref-subtree LEAF beside
HashRef/ArrayRef — which FLATTENS this distinction. Correct framing: OBJECT is a
categorically distinct opaque kind (Chalk's actual objects), NOT a peer of the
structural reftypes; the blessed-ref intersection types are the excluded legacy
path.

## The grounding is BOOTSTRAP GENERATIONS, not a privileged base (perigrin)

FIRST TAKE (superseded): "Level-0 primitives (`add i64`, `store`, `gep`) are raw
nodes OUTSIDE the metacircle; metaclass methods get a privileged INTRINSIC
vocabulary user code doesn't." This is WRONG — it invents a special category.

CORRECT MODEL (with an [ASSESS] reconciliation below): `Int.+` IS a genuine
meta-method (a message send, uniform with everything else, like Smalltalk
`3.+(4)`). `add i64` is not a DIFFERENT KIND of thing at the SEMANTIC level — it is
that meta-method's MEANING; the distinction is STATE: "already-compiled" vs
"needs-compiling". So-called Level-0 = "meta-methods a PREVIOUS BOOTSTRAP
GENERATION already lowered to IR."

**[ASSESS] RECONCILIATION — two definitions of Level-0 were in tension; the honest
statement is a SMALL PERMANENT BASE + liftable everything-else.** The "no true
Level-0 / pure state" framing above conflicts with the MINIMIZE-gen-0 section's
"IRREDUCIBLE substrate (machine arithmetic/memory/control) can't be written in the
subset without themselves." Both are partly right; resolve them:
- SEMANTICALLY, everything is a meta-method (uniform) — the "no privileged kind"
  point holds for the OBJECT MODEL.
- OPERATIONALLY, there IS a small PERMANENT intrinsic base: the backend's hardcoded
  primitive lowering (`Add`->`add i64`, memory, control). It is NEVER lifted at any
  generation — you cannot write "integer add" in a language whose integers ARE
  i64. It is not a movable "already-compiled artifact"; it is a fixed rule. (The
  rhetorical "`add i64` IS `Int.+` already compiled by gen-0" is loose: NO compiled
  `Int.+` IR artifact exists — gen-0's "already-compiled set" is template-emitting
  Perl subs + hardcoded lowering rules, a DIFFERENT kind of thing from the IR
  artifacts the memoization argument quantifies over.)
So: a SMALL permanent intrinsic base (backend primitive lowering) + everything
above it liftable across generations. The termination argument (below) is sound
EITHER way — it is the standard staged-bootstrap argument grounded in an external
gen-0 — but "no true Level-0" over-claims; there is a small irreducible floor.

**Perl is Chalk's generation-0 compiler.** `_emit_int_to_str` is not a
"privileged primitive" and not "legacy" — it is `coerce(Int,Str)` as compiled
by generation 0 (Perl emitting LLVM). The metacircle is broken NOT by a
metaphysically-special base but by A PREVIOUS COMPILER having done the lowering.

The tower is a FIXPOINT OVER COMPILATION STATE, not a static stratification:
- Gen 0: Perl compiles the primitive meta-methods (`Int.+`, `coerce(Int,Str)`,
  ...) → IR. The "already-compiled" set is seeded.
- Gen 1: Chalk, USING gen-0's compiled meta-methods, compiles more meta-methods
  that depend on them → their IR. The frontier moves forward.
- ... the already-compiled set grows; each generation depends ONLY on the
  previous generation's already-compiled set → well-founded, no cycle.

"Level 0/1/2" were never three KINDS of method — they are three BOOTSTRAP
GENERATIONS. `add i64` is "Level-0" because gen-0 (Perl) compiled it, not because
it is ontologically beneath the MOP.

**This is Smalltalk/Self's own resolution:** `3 + 4` really IS a message send
(uniform semantics), but the compiler INLINES the already-compiled SmallInteger
`+` primitive (fast). `+` is BOTH a real method AND a spliced primitive — no
contradiction, because "pre-compiled meta-method spliced inline" IS what a fast
primitive is.

Termination argument (stronger than "grounded in raw nodes"): meta-dispatch is
**MEMOIZED ACROSS BOOTSTRAP GENERATIONS**. Gen 0 is compiled by an EXTERNAL
compiler (Perl); each later gen depends only on the already-compiled set; the
frontier only moves forward. This is the standard self-hosting-bootstrap
termination argument (a compiler compiles a compiler that compiles...), applied
to the RUNTIME layer — the same argument we already trust for the compiler
itself.

**Corrected soundness invariant** (supersedes the "Level-0 doesn't participate in
the metacircle" clause — it DOES participate; its participation was resolved in a
previous generation and cached as IR):
> The MOP is metacircular in structure. Operationally it terminates because
> meta-dispatch bottoms out in a SMALL PERMANENT INTRINSIC BASE (the backend's
> primitive lowering: Add->`add i64`, memory, control — a FIXED RULE, never lifted
> at any generation) PLUS memoization for everything above it (gen 0 compiled by an
> external compiler, later generations depend only on the already-compiled set,
> frontier moves forward). [ASSESS-CORRECTED: the earlier "NO privileged 'below the
> MOP' — only already-compiled vs needs-compiling" phrasing OVER-CLAIMED; there IS a
> small irreducible floor. The floor is a fixed lowering RULE, a DIFFERENT kind of
> thing from the IR-artifact "already-compiled set" the memoization quantifies over —
> so termination = (permanent floor) + (memoization above it), not memoization alone.]

Consequence: everything ABOVE the small permanent floor is Chalk-compiled Chalk
meta-methods as self-hosting completes; Perl's role recedes to a historical bootstrap
that could be REGENERATED for the LIFTABLE layer. But `add i64` (the floor) is NOT a
"fact about the current generation" that dissolves — it is the irreducible base;
[ASSESS-CORRECTED: the earlier "add i64 is a fact about the current bootstrap
generation, not eternal" over-stated — the floor IS eternal/irreducible; only the
LIFTABLE superstructure is generation-relative].

The compiler STILL resolves meta-dispatch at compile time (it must know "this `+`
on two static-Int operands = splice the compiled `Int.+` IR") — but the RESULT of
that resolution is a pre-compiled IR fragment it splices, so the operational
metacircle is broken by cross-generation memoization, not by a privileged base.
Dependency DAG constraint still holds (each meta-method depends only on
already-compiled ones = the previous generation).

## MINIMIZE gen-0: the bare runtime IS the smallest Level-0 (perigrin)

TENSION: self-hosting wants gen-0 (the pieces Perl hand-compiles) SMALL — every
hand-emitter is a hole in self-hosting + hand-maintained surface that can drift
from its self-compiled counterpart. Performance wants MORE pre-compiled/memoized
(splice inline, faster). RESOLUTION: minimize gen-0 NOW; treat "pre-compile more"
as a LATER, OPTIONAL optimization pass. Rationale: pre-compilation-as-optimization
is ADDITIVE and REVERSIBLE (you can always memoize more later — pure speed win,
changes nothing about correctness or self-hosting); a bloated gen-0 is NEITHER
(permanent hand-maintained surface, permanent self-hosting holes, drift risk).
Small gen-0 KEEPS optionality; big gen-0 SPENDS it. Separate "what MUST gen-0
contain" (small, correctness/self-hosting) from "what MAY we pre-compile"
(later, speed).

**THE BARE RUNTIME = the minimal gen-0 seed = the smallest Level-0.** These are
the SAME object from two directions: bootstrap ("irreducible seed Perl must
hand-compile") and runtime ("primitives everything is built on"). So the bare
runtime is NOT a separate design choice — it FALLS OUT of minimizing gen-0.
Finding it is a DISCOVERY task, not a design task: for each candidate primitive,
ask "can this be written in the subset using OTHER primitives, or is it
irreducible?"

**The concrete cut (hypothesis to validate):**
- IRREDUCIBLE (Level-0, can't be written in the subset without themselves):
  machine arithmetic/compare on machine value types (`add/sub/mul/div i64`,
  `icmp`, `fadd/fcmp`, bit ops); memory (`load/store/gep/alloca/malloc`); control
  (`br/phi/ret`); **[ASSESS3 G7] the HOST-INTERFACE / I-O category (a `call` to a
  host/libc function — `printf`, `strtod`, `open`/`read`/`write` — is NOT composable
  from arithmetic/memory/control, so it is a FOURTH floor category, not derivable).**
  The subset's own `if`/`while`/arithmetic LOWER TO these — they are the substrate.
  **File I/O (mod.t's wall, and `print`) lives HERE: a MOP method over the (currently
  unmodeled) IO Ref subtype whose body bottoms out in host-call intrinsics — it is
  neither a coercion nor floor-composable, so it needs this category named.**
- REDUCIBLE (NOT Level-0, composed): `_emit_int_to_str` — its body is a do-while
  over udiv/urem/add/store, which IS expressible in the subset. So
  `coerce(Int,Str)` is the SMALLEST thing that is NOT Level-0 — the first
  meta-method liftable from gen-0 hand-emission into self-compiled subset code.
  Likewise `chalk_str_to_num` (a parse loop, currently cheating via libc), and
  all other coercions/dispatch/field/truthiness.

**KEY: the Level-0 FLOOR is ALREADY IMPLEMENTED — it's PART of the existing backend.**
Chalk's LLVM target already lowers `Add`/`Subscript`/`If`/`Loop` to `add`/`gep`/`br`.
So the bare runtime = the primitive-node lowering we ALREADY have; PLUS the byte-write
primitive (ByteBuf, see the pilot section — the ASSESS finding). **[ASSESS3 G7 caveat:
"it's the existing backend" EQUIVOCATES — the 5,789-line Context.pm is MOSTLY non-floor
gen-0 emitters (the regex subcompiler, Concat, the class registry, the printf
epilogues) = the LIFTABLE superstructure, NOT the floor. The floor is the small
arithmetic/memory/control/host-call CORE inside it; the rest is what gen-0 will
eventually lift.]** Lifting
`_emit_int_to_str` into a self-compiled `coerce(Int,Str)` (compiled through the
Level-0 backend + ByteBuf, BEHAVIOR-identical to the hand-emitter — NOT byte-
identical; graph-inlined SSA differs and GVN changes output by design) IS the act
of proving the bare runtime is complete enough to build on.

**Reframed FIRST TASK (discovery + validation, small + self-contained):**
1. DISCOVER the minimal Level-0 by attempting to express each current "primitive"
   in the subset; the ones that RESIST are Level-0 (hypothesis: exactly what the
   backend already lowers — arithmetic/memory/control).
2. VALIDATE with the smallest lift: write `coerce(Int,Str)` as a subset method
   (using the ByteBuf byte-write primitive), compile it through the existing
   Level-0 backend, prove BEHAVIOR-IDENTICAL (stdout/exit — NOT byte-identical) to
   `_emit_int_to_str` (the gen-0 seed, KEPT until this passes) via the
   S9-S12/L6d/L6e BEHAVIOR blocks (the ir-blocks are rewritten by the Stringify-node
   deletion — see the pilot [ASSESS] notes).
If (2) succeeds: the bare runtime is proven small + buildable-upon; "pre-compile/
memoize more" becomes a well-defined OPTIMIZATION backlog drawn down for speed,
never a correctness or self-hosting requirement.

## THE METACIRCULARITY (load-bearing invariant — this is what makes it SOUND)

"Everything is an instance of OBJECT via the MOP" is metacircular: a value is an
instance of its metaclass; a metaclass is a class, hence an instance of ITS
metaclass; `Class` is an instance of `Class` (the CLOS/Smalltalk/ObjVLisp fixed
point). The formal type doc already admits this (L19: "circular definitions of
Scalar and List conjectured to have a unique fixed-point solution"). This
circularity is NOT a bug to eliminate — it is the SIGNATURE of self-hosting at
the runtime layer (same as a metacircular interpreter: `eval` written in the
language it evaluates). But there are TWO circularities and they behave OPPOSITELY:

1. **STRUCTURAL / bootstrap circularity — BENIGN.** `Class isa Class`, `Int` is
   an OBJECT, the metaclass-of-metaclass tower. A fixed point TIED ONCE at
   bootstrap, then it just IS — never re-derived, never RUNS. Lives in the MOP
   structure (the `declare_*/seal` MOP-replay mechanism IS the knot-tying).
   Runtime cost: ZERO.
2. **OPERATIONAL / lowering circularity — FATAL if not stratified.** If lowering
   `coerce(Int,Str)` REQUIRED dispatching through the MOP, and MOP dispatch itself
   needed a coercion, inlining regresses infinitely AT COMPILE TIME. "Everything
   is an OBJECT via the MOP" would mean even `add i64` wants to go through `Int`'s
   metaclass. This must be broken.

**THE INVARIANT that keeps structure-circular but operation-well-founded**
(REVISED per the bootstrap-generations model below — the earlier "Level-0 doesn't
participate in the metacircle" phrasing was wrong; it DOES participate, resolved
in a previous generation and cached as IR):
> The MOP is metacircular in its STRUCTURE (Class is an instance of Class; every
> value incl. a metaclass is an OBJECT — a sealed bootstrap fixed point).
> Operationally it terminates because meta-dispatch is MEMOIZED ACROSS BOOTSTRAP
> GENERATIONS: gen 0 is compiled by an external compiler (Perl), and each later
> generation's meta-methods depend only on the already-compiled set. There is NO
> privileged "below the MOP" — only "already compiled" vs "needs compiling", and
> the frontier only moves forward. The compiler collapses structural
> metacircularity into already-compiled IR at every point where types are
> statically known; only the residual carries runtime dispatch (also grounded in
> the already-compiled set).

Concretely: `add i64` is NOT a metaphysically-different raw node — it is `Int.+`
(a genuine meta-method) AS COMPILED BY A PREVIOUS BOOTSTRAP GENERATION. A meta-op
on a statically-known metaclass collapses to already-compiled IR WITHOUT a runtime
MOP consultation — the COMPILER did the MOP lookup (circularity #1's sealed fixed
point) and SPLICED the pre-compiled fragment. So "everything is an OBJECT via the
MOP" is true AS A DESCRIPTION and false AS A RUNTIME MECHANISM for resolved cases.
Structure circular (self-hosting) + operation well-founded via cross-generation
memoization (terminates). See "The grounding is BOOTSTRAP GENERATIONS" below for
the bootstrap-generation model (reconciled: a SMALL PERMANENT intrinsic base — the
backend's primitive lowering — plus liftable everything-else; the "no true Level-0"
phrasing over-claimed).

### The bootstrap paradox (why the pilot is a swap-against-an-oracle)

To compile `coerce(Int,Str)` (a MOP method) Chalk needs a working `Int`
metaclass — but `coerce(Int,Str)` is PART OF what defines `Int`. Chicken/egg.
Resolved by STAGED BOOTSTRAP (every self-hosting system does this):
- **Stage 0**: a minimal `Int` metaclass whose coercion is provided EXTERNALLY.
  **`_emit_int_to_str` (today's hand-written LLVM emission) IS the stage-0
  bootstrap `coerce(Int,Str)`** — it breaks the metacircle from OUTSIDE.
- **Stage 1**: use stage-0 Chalk to compile the subset-Perl `coerce(Int,Str)`
  to IR. The method now exists as compiled IR.
- **Stage 2**: swap the external stage-0 impl for the self-compiled stage-1 one;
  verify BEHAVIOR-IDENTICAL output (stdout/exit — NOT byte-identical; see the pilot
  gate [ASSESS]) against the S9-S12/L6d/L6e behavior blocks. Knot tied AND grounded
  — the method is now Chalk-compiled Chalk code.

REFRAMING: `_emit_int_to_str` is NOT "legacy code to delete" — it is the STAGE-0
BOOTSTRAP SEED that breaks chicken-and-egg. KEEP it until stage-2 verification
passes. The pilot's swap-against-an-oracle structure IS the staged bootstrap that
ties the metacircular knot safely.

## KNOWN-INCOMPLETE LATTICE BOUNDARY (do not treat the doc as total)

The architecture docs' lattice is a solid, load-bearing CORE, but is explicitly
NOT total over Perl core (the docs admit methodological gaps: mechanization,
list-context, the Boolean/`is_bool` edge). Additional core types the lattice
does NOT yet place (measured 2026-07-19 via reftype() + builtin):

- **`Glob` is CONFLATED — value vs slot (perigrin, measured 2026-07-19):** the docs'
  ASCII tree lists `Glob` as ONE type, a disjoint sibling of Scalar. But `*foo` is
  OVERLOADED: a glob VALUE (`my $g = *STDOUT` — an rvalue, stored in a $-var,
  `reftype(\$g)`=GLOB, survives scalar ops with identity, string form
  `"*main::STDOUT"`) which PASSES the formal doc's Scalar membership criterion, so
  `Glob(value) <: Scalar` (NOT disjoint — the tree is WRONG here); vs a glob SLOT
  (`*alias = *arr` — a SYMBOL-TABLE entry holding $/@/%/& slots, a symbol-table
  op, NOT a scalar). Two distinct types the lattice fuses under one `Glob` node. Fix:
  split `GlobValue` (<: Scalar / Ref-ish, reftype GLOB) from `GlobSlot` (symbol-table
  container, its own axis). (Code has the analogous `sub{}`-value vs CV-slot split.)
- **`Char` / `CodePoint` — a length-refinement sub-lattice the docs don't place
  (perigrin, measured 2026-07-19):** Perl has NO distinct Char type — a "char" is a
  length-1 Str (`chr(65)="A"` is a normal string, length 1). So `Char = {s : Str |
  length(s)==1}`, hence `Char <: Str` (a length refinement). KEY ASYMMETRY:
  **`Int <: Str` but `Int ⊄ Char`.** `Int <: Str` is a CANONICAL subtype inclusion
  (stringify is THE map: 65 -> "65", round-trips). `Int ⊄ Char` because (a) length:
  ints >= 10 or negative stringify to length>=2 (not Char-shaped); (b) EVEN for
  single-digit ints where shape overlaps, there is NO CANONICAL Int->Char map — `5`
  maps to `"5"` (as NUMERAL, codepoint 53) OR `chr(5)` (as CODEPOINT, a control
  char) and `"5" ne chr(5)` (measured). Subtyping needs a canonical inclusion;
  Int->Char is TWO competing maps, so the edge is absent. **The ambiguity that made
  `chr != stringify` a potential miscompile IS the reason `Int ⊄ Char`** — the
  source "Int" is really TWO types wearing one i64 (Int-as-number vs CodePoint), a
  load-bearing mini-DualVar. Clean coercions once the interpretation is committed:
  `coerce(Int,Str)` = stringify (canonical, the Int<:Str inclusion);
  `chr = coerce(CodePoint, Char)` (canonical once codepoint-committed);
  `coerce(Int,Char)` does NOT exist (ambiguous). The complement of `chr` is `ord`.
  **[CORRECTION 2026-07-19, perigrin — RETRACTS an earlier "genuine bijection"
  claim] `chr`/`ord` are PARTIAL and NOT a clean Int<->Char bijection (measured):**
  - NOT TOTAL on Int: `chr(-1)`, `chr(-100)` don't error — they WARN and return
    U+FFFD (the replacement char, ord=65533). Non-injective (all negatives -> the
    SAME char) and lossy (ord can't recover). A SILENTLY-LOSSY, should-GAP case.
  - Perl's round-trip domain is WIDER than valid Unicode: surrogates (D800..DFFF,
    illegal as scalar values) AND beyond-max (>0x10FFFF, up to ~2^31) BOTH
    round-trip in Perl (`ord(chr(N))==N`) but are NOT valid Characters. So
    `ord∘chr = id` holds on `PerlCodePoint`, but `ValidChar` is a STRICTLY SMALLER
    subset and the coercion ESCAPES it silently. `PerlChar != ValidChar`.
  - Char-count != byte-count: `chr(0x20AC)` (euro) is 1 CHAR / 3 BYTES. The
    `Char<:Str` refinement is in CHARACTER space; the byte representation is
    variable-width (1-4 UTF-8 bytes).
  So the lossless `Int -> ValidChar` domain is `[0, 0x10FFFF] minus surrogates` — a
  strict, NON-CONTIGUOUS subset of Int; outside it, chr either fails silently
  (negatives -> U+FFFD) or produces an invalid-but-round-tripping PerlChar. "Not all
  integers coerce losslessly to valid Characters" — CONFIRMED.
  **[perigrin] ANY integer > Unicode max (0x10FFFF) is invalid — i.e. NEARLY ALL of
  Int (measured):** valid code points = 1,114,112; i64 positive range = ~9.2e18;
  **fraction of positive ints that are valid chars = 1 in ~8.3 TRILLION.** Perl's
  `chr` manufactures a round-tripping PerlChar for ALL of them (`chr(0x7FFF...FFFF)`
  = i64 max returns a defined value that ord round-trips). So the lossless
  Int->ValidChar domain is an ASTRONOMICALLY THIN sliver of Int, with silent failure
  BELOW (negatives->U+FFFD) and silent invalidity ABOVE (>0x10FFFF ~= all of Int).
  A total lossless `coerce(Int, Char)` CANNOT EXIST.
  **CHALK-SPECIFIC COLLISION with the UV bug (019f77d8):** `chr` uses the full
  code-point range up to i64 max, but Chalk models Int as SIGNED i64 — so a
  large-UV codepoint (e.g. 0x8000...0000) reads NEGATIVE in Chalk and would route to
  the U+FFFD (negative) path = a DIFFERENT result than Perl. The signedness bug and
  the chr-domain issue COMPOUND: any chr/codepoint work in Chalk is doubly unsafe
  until UV-vs-IV is modeled.
  **STRENGTHENS the pilot decision to a CORRECTNESS reason (not just scope):** the
  pilot wants `pack("C")` (byte in [0,255], TOTAL, no encoding, no validity leak),
  NOT `chr` (partial, silently-lossy on negatives, UTF-8-encoding, leaks past valid
  Unicode) — `chr` is DISQUALIFIED under GAP-not-miscompile.
- **Ref subtree gaps** beyond the doc's list: `REF` (ref-to-ref, `\\1`),
  `LVALUE` (`\substr(...)`), **`IO`** (filehandles — this IS mod.t test 8's
  file-I/O wall; it's an unmodeled Ref subtype, not "unmodellable"), `FORMAT`
  (legacy). Regex is DUAL-LOCATED (Scalar-child `Regex` AND Ref reftype
  `REGEXP`) — the doc doesn't reconcile this.
- **`OBJECT` reftype (Perl 5.38+ `feature class`)** — the doc's ASCII tree lists
  `Object` as a Ref-subtree leaf beside HashRef, FLATTENING a categorical
  distinction. A native class instance has `reftype()=='OBJECT'` (opaque, no
  underlying storage) — this is CHALK'S ACTUAL object model. It is NOT a peer of
  the structural reftypes; it's the one Ref subtype whose behavior IS the MOP
  (see "OBJECT is where the lattice and MOP coincide" above). Legacy blessed refs
  (`Object ∩ HashRef` intersection types) are the excluded legacy path.
- **Numeric sub-lattice the doc's `Int<:Num` FLATTENS:** Perl's SV has THREE
  numeric slots — IV (signed i64), UV (unsigned u64), NV (double). The doc
  collapses IV+UV into `Int`. **LATENT CORRECTNESS FLAG:** Chalk stamps a UV
  literal (`18446744073709551615` = 2^64-1) as `repr=Int` (i64), and
  `_emit_int_to_str` uses SIGNED ops (`icmp slt i64 .,0`, `sub i64 0,.`) — so a
  UV in an i64 reads as -1 and would render "-1", not the UV. Measured: the eq
  test masks it (both operands fold identically) but the TYPE MODEL is wrong. A
  UV is neither doc-`Int` (i64) nor doc-`Num` (double loses precision > 2^53).
- **NaN / Inf** — Num values breaking ordering axioms (NaN != NaN); the formal
  doc itself flags "NaN" as ambiguously-a-Num. Not placed.
- **vstring** (`v1.2.3`), and the **Code/Glob vs CodeRef/GlobRef** relation
  (`sub{}` vs `\&sub`) — listed as top-level but not developed.

**Discipline this forces (GAP-not-miscompile):** the coerce multimethod is
defined over the DOCUMENTED core lattice; any `coerce`/dispatch involving a
not-yet-latticed type must GAP LOUDLY (residual), never silently mislower. The
UV case is the one place we're ALREADY silently wrong (treated as signed Int) —
file it as a real bug, not just an omission.

## The pilot (proves the architecture — NOT minimum-risk; see [ASSESS])

**Unify `Stringify` into `Coerce`, and make `coerce(Int, Str)` a MOP metaclass
method (subset Perl), compiled to IR and inlined at `Coerce(Int->Str)` lowering.**

**[ASSESS] HIDDEN PREREQUISITE (BLOCKER — the pilot is NOT minimum-risk without
it):** `_emit_int_to_str`'s body writes single ASCII bytes (`store i8`, `add i8
$ch,48`). The SUBSET has NO construct that lowers to a byte-write or char
production (no `chr`, no lvalue `substr` lowering — verified). So writing
`coerce(Int,Str)` in subset Perl REQUIRES first adding a byte-write primitive to
Level-0 (new gen-0 backend surface). This is a SECOND chicken-and-egg (the doc
addressed only the Int-metaclass one). Sequence the pilot: (0) add the byte-write
Level-0 primitive; THEN (1) the lift.

**RESOLUTION — a `ByteBuf` type, NOT a new Str representation, NOT Perl's UTF-8
flag (design decision, 2026-07-19).** Chalk ALREADY HAS a Str value model: a
`(i8* ptr, i64 len)` pair (`%StrPair`, len in `_str_len_table`, G3). The gap is
one-directional: hand-written LLVM can BUILD a Str byte-by-byte (`store i8`), and
the backend can CONSUME one (memcmp, printf %.*s), but the SUBSET LANGUAGE has no
constructive byte-write. The finding is NOT "add a String representation" — it is
"expose a constructive byte-level string builder onto the existing Str model."
Three framings were considered:
- Go `[]byte`/`rune` — representation split (mutable byte-slice vs code point).
- Perl byte-string/Unicode (`SvUTF8`) — ONE storage + an encoding-INTERPRETATION
  bit. The deep, correct, EXPENSIVE model — and already a DEFERRED axis (zhi
  019f51e7 non-ASCII UTF-8; perl5-son is ASCII-encoding by decision).
- A bare byte-buffer — a mutable byte region, no encoding semantics.
DECISION: **`ByteBuf` (the Go `[]byte`/`string` split), NOT the UTF-8 flag.**
`_emit_int_to_str` only ever writes ASCII digits + `-`; it needs BYTES, not code
points, so framings-2 (UTF-8) is wildly over-scoped and correctly deferred.
- `ByteBuf` = a mutable `(ptr, len, cap)` region. Subset ops lowering to Level-0:
  `alloc` (malloc), `set_byte(buf,i,b)` (gep + store i8), `get_byte`, `len`. This
  is `store i8`/`gep`/`add i8` EXPOSED TO THE SUBSET AS A TYPE (not an ad-hoc
  builtin) — exactly the "new gen-0 surface" the prereq (zhi 019f7838) names.
- `coerce(ByteBuf, Str)` freezes the buffer -> immutable `(ptr,len)` Str (cheap:
  same bytes, drop cap, mark immutable). A `coerce` multimethod — fits the design.
- Then subset `coerce(Int,Str)` = build a ByteBuf, write digit bytes (the do-while,
  now in subset code), `coerce(ByteBuf,Str)`. Every op lowers to existing Level-0.
- STRATIFICATION check: `ByteBuf.set_byte` bottoms out in `store i8`/`gep` = the
  SMALL PERMANENT INTRINSIC BASE (the assessment's Level-0 reconciliation). So
  `ByteBuf`'s primitive ops are gen-0 intrinsics (like `add i64`); everything
  built ON ByteBuf (incl. coerce(Int,Str)) is LIFTABLE subset code. `ByteBuf` IS
  the boundary between the permanent intrinsic floor and the liftable metalayer.
- LATTICE: `ByteBuf` (mutable byte region) and `Str` (immutable stringy value) have
  no subtype relation (mutability differs) — related by coercion, not membership.
- FUTURE UTF-8 (framing 2) is NOT foreclosed: when it lands (019f51e7) it becomes
  "a Str carries an ENCODING INTERPRETATION of its bytes" — a property layered ON
  the ptr/len/bytes, added on demand, never now. ByteBuf is encoding-agnostic.

The `$s = chr(48+$d) . $s`-via-Concat encoding is the WRONG lift (it produces
Concat/memcpy chains + loop-carried Str Phis, different IR); the ByteBuf builder
is the right one (a single mutable buffer, matching the hand loop's structure).

**PRIMITIVE ANALYSIS — "is it pack(), chr(), or bit-shifts?" (measured 2026-07-19):**
The missing piece is EXACTLY ONE crossing: **int -> byte-in-a-string**. Everything
else in `_emit_int_to_str` ALREADY LOWERS:
- digit EXTRACTION (`$x % 10`, `$x / 10`, `+`) — Modulo/Divide/Add all lower;
  `my $x=47; $x % 10` PASSES today. So the arithmetic half is done.
- bit ops `>>`/`&` — the IR nodes `RightShift`/`BitAnd` ALREADY EXIST in the loader
  (typed Int); only the trivial LLVM lowering is missing (`lshr`/`ashr`/`and i64`).
  Worth adding anyway (real programs use them) — but they DO NOT SOLVE THIS: bit
  ops stay in INTEGER-land; they never put a byte into a string.
- **"just judicious bit-shifts" is DEFINITIVELY NOT ENOUGH** — `>>`/`&` produce
  integers; `48+$d` is an ASCII INTEGER, not a byte-in-a-string. No arithmetic op
  crosses int->byte-in-string. That crossing IS `store i8` at an index — IRREDUCIBLE
  (can't be composed from `+`/`>>`/`&`); it is the permanent-intrinsic-floor primitive.
- `chr` / `pack("C",N)` — NEITHER exists in Chalk today (no IR node, no lowering;
  the Context.pm "pack" hits are the word "package"). Both CROSS the boundary
  (int -> 1-byte/1-char Str), so either WOULD solve it. `pack` is a whole format
  mini-language (`C`/`N`/`a*`/counts/endian) — lower only `"C"`, GAP the rest.
  `chr(N)`+`.=` is idiomatic but [ASSESS-CORRECTED: Concat IS lowered
  (`_lower_concat`, Context.pm:415/827) — the EARLIER "0 Concat hits" claim was
  FALSE] drags in a loop-carried Str Phi through Concat, which GAPs because Concat
  needs STATICALLY-TRACKED operand lengths (Context.pm:853 — only Constant/Concat Str
  have tracked len; a loop-Phi Str does not), PLUS per-iteration realloc (the wrong
  IR). The conclusion (chr+`.=` is the wrong lift; ByteBuf is right) stands, via the
  tracked-length restriction + realloc, NOT an absent Concat lowering.

**[CORRECTION 2026-07-19, perigrin] `chr(N)` is NOT `coerce(Int, Str)` — they are
DISJOINT functions.** An earlier line said "chr(N) = coerce(Int,Str) of a 1-char"
— WRONG, and the kind of error that would be a SILENT MISCOMPILE if wired:
- `coerce(Int, Str, N)` = STRINGIFY / decimal render: N as a NUMERAL. 65 -> "65"
  (two chars '6','5'). This is `_emit_int_to_str`, `"$N"`, sprintf("%d").
- `chr(N)` = CODE-POINT -> CHARACTER constructor: N as a CODE POINT. 65 -> "A"
  (the one char at code point 65).
MEASURED: `chr(N) eq "$N"` for ZERO values of N in 0..127 (not "many" — NONE;
chr(48)="0" vs "48", chr(53)="5" vs "53", chr(65)="A" vs "65"). They coincide
NOWHERE. `chr` is a CONSTRUCTOR, not a lattice coercion of the Int-as-number.

**Correct decomposition — `coerce(Int,Str)` USES `chr` internally:**
```
coerce(Int,Str, N):            # the WHOLE decimal render = the coercion
  loop: d = N % 10             # extract digit 0-9  (arithmetic, ALREADY lowers)
        byte = chr(d + 48)     # digit -> its CHARACTER  <- THIS is chr (the +48!)
        store byte to buffer   # store i8  <- the missing primitive
        N = N / 10
```
`_emit_int_to_str`'s `add i8 $ch, 48` IS `chr` of a single digit ('0'=48). So
`chr` is a COMPONENT of `coerce(Int,Str)`, not equal to it. And `chr` IS the
int->byte-in-string crossing from the primitive analysis, correctly named.

**So the IRREDUCIBLE primitive is `chr` (codepoint->char) / `store i8` — and
`coerce(Int,Str)` is BUILT ON `chr`, not the same as it.** Correct types:
- `chr(N)` = `coerce(CodePoint, Str)` — the FROM-type is `CodePoint` (an Int
  INTERPRETED as a character index), NOT Int-as-number. Same i64, TWO source types
  by interpretation (a mini-DualVar: the value's type depends on how you read it).
- `pack("C",N)` = byte value N -> 1-BYTE Str, explicitly byte-NOT-codepoint (no
  UTF-8): [ASSESS-CORRECTED: chr(N) eq pack("C",N) for N in 0..255; they DIVERGE at
  **N>=256** — `pack("C",256)` WRAPS to byte 0, `chr(256)` is a 2-byte UTF-8 char.
  The earlier "diverge for N>=128" was FALSE.] Not interchangeable above 255.
  [ASSESS-NOTE: pack("C") achieves TOTALITY by SILENTLY WRAPPING (256->0, -1->255) —
  the SAME silent-lossiness class chr was disqualified for. Irrelevant for the pilot
  (digits 48-57 only, well in [0,255]) but the correctness rationale is applied
  asymmetrically; the honest reason to prefer pack("C")/ByteBuf is the BYTE (not
  codepoint/UTF-8) semantics + the buffer-accumulator IR shape, NOT that it's
  loss-free where chr isn't.]
- `coerce(Int,Str)` (the pilot) = decimal render — its INTERNAL digit->byte step is
  `byte = digit + 48` written via ByteBuf.set_byte (a BYTE write in [0,255], NOT a
  `chr`/codepoint op).

`ByteBuf` remains the right INTERNAL loop primitive (one malloc + N indexed stores
= same IR as the hand loop; chr+`.=` drags in absent Concat + per-iter realloc).
The narrowest true primitive the pilot needs: `chr` of an ASCII digit-char (code
points 48-57) = `store i8 (d+48)`. Bit-ops are a SEPARATE trivial do-anyway win.
Net: the missing primitive is BYTE-write / `store-i8` (NOT chr — chr is
disqualified above), exposed as ByteBuf.set_byte (internal) and/or `pack("C")`
(native byte surface); `coerce(Int,Str)` sits ABOVE it; bit-shifts are orthogonal.

**DECISION (perigrin 2026-07-19): `ByteBuf` is BACKEND-INTERNAL — the
`SoNGraph`/`IRGraph` category, NOT a first-class user-lattice type.** ByteBuf is to
the BACKEND what `SoNGraph` (Chalk's own IR) is generally: a COMPILER-AUTHOR-DEFINED
representation type — a class written in Chalk's OWN source (like `Chalk::IR::Graph`
+ its node classes), NATIVE, class-shaped, reified enough to be a `coerce` ENDPOINT
(`coerce(ByteBuf,Str)` = freeze to an immutable Str; `coerce(SoNGraph,LLVMIR)` =
lower), but NOT declared by a program UNDER compilation (no `class ByteBuf` in a
user's source; never in a user program's inference). Licensed by the CLOSURE
CONDITION (type layer superset of grammar/class layer).

**[perigrin] `SoNGraph` is the BETTER exemplar than `OPTree` — and they are
EQUIVALENTLY "user-defined" (in the COMPILER-AUTHOR sense).** This gives a cleaner
3-tier taxonomy of "who defines a type", which the design should use:
| type | defined by | native? | class-shaped? | coercion liftable? |
|------|-----------|---------|---------------|--------------------|
| Int, List | nobody — BOOTSTRAP primitive (no written class) | native | Int y / List n | n/a (the floor) |
| OPTree | libperl (FOREIGN C struct) | FOREIGN | struct-ish | NO (no subset FFI) |
| SoNGraph, ByteBuf | the COMPILER AUTHOR, in Chalk source | native | yes | YES |
| Point | the LANGUAGE USER, in a program | native | yes | yes |
So `ByteBuf` belongs with `SoNGraph` (compiler-author-defined, native, liftable),
NOT with `OPTree` (foreign, non-liftable). Using `SoNGraph` as the exemplar removes
the awkward "caveat where ByteBuf is better than OPTree" — with SoNGraph there is NO
caveat, they are straightforwardly the same tier.

Concretely for the pilot:
- `ByteBuf` primitive ops (`alloc`/`set_byte`/`get_byte`/`len`) are GEN-0 INTRINSICS
  (bottom out in malloc/store-i8/gep = the permanent intrinsic floor) — never lifted.
- What is BUILT ON it (`coerce(Int,Str)`, subset code) is LIFTABLE (native floor,
  unlike OPTree's foreign floor — the NATIVE-vs-FOREIGN axis determines liftability,
  and both ByteBuf and SoNGraph are on the native/liftable side).
- DEMAND-DRIVEN: keep it a backend intrinsic; PROMOTE to a lattice-placed type ONLY
  if a user-facing consumer ever pulls.

Why it is still the right pilot:
- Small (a do-while + arithmetic + the new byte primitive).
- Has a BEHAVIORAL ORACLE: corpus S9-S12 (Stringify interpolation) + L6d/L6e
  (int-in-eq) `behavior` blocks (stdout/exit). **[ASSESS] The GATE is
  BEHAVIOR-IDENTICAL, not byte-identical** — a graph-inlined+scheduled method
  produces different SSA naming/block order than today's textual emitter, AND the
  advertised GVN win (two Stringify -> one) CHANGES the output by design, so
  byte-identity is both unachievable and self-defeating. **[ASSESS] The S9-S12
  ir-blocks are INVALIDATED by the `Stringify`-node deletion** (corpus dual
  contract: ir-blocks are lowering spec AND optimizer contract) — so the oracle is
  the BEHAVIOR blocks only, plus a PLANNED, REVIEWED ir-block rewrite (not a fixed
  external check).
- Success proves: (a) a metalayer method can be self-compiled, (b) inlined as IR,
  (c) optimized IN-GRAPH via CROSS-SITE unification, (d) no BEHAVIOR change, (e)
  DELETES the `Stringify` node type.
  **[ASSESS3 G6 — restate (c).** Two `Stringify(Int)` of the SAME value ALREADY GVN
  to one node TODAY (Chalk's IR is hash-consed; the backend caches lowering by node
  id, Context.pm:~932) — so "the current LLVM version cannot" was FALSE for the
  same-node case. The REAL win the pilot unlocks is CROSS-SITE: a `Stringify` USE and
  an eq-operand stringification of the same value currently call `_emit_int_to_str`
  DIRECTLY at two sites (`_str_compare_operand`, printf-%d) with NO shared node, so
  they cannot merge; unifying them behind ONE `Coerce` node lets them GVN. For this to
  hold, the malloc+i8-store+loop BODY must be spliced at LOWERING time (not into the
  pre-optimizer graph) — else the effectful copies can't hash-cons and the merge is
  lost. Pin the splice to lowering.]**

**FULL PILOT SEQUENCE (2nd-assessment F10/F11 named the unsequenced deps; the
2-step "(0) ByteBuf -> (1) lift" was too short):**
1. Consolidate the SIX scattered coercion sites — `_lower_coerce`,
   `_lower_stringify`, `_str_compare_operand`, `_coerce_ref_to_num` (Context.pm:1627
   — re-emitting sitofp + @chalk_str_to_num, the fast/slow divergence the Graal
   critique warns of), AND **[ASSESS3 G2] the `_lower_print` Int arm (Context.pm:~5648,
   printf `%d` of a TRUNCATED i32) and the Int return epilogue (LLVM.pm:~1291, `trunc
   i64 -> i32`)** — behind ONE `coerce(From,To)` VTABLE lookup (the MECHANISM above).
   **These last two are int->str renderers that DIVERGE from `_emit_int_to_str` TODAY:
   `print 4294967296` -> "0" (i32-truncated printf) but `"$n"` -> "4294967296" (full
   i64) — a LIVE wrong-answer (real perl prints 4294967296; the behavior oracle uses
   small ints so the gate misses it). Consolidating them onto `coerce(Int,Str)` FIXES
   the truncation as a side effect.** Handle UV/signed AND the INT64_MIN `0 - val`
   overflow edge (Context.pm:~947) while there. (This step is pure refactor — no
   self-hosting yet; validates the vtable-dispatch mechanism against today's gen-0
   coderefs.)
2. **[F10] Add the `ByteBuf` byte-write intrinsics** (alloc/set_byte/get_byte/len ->
   malloc/store-i8/gep) — the permanent-floor primitive the subset lacks.
3. **[F10] PROVE THE INLINER on a loop+effect callee FIRST.** `_lower_call_direct` +
   F5/F8 arg-binding is verified, BUT the F-corpus has NO loop-bearing / store-
   effecting callee — the inliner substitutes only a callee's Return-VALUE subgraph,
   requires exactly one Return, and has NEVER run on a body like `coerce(Int,Str)` (a
   do-while with loop Phis writing bytes through ByteBuf effects). Prove (or GAP) this
   shape on a MINIMAL loop+effect callee before the real lift. [This is the pilot's
   biggest UNPROVEN mechanism.]
4. **[ASSESS3 G3 — SNIPPET AVAILABILITY (was an unnamed prereq).** Step 3's inliner
   resolves callees against the LOADED GRAPH SET of ONE compilation payload
   (`_resolve_direct_calls`, JSON.pm:~570). Nothing persists a compiled
   metaclass-method graph ACROSS compilations or splices it into an unrelated
   program's `Coerce(Int->Str)` lowering. The gen-1 vtable cell must hold a graph that
   is present in EVERY consumer compilation. Define the snippet-library mechanism:
   serialize the compiled `coerce(Int,Str)` graph (JSON) and INJECT it into the loaded
   graph set of any compilation whose lowering hits a populated vtable cell (Graal has
   exactly this snippet cache). Without this, step 5 can only demonstrate the lift
   inside one hand-assembled payload — a demo, not the mechanism.]**
5. Write `coerce(Int,Str)` as a subset method (do-while + ByteBuf), REGISTER it in the
   vtable. **[ASSESS3 G4: the stated `sub Str (Int $v){...}` typed-signature form is a
   MEASURED compile error in gen-0 perl 5.42 ("signature parameter must start with
   $/@/%") and has no Earley production — so pick the REGISTRATION mechanism (an
   explicit `Type->_populate(Int, Str, \&coerce_int_str)` call, or an attribute); the
   typed-sig syntax is a SEPARATE, deferrable grammar feature, NOT a pilot prereq.]**
   Compile through the Level-0 backend, make it available via step 4, inline it (step
   3's mechanism), prove BEHAVIOR-IDENTICAL to the gen-0 `_emit_int_to_str` (kept as
   seed) via the S9-S12/L6d/L6e behavior blocks; rewrite the S9-S12 ir-blocks (the
   Stringify-node deletion invalidates them).

**[F11] ByteBuf TIER (resolve the strain): ByteBuf is a compiler-author-defined TYPE
(SoNGraph tier) but its PRIMITIVE OPS (set_byte etc.) are GEN-0 INTRINSICS with
backend-magic bodies (NOT source-written — the absence of a subset byte-write is why
ByteBuf exists). So: ByteBuf-the-TYPE is SoNGraph-tier (native, its coerce(ByteBuf,
Str) is liftable); ByteBuf's PRIMITIVE OPS are the intrinsic FLOOR. Not circular
(floor + liftable-superstructure is coherent) but they are DIFFERENT tiers — do not
say "same tier as SoNGraph, no caveat" AND "the intrinsic-floor boundary" without
this split.**

## Prerequisites / dependencies

1. **Type lattice as a first-class MOP structure** — metaclasses
   `Scalar/Str/Num/Int/Bool/Undef/Ref/...` with real ancestor relations,
   replacing/subsuming the ad-hoc string reprs + `_REPR_RANK`. This also cleans
   up repr inference (join = lattice LUB). PREREQUISITE.
2. **MOP migration landed** — a RUNTIME MOP is a strict superset of the
   compile-time MOP, so it can't be designed against an incomplete one. The MOP
   migration is ~2/3 done and PARKED near-capstone (backchannel, `cfg_state()`,
   Target::C entry — see the CLAUDE.md Plan Discipline section). Confirm adding a
   runtime phase doesn't depend on the parked pieces before this becomes work.
3. **Optimizer/scheduler in shape** — snippet IR flows back through GVN/DCE +
   the scheduler; the scheduler's back-half is done, front-half deferred to
   B::SoN (memory `scheduler_aegraph_backhalf_now_fronthalf_phase4`).

## OPERATIVE STRATEGY: demand-driven, north star = self-hosting lib/ (perigrin)

This is NOT a "go build the runtime MOP" project. The runtime MOP gets built ONE
COERCION AT A TIME, PULLED by the corpus + t/* tests + lib/, never speculatively:

1. **Clean up Level-0 and integrate it with the existing MOP.** Level-0 is already
   implemented (backend lowers Add/If/Loop/Subscript → add/br/gep) but IMPLICIT —
   not expressed AS the MOP's primitive metaclass operations. The cleanup makes
   it explicit: the machine arithmetic/memory/control primitives become the named
   grounded base OF the MOP, so the metacircle has a named floor, not an ad-hoc
   backend convention.
2. **Level-1-and-up are lifted ON DEMAND, as runtime ops, driven by the actual
   tests.** A `coerce(A,B)` gets unified/lifted into a proper self-compiled method
   WHEN a corpus case / t-file / lib/ method needs it — the runtime grows exactly
   as fast as the tests demand, and no faster. Not a big-bang runtime library.
3. **NORTH STAR: finish self-hosting compilation of `lib/`.** This whole arc (the
   t/-drains, the corpus, this runtime-MOP design) serves that. Every runtime op
   lifted is a step toward lib/ compiling through Chalk (capstone zhi 019f5da9 +
   019eaa51).

**This recontextualizes the existing task list without changing it:**
- `019f7771` (float subsystem) = `coerce(Num,Str)` + `coerce(Str,Num)` refinement,
  LIFTED when num.t is drained. Not "a runtime library to build."
- `019f77d8` (UV signedness) = correctness INSIDE `coerce(Int,Str)`, handled AT
  the pilot lift (not a separate patch).
- `chalk_str_to_num` = `coerce(Str,Num)`, already exists (gen-0); unified during
  the pilot.
- lib/ capstone (`019f5da9`, real lib/ methods fail at NO-REPR) is downstream —
  it needs the type-lattice-as-MOP structure this design motivates.

Same work, correctly named, demand-ordered.

## Open questions to resolve before implementation

- Snippet lowering PHASE ORDERING (inline too early loses high-level facts for
  escape analysis; too late misses cross-op sharing). Small subset => probably 2
  tiers (abstract, lowered) suffices, but needs a design.
- Inline-vs-call CUT heuristic (intrinsify the small hot ops where GVN/DCE pay;
  CALL the big opaque ones — float-format, regex — where the optimizer gains
  nothing from seeing inside).
- Source-vs-target-vs-multimethod for the OPEN/overload case, and the ambiguity
  precedence rule there.
