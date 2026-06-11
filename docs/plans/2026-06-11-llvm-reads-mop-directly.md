# LLVM Backend Reads the MOP Directly (zhi 019eb42a)

**Date:** 2026-06-11
**Status:** DECIDED (perigrin) — executing.
**Parent decision:** `docs/plans/2026-06-11-target-ir-architecture-review-resolution.md`
(the metadata structs delete eventually; R3's ClassInfo consumption is a
transitional bridge).

## The decided design (option b: class structure off the node-input channel)

perigrin resolved the node-input-protocol question (2026-06-11): class
structure is **compile-time context, not dataflow**. The `Call(new) ->
ClassInfo` input edge encodes a dependency that does not exist — class
structure never lowers to a runtime value (the backend special-cases
`inputs[0]` and `add_consumer` is a no-op: it fakes being a node), and
there is no runtime definition event for the scheduler to order against.
Class structure reaches the backend the way a symbol table reaches every
compiler: by name, against a registry handed alongside the graph
(`lower_with_elaboration` already threads `class_registry`).

The rejected option (a) — giving MOP metaobjects content-based `id()` +
no-op `add_consumer` — founders on mutability: `MOP::Class` is a
parse-time accumulator (`declare_*` fires per member as the Earley actions
complete), so its content hash is unstable at `Call(new)`-construction
time (a method body can construct its own class mid-definition). Option
(a) is only sound after sealing — i.e. it is option (b) plus machinery to
make a mutable object impersonate an immutable node.

## Contract changes

1. **`Chalk::IR::Node::Call` gains `class_name`** (`:param :reader`,
   default undef; serialized in `content_hash` when present). For
   `dispatch_kind => 'method'` calls — both `new` and regular dispatch —
   it names the statically-known class. Inputs carry ONLY runtime values:
   `Call(new)` inputs = the `:param` values; `Call(method)` inputs[0] =
   invocant (+ args). No metadata object ever rides as an input.
   (The parse path's `Call->target` MOP::Method handle is unchanged — it
   was already MOP-direct.)

2. **The MOP gains `seal()`** (`Chalk::MOP::seal()` seals the registry and
   every `MOP::Class`; each `declare_*` dies after seal; sealing is
   idempotent). Mutability is for parse-time accumulation only; the
   post-parse read surface becomes enforceably immutable rather than
   immutable-by-politeness. The LLVM backend REQUIRES a sealed MOP.

3. **Backend entry:** `Chalk::Target::LLVM->lower($return_node, mop => $mop)`
   and `lower_with_elaboration($return_node, $elab, mop => $mop)`. The
   class registry is built by `_populate_registry_from_mop` from
   `$mop->classes()` (iterated in sorted-name order for determinism),
   reading `MOP::Class` / `MOP::Method` / `MOP::Field` /
   `MOP::Phaser::Adjust` directly:
   - **fields:** name / fieldix / is_param / has_reader / has_default /
     default_value / type (same readers the ClassInfo path already used —
     ClassInfo carried MOP::Field members all along).
   - **methods:** name; **body root = the method graph's single Return's
     value input** (die GAP if the graph has no Return); return repr =
     `$method->return_type // body root's representation`. This replaces
     the transitional `MethodInfo.body_node`/`return_repr` reads. (The
     `body` arrayref is NOT consumed — it is retiring in MOP-migration
     3/4; graphs + control chains are the durable shape.)
   - **adjusts:** statements from the phaser's graph in **control-chain
     order** (walk `control_in` links among the graph's members from the
     chain head). Parsed phasers get this threading from the Block fixup;
     hand-built phasers thread it explicitly.
   - **parent:** `parent_name`; inheritance flatten unchanged.

4. **ClassInfo bridge DELETED from the LLVM tier:**
   `_populate_registry_from_classinfo`, the ClassInfo arm of
   `_scan_class_registry`, `_class_name_from_class_node`, and the
   ClassInfo-input special cases in `_lower_call_new` /
   `_lower_call_method`. The `Chalk::IR::ClassInfo` / `MethodInfo` structs
   themselves are NOT deleted here (MOP-migration 4/4 owns that; their
   remaining consumers are the legacy Program-structure path). The
   `body_node` / `return_repr` fields on MethodInfo stay until 4/4 —
   nothing reads them after this issue.

5. **Corpus ir-block vocabulary** (the dual contract follows the backend):
   ```
   %cls = MOP::Class(name: "Pt")
   %mf  = MOP::Field(class: %cls, name: "x", param: true, type: "Int")
   %mi  = MOP::Method(class: %cls, name: "val", body: %fa, return_repr: "Int")
   %adj = MOP::Adjust(class: %cls, body: [%st_p, %st_x])
   %new = Call(%v42, dispatch_kind: "method", name: "new", class: "Pt", param_names: "x") :Object
   %get = Call(%new, dispatch_kind: "method", name: "val", class: "Pt") :Int
   ```
   - `MOP::Class` allocates via a per-case `Chalk::MOP` instance's
     `declare_class`; `MOP::Field`/`MOP::Method`/`MOP::Adjust` route
     through `$cls->declare_*` (fieldix from declaration order; an
     explicit `fieldix:` kwarg is asserted against the derived index).
   - `MOP::Method(body: %node)` wraps the body in a `Return` merged into
     the method's graph (the builder does this mechanically).
   - `MOP::Adjust(body: [...])` threads `control_in` in list order and
     merges into the phaser graph.
   - The runner seals the case's MOP and passes it to `lower(mop => ...)`.
   - `ClassInfo(...)` / `MethodInfo(...)` builder vocabulary is deleted.

## Migration surface (LLVM tier only — legacy Program-path consumers are 4/4's)

- `lib/Chalk/Target/LLVM.pm` (registry, Call lowerings, entry signatures)
- `lib/Chalk/IR/Node/Call.pm` (+class_name), `lib/Chalk/MOP.pm` +
  `lib/Chalk/MOP/Class.pm` (+seal)
- `t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm` (vocabulary + mop handoff)
- `t/corpus/mdtest/classes.md` (8 cases), `variables.md` (A5)
- `t/bootstrap/ir/`: build-classinfo.t (becomes build-mop.t),
  llvm-classinfo-lowering.t (becomes llvm-mop-registry.t),
  llvm-mop-classes.t, llvm-call-new-dispatch.t, llvm-call-method-dispatch.t,
  llvm-adjust-per-class-fn.t, llvm-stale-value-cache.t, llvm-env-read.t,
  llvm-method-body-needs.t, llvm-regex-subst.t, llvm-str-const-collision.t,
  llvm-strpair-undeclared.t, implicit-return.t (LLVM section if any)
- Docs: `docs/architecture/mop.md` (transitional section), 
  `docs/architecture/sea-of-nodes-ir.md` (MOP-lowering section),
  `docs/plans/2026-06-07-mdtest-corpus-format-draft.md` (vocabulary
  amendment note)

## Execution order (TDD, commit per phase)

1. **seal()** — RED `t/bootstrap/mop/seal.t`; MOP + MOP::Class seal flag,
   declare_* guards, idempotent.
2. **Call.class_name** — field + content-hash coverage (factory test).
3. **Backend MOP-direct path** — RED `t/bootstrap/ir/llvm-mop-direct.t`:
   hand-built sealed MOP (field + method + adjust + inheritance),
   `lower(mop => $mop)` with class_name Calls, lli==perl; unsealed MOP
   dies; missing Return dies GAP.
4. **Migrate the llvm ir tests; delete the ClassInfo bridge** from
   LLVM.pm. Sweep.
5. **Harness vocabulary + corpus migration** (classes.md, variables.md
   A5, build-classinfo.t); runner mop handoff. Sweep.
6. **Docs + per-issue review + close.**

## Phase-4 note

Serialized graphs stop being self-describing for class structure — by
design: Phase 4's contract is B::SoN as "trusted IR/**MOP** producer";
the graph and the sealed MOP travel together.
