# Handoff: split `Chalk::IR::Value` out of `Chalk::IR::Node`

**Date:** 2026-08-21
**Status:** DESIGNED, measured, not built. No code written for this yet.
**Input doc:** `2026-08-21-type-vs-representation-seams.md` (read it first --
this plan is the resolution of the architectural finding at its end).

---

## The problem in one line

`field $representation = undef` sits on the BASE node class, so `undef` means
three different things and no consumer can tell them apart:

1. this node produces no value (a control node -- correct, permanent)
2. inference has not run yet (temporary)
3. inference ran and failed (a bug)

Most findings in the seams doc are downstream of that conflation. It is the same
absence-vs-value defect as `Unknown`, on the other axis.

## The design

    Chalk::IR::Node                    control: Start Return If Loop Region
    └── Chalk::IR::Value               field $type :reader
        ├── BinOp      (37 subclasses)
        ├── UnaryOp     (8)
        ├── Access      (5)
        ├── Aggregate   (4)
        ├── Regex       (2)
        └── direct value nodes

**The predicate is `$node isa Chalk::IR::Value`.**

NOT `->can('type')`. perigrin, correcting my earlier suggestion: `can` is
duck-typing over a NAME, so any class defining a `type` method for unrelated
reasons answers true, and guarding that needs a test whose only job is patching
a weak predicate. `isa` asks the actual question -- "is this a value" -- and
`feature class` gives the infix form directly:

    if ($node isa Chalk::IR::Value) { ... }

**Consequence, and it is the point:** `isa` is CLOSED against the hierarchy.
There is no opt-in-by-defining-a-method escape hatch, so a value node nobody
reparents fails by not being recognised as a value -- loud -- rather than by
carrying a silently untyped field.

Once split, `$type` is never `undef`. It holds a Chalk type or `Unknown`, and
`Unknown` finally has somewhere to live as a real lattice value because the
"not applicable" case moved out of the field entirely.

## Why this shape (prior art)

| | mechanism | can you ask a control node for its type? |
|---|---|---|
| LLVM | `void` is a real type | yes -- answers `void` |
| C2 | `Type::CONTROL` in the lattice | yes -- answers CONTROL |
| Graal | `ValueNode` base class | **no -- no such method** |
| Chalk today | none | yes -- answers `undef`, indistinguishable from a bug |

Graal's is the shape this follows. perigrin: *this is where I wish Perl core had
Roles again (like Fixed vs Floating which are perfect Role shapes).* Correct --
Fixed/Floating and Value/Control are orthogonal, and Java interfaces compose them
where single inheritance cannot. Chalk already works around this for the other
axes: `is_fixed`, `staleness_kind`, `identity_kind` are METHODS, not base
classes. The hierarchy slot is spent on shape (`BinOp`/`UnaryOp`/...), so `Value`
must go ABOVE those five, not beside them.

## Classification

**Control -- stay on `Node`:**
Start, Return, If, Loop, Region, MemStart, Proj, Print, Unwind, VarDecl, TryCatch

**Value -- move under `Value`:**
Constant, Phi, TernaryExpr, Coerce, Call, ExpressionList, PostfixDeref,
StructFieldAccess, StructRef, RegexCapture, EnvRead, BacktickExpr, AnonSub,
ListAssign, CompoundAssign
plus the five base classes, which carry 56 subclasses with them.

**RESOLVED by measurement -- the assigns are BOTH:**

`Assign` and `CompoundAssign` are both in `%STATEMENT_EFFECT_OPS`
(NodeFactory.pm:164-167) AND `Assign` already inherits `BinOp`, a value class.
`Serialize/JSON.pm:1517`: *"An Assign's result IS the stored value, so its repr
is the..."*. So they are effectful AND value-producing -- perl's `$x = $y = 5`.

This is exactly the Fixed/Floating vs Value/Control orthogonality: `is_fixed`
answers the effect question, `isa Value` answers the value question, and they
are independent. No conflict. `CompoundAssign` and `ListAssign` are VALUES that
are also statements.

The same file already states the axes are separate (:175): *"allocations are
value-producing and are not control-threaded by the Block fixup, which is a
different question."*

**STILL OPEN -- perigrin's call, do not guess:**

- `Unwind` (`die`) -- never returns, so `None` (the bottom type) is the
  principled answer. But it may be cleaner as control.

## Enforcement: the loader THROWS on an untyped Value node

perigrin: update the loader to throw if it encounters an untyped Value node.

That is what makes "fully typed" an INVARIANT rather than a convention. Without
it the split is documentation.

**Sequencing matters:** the loader cannot throw until the producer emits full
types, or every program dies. So this lands AFTER the producer step, or behind
a transitional flag. The ~35 corpus gaps are precisely the programs that would
throw, which makes them the work queue.

The throw belongs at the END of `from_json`, after all propagation passes have
run -- that is the point where remaining `undef` means inference genuinely
failed rather than "not yet reached". Message must name the NODE and the
OPERATION, not a phase: the seams doc records `_require_repr` blaming
TypeInference for a scoping bug three levels away, and this must not repeat it.

## Sizing -- MEASURED, and much smaller than it first looked

Corpus ir-blocks: **239 blocks, 1893 value lines, 1680 (89%) already typed.**

Of the 213 untyped lines:

| op | n | verdict |
|---|---|---|
| `Proj` | 94 | CONTROL -- its own ABOUTME says "Selects one **control** output ... from a multi-output node such as If". Correctly blank. |
| `MOP` | 45 | metaobject reference, almost certainly not a lattice value |
| `If` | 39 | control -- correctly blank |
| **real gaps** | **~35** | Phi 13, PadAccess 6, Unwind 4, Concat 3, Subscript 3, Call 2, CompoundAssign 2, TernaryExpr 1, Ref 1 |

So the corpus is **~35 lines from fully typed, not 213.** I first reported 239
blocks as "the migration workload" -- wrong: I counted blocks asserting SHAPE and
assumed shape meant representation. It does not. Retracted.

**The corpus needs almost no rewriting.** perigrin predicted this and it
measures out: ir-blocks contain **zero LLVM types**. ~1650 Chalk-type
annotations (`:Int` 825, `:Str` 667, `:Bool` 123, `:Num` 31, `:Undef` 7) against
~123 LLVM mentions that are ALL prose or false positives (`$double` is a field
name in classes.md; "native i64 subtract" is explanatory text). The corpus is
already the spec this architecture calls for.

`:Unknown` appears **0 times**, which is itself the finding from the seams doc:
nothing ever produces it.

## What the test suite is worth here

- **221 stdout assertions = a genuine semantics net.** Preserved by any
  correct refactor. Run constantly.
- **239 ir-blocks = the spec**, not the workload. They stay; ~35 lines gain types.
- **9 repr-string assertions** across 14 of 225 bootstrap tests. Trivial.

perigrin's premise -- "our existing tests become safe refactor tests" -- holds,
with the correction that the behavior leg is the net and the shape leg is the
specification.

## Build order

1. **`Chalk::IR::Value` + reparent.** Mechanical once classification is settled.
   No behavior change: `$type` starts undef-equivalent everywhere.
2. **A corpus check.** For each ir-block line, if the node class
   `isa Chalk::IR::Value`, assert a `:Type` annotation. No exclusion list needed
   -- that is the whole point of the structural predicate. Goes RED for ~35 lines.
3. **Close the ~35.** Mostly `Phi` (a join that should already work) and
   `PadAccess` (finding 3 -- cross-sub lexicals, filed as H13).
4. **Then** rename `representation` -> `type` at the ~220 remaining sites, and
   `$type` becomes non-nullable.

Do NOT reorder 4 earlier: it is a large mechanical diff across code that
findings 0a and 2 are about to change.

## Not in scope here

The lowering rewrite phase (`Node(Int)` -> `Node(i64)`), its machine-level
coercion table with lossiness verdicts, and findings 0a/0b. Those are the seams
doc's content and depend on this split landing first.
