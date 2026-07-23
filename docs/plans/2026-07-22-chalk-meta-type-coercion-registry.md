# Chalk::Meta::Type — Type + Coercion metaobjects (NORTH STAR, deferred to N>=3)

ABOUTME: Captured architecture for a MOP factory/registry minting Chalk::Type +
ABOUTME: Chalk::Coercion; DEFERRED until >=3 real Type->Type coercions share it.

Date: 2026-07-22
Status: CAPTURED ARCHITECTURE (deferred) — not a milestone yet. The immediate
work is 019f82f1 (a concrete Coerce insertion), NOT this MOP.
Assessed twice (adversarial + ponytail), TWICE (horizontal draft, then vertical
triplet draft). Both drafts' milestone-1 build was found premature. This file now
records the architecture as a north star with an explicit trigger, per those
reviews.

## The corrected model (perigrin, 2026-07-22) — TWO layers, cleanly separated

**Coercion is ALWAYS Type -> Type. Opcodes are mapped to types by B::SoN
UPSTREAM. These are different layers:**

- **TYPING layer** (B::SoN + OpMap): `perl-opcode -> node-op -> Chalk::Type`.
  OpMap's `add => [2,'Add',1,0]` ASSIGNS the op its node/type; `set_representation`
  stamps it (Chalk/IR/Serialize/JSON.pm). This is type ASSIGNMENT, not coercion.
  Opcodes live ONLY here. (Correcting a prior error in this thread: OpMap is NOT
  "the declarative half of a coercion registry" — it is the typing table.)
- **COERCION layer** (`Chalk::Coercion`): ALWAYS `Chalk::Type -> Chalk::Type`,
  never sees an opcode. Verified: the Coerce node carries only from_repr/to_repr
  (Node/Coerce.pm:16-20); `_lower_coerce` dispatches purely on from/to repr
  (Context.pm:1022-1039). A Coercion is a GRAPH-BUILDING rule (its apply inserts a
  Coerce node); backend LOWERING of that node stays the backend's job, a separate
  arrow.

Consequence: there is NO "import coercion." A prior draft's "import triplet"
(add->Add) was proof-by-vacuity — neither end is a Chalk::Type, so it bypasses
the type registry entirely (adversarial 2026-07-22). Deleted.

## The MOP shape (correct, once framed as above)

`Chalk::Meta::Type` = a factory/registry that mints two peer metaobjects:
- `Chalk::Type` — a value type (Int, Num, Str, Scalar, classes, List). `add_type`/`get_type`.
- `Chalk::Coercion` — a `Chalk::Type -> Chalk::Type` graph-building rule. `add_coercion`/`get_coercion`.

No union `from` (always a Type), no opcode leakage. This is the right architecture.

## WHY IT IS DEFERRED (both reviews, independently)

Milestone-1-building it now is premature — TWO independent adversarial passes
reached this:
- **Ponytail:** the only ready consumer (the divide bridge) closes with ZERO new
  classes via `factory->make('Coerce', from_repr=>'Int', to_repr=>'Num')` (the
  existing factory + node). A registry with one occupant is a factory for one
  product.
- **Adversarial:** `Chalk::Type('Int')` is INERT in milestone 1 — nothing consumes
  a Type OBJECT. Coerce carries strings (Coerce.pm:16-20), TypedInvariant compares
  strings, the loader maps strings, the `<:` relation is deferred. `get_type('Int')`
  is a string with a wrapper; string-keyed `get_coercion('Int','Num')` is
  functionally identical minus one class.

So `Chalk::Type` earns itself only when it carries BEHAVIOR (the `<:` lattice
relation, coercion-path search, class/List membership) that strings can't — and
`Chalk::Coercion` earns a shared home only at multiple consumers.

## THE TRIGGER (when to build this)

Build `Chalk::Meta::Type` when **N >= 3 real Type->Type coercions** want a common
home AND at least one needs Type BEHAVIOR (not just a string key). The three
concrete pending consumers:
1. `Coerce(Int, Num)` — the divide bridge (019f82f1). [N=1 today]
2. `Coerce(Str, Num)` — the numify-warning chain (runtime-mop-pilot 019f8193).
3. `Coerce(Int, Num)` / etc. for `%` (modulo) and other Num-input arith.
When those exist as separate real insertions AND you need to SEARCH a coercion
path (transitive Int->Num->Str via the lattice), the string-keyed lookups stop
sufficing and the metaobjects pay for themselves. Not before.

## IMMEDIATE WORK (this is NOT the MOP)

Land 019f82f1 as a concrete producer-side Coerce insertion (verified scope in that
issue): build-time wrap Int operands of Divide in a Coerce node via the existing
factory + add the missing Coerce arm to perl5-son SoN/Serialize/JSON.pm
`_extract_fields` (it currently DROPS from_repr/to_repr on the wire) + ensure the
Num stamp rides the wire (else the backend double-sitofps). ~40-60 lines cross-repo,
zero new classes. Flips the divide invariant leg -> un-worklists the case -> floor
rises. This is consumer #1; the MOP waits for #2 and #3.

## do/while

Independent throughout — a control-structural import handler (opcode->graph, the
TYPING layer), not a coercion. Its own doc: 2026-07-21-do-while-as-import-coercion.md.

## Evidence base (verified 2026-07-21/22)

- Coercion keys on from_repr/to_repr (types), never opcodes: Node/Coerce.pm:16-20;
  Context.pm:1022-1039 (Int->Num sitofp :1028).
- Divide invariant accepts a Coerce bridge; consumer pre-wired: TypedInvariant.pm:22,
  :139-152; well-typed-graph.t H2-6:106 / H2-7:131; behavior+shape already green
  (commit 6dd73cc7).
- Wire format drops Coerce reprs (the gap): perl5-son SoN/Serialize/JSON.pm
  _extract_fields ~:31-108 has NO Coerce arm (verified).
- Repr is flat strings, no rank: %STAMP_TO_REPR (Chalk/IR/Serialize/JSON.pm), NOT
  `_REPR_RANK` (does not exist); lattice in perl5-son SoN/IR/Stamp.pm.
- OpMap = typing table (opcode->node-op), not coercion: lib/SoN/FromOptree/OpMap.pm:24,44,61.
- Both reviews (premature-metaobjects / inert-Type / vacuous-import-triplet):
  ponytail + adversarial, 2026-07-22.
