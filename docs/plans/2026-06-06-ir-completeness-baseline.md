# IR-Completeness Baseline: Current IR vs. Typed-IR Contract

**Date:** 2026-06-06
**Phase:** 3b — IR-completeness gap-map + measurement
**Status:** BASELINE — the honest measurement of how far the current IR is from
the typed-IR contract (docs/architecture/typed-ir-representation.md). This is
the 3c work-list.

## Purpose

The typed-IR contract (§§1-4 of the representation doc) specifies three things
a node must carry to lower runtime-free:

1. **Latent type** (`Int/Num/Str/Ref/...`) — from TypeInference and the formal type system.
2. **Representation** — the machine-level shape of the value at rest (`i64`, `double`,
   `ptr`, `Scalar`), carried ON the graph from value creation.
3. **Coercion explicitness** — every implicit Perl coercion materialized as an
   explicit `Coerce` node.

This document measures what the current IR (as produced by the parser's
SemanticAction semiring, driven by TypeInference and post-processed by
StructPromotion) provides against each requirement.

---

## Contract requirement 1: Latent type on-graph

**Requirement:** Each produced value has a latent type (`Int`, `Num`, `Str`,
`Ref`, `Scalar`, ...) carried as an on-graph node property.

**What TypeInference provides today:**
TypeInference is a parse-time semiring that annotates `Context` objects with
type tags during Earley parsing. It propagates `type` tags through the grammar
rules: scan-time annotations (`type=Int` for integer literals, `type=Str` for
string literals, `type=Scalar` for variables, etc.) and complete-time
annotations (`BinaryExpr`, `CallExpression`, etc.).

**Gap — what TypeInference does NOT do:**
TypeInference produces parse-time `Context` tags that flow through the grammar.
These tags are CONSUMED by SemanticAction to gate codegen decisions (e.g. whether
to emit a typed node). They are NOT persisted to the graph — the IR nodes
themselves (`Chalk::IR::Node` and all subclasses) carry no `latent_type` field.

After the SemanticAction fires and the node is placed in the graph, the type
information is gone. A `Constant(1)` node in the graph cannot be queried for its
latent type; `$node->latent_type()` does not exist.

**Contract verdict:** PARTIAL — latent types exist at parse time in the Context
but are NOT on the graph. 3c must add a `latent_type` field to Node (or a
companion annotation table).

---

## Contract requirement 2: Representation on-graph from value creation

**Requirement:** Each produced value carries a representation (`Int`, `Num`,
`Str`, `Ptr`, `Scalar`) as an on-graph decoration, set at node-creation time
by the IR builder.

**What the IR provides today:**
`Chalk::IR::Node` (Node.pm:42-52) carries a `$representation` field that:
- Is readable via `representation()`.
- Is settable post-construction via `set_representation($repr)`.
- Defaults to `undef` (not yet assigned).
- Is EXCLUDED from `content_hash` (correct — per §1a of the design doc).

The field was added in Phase 3a (commit `5363dfde`). The `Coerce` node
(`Node/Coerce.pm`) carries `from_repr`/`to_repr` as content-hashed fields.

**Gap — what the IR builder (SemanticAction / Actions.pm) does NOT do:**
While the `representation` field EXISTS on the node, the IR builder
(SemanticAction + Actions.pm, the production path that converts parsed Perl into
the graph) NEVER calls `set_representation()` on any node it creates. The
field exists but is always `undef` for every parser-produced node.

Evidence: `grep -rn set_representation lib/` returns zero hits outside of:
  - `lib/Chalk/IR/Node.pm` (the setter definition itself)
  - `lib/Chalk/IR/Target/LLVM.pm` (test graphs hand-authored in t/)
  - `t/bootstrap/ir/` test files (hand-authored graphs only)

Every representation-tagged node in the system today is hand-authored in a test.
The parser produces nodes with `representation = undef`.

**StructPromotion (lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm):**
StructPromotion is a post-parse optimizer that detects hashes with known key sets
and rewrites them to `StructRef`/`StructFieldAccess` nodes for the C/XS backend.
It uses field_usage tracking and escape analysis. It does NOT call
`set_representation()` on any node. It adds new node types (`StructRef`,
`StructFieldAccess`) but does not annotate their representation.

Representation inference in the C backend happens LATE, during `Target::C`
emission (via `StructPromotion` schema analysis), not on the graph. This is the
"late, backend-specific" model the typed-IR doc says must move on-graph.

**Contract verdict:** INFRASTRUCTURE EXISTS, NO PRODUCER — the `representation`
field is on the node model and works (tested). The gap is that no code path sets
it for parser-produced nodes. 3c must wire `set_representation()` calls into
the IR builder for the provably-typed cases:
  - Integer literals → `Int`
  - Float literals → `Num`
  - String literals → `Str`
  - Method/sub parameters with inferred types → their inferred type
  - Return of an arithmetic op on Int inputs → `Int`

---

## Contract requirement 3: Coercion explicitness

**Requirement:** Every implicit Perl coercion is materialized as an explicit
`Coerce` node on the edge between producer and consumer.

**What the IR provides today:**
`Chalk::IR::Node::Coerce` exists (Phase 3a, commit `3a60cad6`) with:
- `from_repr` / `to_repr` as content-hashed fields.
- Correct hash-consing: two consumers of the same `Coerce[Str→Num](x)` share
  one node.
- `Chalk::IR::Graph::TypedInvariant` can check for unbridged representation
  mismatches (missing Coerce nodes).

**Gap — what the IR builder does NOT do:**
The IR builder (Actions.pm / SemanticAction) inserts ZERO `Coerce` nodes. Perl's
implicit coercions (e.g. `"42" + 1` needing `Str→Num` on `"42"`) are not
materialized in the graph. Every parser-produced graph has no `Coerce` nodes.

Concretely, `grep -rn "Coerce" lib/Chalk/Bootstrap/` returns hits only in:
- `lib/Chalk/IR/Target/LLVM.pm` (the lowering pass that handles Coerce — but
  only in test-authored graphs)

The production parse path has no code to insert Coerce nodes.

**Contract verdict:** INFRASTRUCTURE EXISTS, NO PRODUCER — the `Coerce` node
model is complete and tested. The production IR builder never inserts one.
3c must add Coerce insertion to the IR builder for all implicit coercion sites:
  - Arithmetic ops on Str-typed operands (numeric context coerces `Str→Num`)
  - String concatenation on Num-typed operands (`Num→Str`)
  - Boolean context on non-Bool values (`→Bool`)

---

## Summary: current IR vs. typed-IR contract

| Contract requirement      | Field/infra on Node? | Production IR builder uses it? | 3c task |
|--------------------------|----------------------|--------------------------------|---------|
| Latent type on-graph      | No field exists      | No                             | Add `latent_type` field; wire TypeInference output to node creation |
| Representation on-graph   | ✅ `$representation` field + setter | No — always `undef` for parsed nodes | Wire `set_representation()` in Actions.pm for provably-typed literals and propagated types |
| Coerce explicitness       | ✅ `Coerce` node + `TypedInvariant` checker | No — zero Coerce nodes in parsed graphs | Add Coerce insertion in Actions.pm at implicit coercion sites |

**Net result:** The IR has the representation and Coerce node infrastructure
from Phase 3a. The gap is entirely in the IR BUILDER (SemanticAction / Actions.pm)
which does not call `set_representation()` or insert `Coerce` nodes for any
parser-produced value. Phase 3c is the builder-side work: plumb representation
and coercions into the production path.

---

## Gap-map tally (Phase 3b output)

Over the computation slice (groups A, C, D, K, L + literal arithmetic):

| Verdict     | Count | Details |
|-------------|-------|---------|
| L-GREEN     | 3     | Literal arithmetic: `return N+M`, `return N-M`, `return N*M` (fully runtime-free, libperl-free, lli==perl) |
| GAP         | 24    | All variable/control/logical idioms |
| MISCOMPILE  | 0     | None found |

**GAP breakdown by category:**
- `representation-missing` (24): all 24 GAP entries fall here. The specific sub-reasons:
  - **VarDecl/PadAccess (A1-A4, C1-C2, K1-K2):** lexical variables have no
    representation; alloca+store/load model absent from IR.
  - **Array/Hash (A2-A3, C4-C5):** Perl arrays/hashes have no runtime-free
    representation; require `Scalar` (SV*).
  - **FieldAccess (A5):** object fields require struct layout (offset), not in IR.
  - **Control flow / Phi (D1-D8):** If/Phi nodes carry no representation;
    condition representation (Bool/Int) absent; Phi join values untyped.
  - **String operations (C3):** Concat/.= operates on Str representation not
    yet lowerable runtime-free.
  - **Logical operators (L1-L4):** And/Or/DefinedOr/Not on Scalar-typed parameters.

**L-GREEN idioms — generated .ll (one example, arith-add):**
```llvm
; Generated by Chalk::IR::Target::LLVM — SoN->LLVM lowering (Phase 3a/3b)
; SoN graph: Return(Add(Constant(Int), Constant(Int))) with Int representation

@fmt = private unnamed_addr constant [4 x i8] c"%d\0A\00", align 1

declare i32 @printf(i8* nocapture readonly, ...)

define i32 @main() {
entry:
  %tmp_1 = add i64 0, 1          ; Constant(1, repr=Int -> i64)
  %tmp_2 = add i64 0, 2          ; Constant(2, repr=Int -> i64)
  %tmp_3 = add i64 %tmp_1, %tmp_2  ; Add(repr=Int) -> i64 add
  %result_i32 = trunc i64 %tmp_3 to i32
  %fmt_ptr = getelementptr inbounds [4 x i8], [4 x i8]* @fmt, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %fmt_ptr, i32 %result_i32)
  ret i32 0
}
```
`lli` output: `3` — matches perl oracle `3`. No Perl_/SV/libperl anywhere.

---

## What 3c must do (the concrete work-list)

1. **Add `latent_type` to `Chalk::IR::Node`** (out-of-hash, like `representation`).
   Wire TypeInference's `type` tag output to `$node->set_latent_type()` in
   SemanticAction's node-creation path.

2. **Wire `set_representation()` into Actions.pm** for:
   - Integer literal constants → `Int`
   - Float literal constants → `Num`
   - String literal constants → `Str`
   - Arithmetic result nodes Add/Sub/Mul on Int inputs → `Int` propagation.
     NOTE (3b gate finding): Div is NOT Int — Perl `/` is float division
     (`3/4 == 0.75`), so `Int / Int` yields `Num` and requires Coerce(Int→Num)
     operands + `fdiv`. Modulo `%` follows the right operand's sign
     (`-7 % 3 == 2`, unlike LLVM `srem`) and needs sign-correction. Both are
     recorded as GAP in the gap-map (arith-div, arith-mod); do NOT lower them
     as bare `sdiv`/`srem` i64 (that miscompiles vs perl).
   - Method parameter types (when TypeInference has inferred them) → their type

3. **Wire Coerce insertion into Actions.pm** for:
   - Numeric context on Str operands (e.g. `"42" + 1`)
   - String context on Num operands (e.g. `"$n"` interpolation)
   - Boolean context on non-Bool values (for if-condition, loop-condition)

4. **Extend TypedInvariant** to check latent-type consistency (not just
   representation consistency) once latent_type is on-graph.

5. **Extend LLVM.pm** to handle VarDecl (as alloca+store/load) once
   representation is wired for lexical variables — this unlocks A1-A4 and K1-K2.

The Scalar-GAP coverage metric (§4a) will automatically track progress: as
more idioms get representation, their L-corner coverage rises from 0% toward
100%, and their verdict migrates from GAP to L-GREEN.
