# Memory-SSA for aggregate element reads

**Date:** 2026-07-05
**Status:** DESIGN (approved model: full memory-value + MemPhi, one global memory,
alias-splitting deferred). Awaiting build sign-off.
**Fixes:** zhi 019f3354 (element reads not memory-ordered against stores; the
read/store WAR miscompile `my $x=$a[0]; $a[0]=99; $x` -> 99 not 5). Composes with
zhi 019f330b (R12 aliased element store) as a follow-on.

## The problem

An element read is `Subscript(container, index)`, hash-consed on
`(container, index)` with no memory input. A pre-store read and a post-store read
of the same slot collapse to ONE node (in fact the read node and the store's
lvalue Subscript are the same object), so the single load observes the FINAL
memory state. Scalars are immune: a scalar read binds to the *value node* held at
that point (scope-binding = free SSA versioning). Aggregates have no equivalent.

## The model (canonical Sea-of-Nodes memory-SSA, per Cliff Click / LLVM MemorySSA / V8)

Memory is itself an SSA value threaded through the graph:

- **Initial memory**: a value at function entry (and conceptually redefined by each
  aggregate allocation). One GLOBAL memory value (no alias-class splitting yet --
  that is a pure optimization, deferred; independent arrays may false-serialize,
  which is correct-but-not-optimal).
- **A store PRODUCES a new memory value.** The element-store Assign consumes
  memory-in and yields memory-out.
- **A load CONSUMES the live memory value** at its program point (a real input, so
  hash-consing distinguishes a load at mem-version M1 from one at M2).
- **At a control-flow merge, memory gets a Phi (MemPhi)** -- the SAME Phi node
  Chalk already uses for scope variables, whose inputs happen to be memory values.
- **Loops** thread memory through a header Phi like any loop-carried value.

This is correct for straight-line code, branches (stores in one arm -> MemPhi at
the merge), and loops (header MemPhi) -- not just the straight-line case.

## Why this fits Chalk's existing machinery (the key finding)

`StackSim::merge` (perl5-son FromOptree/StackSim.pm:80-115) already builds a
Region at merges and creates Phi nodes for scope variables AND stack positions
that differ between arms, then sets `$control = $region`. Memory threads
IDENTICALLY: a `$memory` field parallel to `$control`, merged by the same Phi
mechanism. The merge/Region/Phi/loop-header infrastructure is reused, not rebuilt.

## Concrete plan

### Producer (perl5-son)

1. **StackSim gains a `$memory` field** (parallel to `$control`), a `:reader` +
   `set_memory`, initialized at function entry to an initial-memory value
   (FromOptree.pm:104, alongside `control => $start`). The initial-memory value is
   a node -- candidate: a `MemStart` (a distinct nullary node) OR reuse `Start`.
   DECISION: a distinct `MemStart` node so the memory chain is typed and never
   confused with control. (Small new node, mirrors Start.)

2. **Element store produces memory** (FromOptree.pm:1066-1072): the store Assign
   already threads control; it additionally takes `$sim->memory` and the store
   node becomes the new memory (`$sim->set_memory($store)`), so the store IS the
   memory-out (the store node doubles as its own memory value -- standard SoN,
   the Store node is the memory it produces). The read then depends on the store
   node as its memory input.

3. **Element load takes memory** at ALL THREE read-construction sites (recon
   finding -- not just the aelem/helem handler): FromOptree.pm:999 (aelem/helem)
   PLUS the two generic-dispatch sites (FromOptree.pm ~1157 and ~1259) for
   aelemfast/aelemfast_lex/multideref. Shape: `Subscript(container, index, memory)`
   -- memory LAST so container=[0]/index=[1] stay fixed (the store lvalue path
   reads [0]/[1] by index; keeping them fixed means zero store-path change).

4. **merge() creates a memory Phi** (StackSim.pm:80-115) when the two arms' memory
   differs, mirroring the scope-var Phi loop; the merged memory becomes the new
   `$memory` (like `$control = $region`).

5. **Loops** thread memory through a header Phi (FromOptree.pm _translate_while_loop
   ~1279) like other loop-carried values.

### Loader (Chalk)

- The memory input rides in `inputs()` (a normal data edge), so it is preserved
  verbatim -- no is_stmt_effect split needed for the load (recon-confirmed). The
  store's control split is unchanged.
- Repr: the memory value / MemStart carries a `Memory` repr (or no repr, and the
  backend ignores it). A Subscript's DATA repr (Int/Str) is still inferred from
  the container element type; the memory input does not participate in that.
- `_control_chain_nodes` / repr closure already added for stmt-effect Assigns;
  extend it to reach the memory chain if a memory node needs typing.

### Backend (Chalk LLVM) -- CORRECTED SCOPE (recon was wrong here)

The recon claimed "no backend change for straight-line." WRONG. The producer's
memory input makes reads DISTINCT nodes, but Chalk lowers a pure-data read LAZILY
at its CONSUMER (the Return, processed AFTER the control-chain walk emits the
stores). So a pre-store read (mem=MemStart) is still emitted after the store and
reads the mutated array. The scalar case is correct only because the producer
snapshots scalars into var_table via scope-binding -- aggregates have no such
snapshot.

THE CORRECT MODEL (canonical Sea-of-Nodes memory-SSA): the memory input is a real
scheduling constraint. A load Load(mem, addr) is placed AFTER the node producing
`mem` and before any later memory version. So the backend must EMIT A MUTABLE READ
AT ITS MEMORY INPUT'S CONTROL POSITION, not lazily at its consumer:
- A read with mem=MemStart: emit at function entry (before any store), freeze its
  value, consumers use the frozen value.
- A read with mem=Store_N: emit after Store_N.
FEASIBLE via the existing consumer-walk: a memory-producing node (MemStart / a
store Assign) has `consumers()`; its Subscript consumers are exactly the reads
valid at that memory version. When the control walk reaches a memory node, emit +
freeze its read consumers before advancing. This mirrors how stores are
materialized at their control position, and how var_table snapshots scalars.

This is a MEDIUM backend change (a mutable-read scheduler keyed on the memory
edge), not zero. It is the real heart of memory-SSA and generalizes to 2b/2c/2d.
- For BRANCHES/LOOPS: the memory Phi must lower. A MemPhi that selects between two
  memory values (which are store nodes / MemStart) needs a lowering -- but memory
  values are not materialized data (a store already emitted its effect), so a
  MemPhi is a SCHEDULING artifact, not a runtime value. Likely lowers to nothing
  (a no-op / it just orders loads after the correct stores). THIS IS THE ONE PART
  NEEDING BACKEND CARE and must be validated with a branch-with-store probe before
  claiming loops/branches work. Scope Phase 2a to straight-line + assert the
  branch case is an honest GAP until 2b.

### Corpus

- Shape contract is signature-based (kind+repr, NOT inputs) -- adding a memory
  input to Subscript does NOT change its signature (recon-confirmed). Existing
  references.md Subscript ir-blocks match unchanged. The memory input node
  (MemStart / a store) is visited but produces a benign signature.
- New teeth (references): read-before-store (`my $x=$a[0]; $a[0]=99; $x` -> 5) and
  interleaved (`$a[0]=1; my $x=$a[0]; $a[0]=2; $x+$a[0]` -> 3), GREEN.

## Phasing

- **2a (this plan): Subscript element reads, straight-line + single-block.** Closes
  019f3354 for straight-line code. Memory field + MemStart + load-takes-memory
  (3 sites) + store-produces-memory. Branch/loop memory-Phi asserted as an honest
  GAP (die loudly, not miscompile) until 2b.
- **2b: branch/loop memory-Phi.** CORRECT MODEL (canonical SoN, confirmed): an
  element store in a branch is CONTROL-DEPENDENT on the branch -- pin its control
  to Proj(If, true) so it is emitted inside the guarded block (the backend's
  _process_branch_from_if already emits guarded Assign effects), and merge memory
  with a Phi over the Region (the read after takes it). A memory-Phi is a
  scheduling token, NOT a runtime value-select. REJECTED false-start (reverted):
  a memory value-select TernaryExpr(cond, store_mem, MemStart) -- the scalar
  value idiom misapplied to memory, which the backend cannot `select`. The
  producer's and-void-branch handler already builds If/Proj for the guarded-EXIT
  case (`return X if C`); extend it to a non-exit body with a memory-Phi. Loops:
  a header memory-Phi like other loop-carried values. See zhi 019f33f6.
- **2c: FieldAccess** (object fields, same %MUTABLE_READ_OPS hazard) via the same
  memory value.
- **2d: R12 aliasing** (Subscript over a Ref) -- the memory value makes a store via
  one name visible to a read via another IF both resolve to the same memory
  version; composes with the Ref-container resolution.
- **Later (optimization, not correctness): alias-class splitting** so independent
  aggregates do not false-serialize (Steensgaard/Andersen). NOT needed for
  correctness.

## Risks

- The MemPhi lowering (branch/loop) is the least-certain part -- validate with a
  probe before 2b; keep 2a straight-line-only with a loud GAP for branch-store.
- The store-node-doubles-as-memory-value convention must not break the existing
  is_stmt_effect control threading (control and memory both point at the store
  node; they are different EDGES to the same node -- confirm the loader's control
  split does not consume the memory edge).
- Determinism: the memory input is a content-hash participant; ensure the initial
  MemStart has a stable id (content-based, like Start).
