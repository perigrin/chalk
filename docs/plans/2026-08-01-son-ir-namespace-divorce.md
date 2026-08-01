# ABOUTME: Plan to re-divorce B::SoN's vendored Chalk IR classes into SoN::IR::*,
# ABOUTME: so B::SoN can compile the chalk classes it currently loads and shadows.

# SoN/Chalk IR namespace divorce — unblocking 55% of lib/ for the Phase-5 capstone

**Status:** DOUBLE-ASSESSED 2026-08-01 (crochet:assess Fable + ponytail). Verdict: SOUND, and SHRUNK -- assess reproduced the central proof to the digit and verified every citation; ponytail then cut the standalone contract doc and the cross-repo conformance test as drift insurance bought before any drift exists. Ready for crochet:refinement.

All measurements taken 2026-08-01 on chalk `967ade11` / perl5-son `pu`, and
independently re-verified by the assessor on the same commits.

## The problem, measured

Loading `B::SoN` pulls **91 `Chalk::*` modules** into `%INC` (measured:
`perl -I<son>/lib -MB::SoN -e 'grep m{^Chalk/}, keys %INC'`). B::SoN needs them
because it does not merely emit JSON — it **constructs a real IR object graph**
via `Chalk::IR::NodeFactory` and `Chalk::IR::Graph`, then serializes it
(`B/SoN.pm:17-18,372,416`; `SoN/FromOptree.pm:12-13,167,927,2332,2355,2543`).

Consequence: compiling any of those 91 files *as a B::SoN target* fails at
compile time —

```
Cannot reopen existing class "Chalk::IR::Graph" at lib/Chalk/IR/Graph.pm line 8.
```

— because Perl's `class` feature refuses to reopen a class the compiler already
loaded. The file's body never compiles, so its methods are never emitted.

**Scale:** chalk `lib/` holds 166 `.pm` files. 91 are loaded by B::SoN; **90 of
those are `class` files and therefore structurally uncompilable** (~54%). The
91st, `Chalk/IR/Serialize/JSON.pm`, is a plain package — reopening it produces
redefinition warnings, not the fatal class error. perl5-son separately vendors
104 `Chalk::*.pm`; all 104 verified **byte-identical** to chalk's copies (104
identical / 0 different). The 91 loaded are a strict subset of the 104 vendored.

### Why this was invisible until now

The Phase-5 coverage harness reports the *downstream* symptom, not the cause. It
prints `GAP: method '_seed' in class 'Chalk::IR::Graph' has no Return in its
graph` — because the MOP carries a `_seed` entry (replayed from class metadata)
with no graph behind it. That reads as a lowering gap. It is not.

## The proof (falsification test, run 2026-08-01)

Took `lib/Chalk/IR/Graph.pm` verbatim, changed only the class *name* so it is not
pre-loaded, and compiled it with B::SoN:

| | collision (real name) | renamed copy |
|---|---|---|
| methods emitted | 4 | **7** |
| `_seed` | absent | **present, 25 nodes, Return x1** |
| `merge` | absent | present, 41 nodes, Return x1 |
| `unmerge` | absent | present, 27 nodes, Return x1 |

`_seed` has a Return and always did. The namespace collision is the **sole**
cause — nothing else is hiding behind it, and the fix is *sufficient*, not merely
necessary.

**Retracted by this test** (recorded so the wrong diagnosis is not re-derived):
- "4 methods account for 100% of the 47 blocked units" — contaminated blame; 21
  of those units traced to a class that never compiled.
- "6 of 8 files gated on one accessor GAP class" — repeated from the harness's
  stale printed diagnosis text; not supported by its own `fails` data.

## Decision

**Re-divorce the namespaces. B::SoN gets its own `SoN::IR::*` classes. The shared
artifact becomes the wire format and node taxonomy — a contract carried in the
code comments and enforced by the corpus gate — not shared `.pm` files.**

Unification was the correct FIRST step and is not being undone. You cannot
extract a contract from two drifted implementations — you would codify the drift.
Unification produced today's ground truth (104 byte-identical files, zero
divergence), which is exactly what makes this divorce mechanical and verifiable.
The sequence is **unify → extract the contract → re-divorce against it**; this
plan is step 2-and-3. The collision is a consequence of unification that only
became visible when the capstone tried to compile the compiler's own
dependencies.

**Precedent:** `lib/Chalk/IR/Graph.pm:162` describes the topo-sort as "exactly the
pre-unification `SoN::IR::Graph::nodes()` shape." That namespace previously
existed. This restores it — this time with the walk-order contract carried in the
comments the rename copies, and the corpus gate enforcing it.

## The contract (what "single IR" means after the divorce)

Single IR = **one wire format and one node taxonomy**, independently implemented.
The contract lives in the code comments; the corpus gate is the enforcement.

### A. Walk-order contract = THE CODE COMMENTS (no separate doc)

**DECIDED (perigrin, 2026-08-01, after ponytail review): the comment blocks ARE
the contract. Do NOT lift them into a standalone doc.**

The mechanical rename **copies them automatically** — `SoN::IR::Graph` inherits
`Graph.pm:133-170` verbatim, and `SoN::Serialize::JSON` inherits
`Serialize/JSON.pm:127-171` with the duplicated `_all_nodes_topo`. Both repos get
the spec for free, co-located with the code it constrains, which is where prose
is least likely to rot. A standalone doc in two copies would be a third and
fourth copy of prose that is not the enforcement anyway.

**Enforcement is the corpus gate + byte-compat goldens.** Add one line to each
comment block on both sides: "This is the cross-repo walk-order contract; the
corpus gate enforces it."

The four clauses, for reference (they live in the comments, not here):

1. **Membership** — bidirectional reachability over `inputs()` *and*
   `consumers()` from every cached node; consumers followed ONLY when already in
   the graph's cache (the graph-local filter that keeps foreign/orphan nodes out).
2. **Order** — topological sort over **producer edges only** (`inputs`, plus a
   Phi's `region`). Consumers are never treated as producers; doing so finalizes
   a consumer before the producer it reads.
3. **Backedge cut** — a loop-header Phi's `inputs[1]` is cut; the loader
   defer-patches it via `set_backedge`.
4. **Post-pass** (`_all_nodes_topo`) — add Phi `region`s and `control_in`-only
   nodes, fixpoint in both directions, guarantee Region precedes Phi.

### B. Conformance test — CUT (ponytail review, 2026-08-01)

**DECIDED: do NOT build a cross-repo conformance test. The corpus gate is the
anti-drift mechanism.**

Rationale: measured drift today is **zero** (104 files byte-identical). Assess
confirmed the 156 corpus idioms already exercise all four clauses at behavior
level — backedge cut (D2d/D2e/T4d/D3a-e), control_in-only effect nodes (the
I2/L5/D1 print family), consumer-edge membership (void prints with no data
consumer), Region-before-Phi (the pinned merge-Phi loader-topo bug). The test's
only residual value was shapes OUTSIDE the corpus, and the existing corpus
absorbs those as 2-3 new cases at near-zero marginal cost, under the triple
contract and floor discipline already in place.

It also only ever justified the SoN→loader direction — the direction something
actually consumes. The reverse (chalk's serializer matching SoN byte-for-byte)
has no consumer today; that is conformance for a self-hosting stage that does
not exist yet.

**Cutting this deletes the entire fixture-provenance problem** — checksum-pinned
duplicated fixtures, options (a)/(b)/(c), and the "resolve fixture design before
execution" workstream all evaporate. That workstream existed only to serve
machinery that should not be built.

**Replacement (follow-up, not this plan):** file TryCatch/Unwind corpus cases as
a small separate issue. Revisit a cross-repo conformance test only if the corpus
gate ever catches real serializer drift. It has not.

## Considered and rejected (record these so they are not relitigated)

**1. Emit the wire JSON without constructing IR objects at all.** REJECTED — it
is a rewrite, not a fix. `SoN/FromOptree.pm` is ~4,000 lines with **131 factory
construction sites**, and the objects are load-bearing, not a carrier:
hash-consing identity via `content_hash` (`NodeFactory.pm:316-327`) dedupes nodes
and thereby determines positional wire IDs; `consumers()` use-def edges drive
membership (`FromOptree.pm:927`) and the serializer's topo order; ~25
`->isa('Chalk::IR::Node::X')` dispatch decisions run during translation.
Reimplementing that over plain hashes while holding byte-compat goldens is
strictly more expensive and riskier than renaming byte-identical files.

**2. The 30-line harness stopgap.** The proof's own trick, productized: have
`t/lib/Chalk/CodeGen/Harness/Phase5LibCoverage.pm` sed-rename the target file's
`class` declaration before compiling. This delivers *this plan's only stated
near-term deliverable* ("converts 91 files from uncompilable to measurable")
without touching perl5-son at all, in ~30 lines. REJECTED as the primary fix
because it measures a **drift-blind twin**: the probe-renamed target still
compiles against vendored parent classes, which is the exact disease being cured,
and real self-hosted compilation of real class names still requires the divorce.
It remains legitimate as a temporary measurement aid if the divorce is delayed —
but it must not be mistaken for progress on the capstone.

## Scope

1. Rename perl5-son's vendored `Chalk::*` → `SoN::*` (`SoN::IR::Graph`,
   `SoN::IR::NodeFactory`, `SoN::IR::Node::*`, ...).
2. Update the lib consumers: `B/SoN.pm` (:17-18, :372, :416),
   `SoN/FromOptree.pm` (:12-13, :167, :927, :2332, :2355, :2543),
   `SoN/Serialize/JSON.pm` (:14, :158). `SoN/Render/Text.pm`'s two mentions are
   comments only. Also the ~25 literal `isa('Chalk::IR::Node::X')` strings in
   FromOptree and the two string-built dispatch maps `"Chalk::IR::Node::$_"`
   (`NodeFactory.pm:91,116`).
3. **The perl5-son test suite is IN SCOPE: 27 `t/` files reference `Chalk::`**
   (`t/ir-graph.t`, `t/serialize-json.t`, `t/standalone-nodes.t`, ...). A rename
   executed against lib/ alone leaves the suite red.
4. **Trim the dead vendored files first (answers open question 2: yes, delete).**
   13 vendored files are never loaded, and a mechanical rename would convert
   their references into references to nonexistent `SoN::*` modules:
   `Chalk/IR/Scheduler/EagerPinning.pm:15-17` (`use Chalk::Scheduler::*` — not
   vendored, already unloadable standalone), `Chalk/IR/Target.pm:15,20`
   (`Chalk::Target::LLVM`), plus `Schedule/*`, `TypedInvariant.pm`, `Program.pm`
   and the five Info structs. Three cannot even load from son/lib alone.
   Separately, the **loaded** `Chalk/IR/Serialize/JSON.pm:781` carries
   `require Chalk::MOP` inside `_replay_classes` — post-rename that becomes
   `require SoN::MOP`, which will not exist. B::SoN never calls the loader half,
   so nothing breaks at runtime, but strip or explicitly mark that dead half.
5. **Duplicate** `_all_nodes_topo` into `SoN::Serialize::JSON`. Today
   `SoN/Serialize/JSON.pm:158` reaches across repos into the *private*
   `Chalk::IR::Serialize::JSON::_all_nodes_topo` — exactly the coupling being
   severed. Copy it; do not import it.
6. Add one line to each walk-order comment block (both repos, after the rename
   copies them): "This is the cross-repo walk-order contract; the corpus gate
   enforces it." No separate doc, no conformance test — see contract section.
7. Chalk side: **no production change expected** (verified: every `SoN` mention
   in chalk `lib/` is a comment). Chalk keeps `Chalk::IR::*`.

**Rename count: 104 vendored − 13 deleted = 91 renamed.** Renaming only the 90
that collide would leave a mixed namespace and live shadowing paths — the trim
plus full rename converges to the right number.

## Anti-drift guard (already exists — this is why the divorce is safe now)

The corpus gate `t/bootstrap/corpus/son-corpus-wide.t` runs B::SoN → chalk's
loader → lli end-to-end for **156 gate-green cases** under a triple contract
(behavior + shape + TypedInvariant), plus byte-compat goldens. A rename that
changes emitted output fails it immediately.

**PRECISION (measured — the safety claim depends on it):** the gate stays green
*because it compiles FILTERED*. `son-corpus-wide.t:66` passes `package=` to
`-MO=SoN,json`, and a filtered compile of a trivial file emits JSON containing
**zero** occurrences of `Chalk` (1,351 bytes). The SAME file compiled
**unfiltered** emits **994** occurrences (770KB) — B::SoN walks every loaded
stash and serializes its own vendored classes. So:
- Method keys like `Chalk::IR::Graph::_seed` come from the **compiled target's**
  package and are unchanged by the rename.
- Corpus-gate bytes are rename-invariant. Op names are hardcoded literals
  (`method operation() { 'Add' }`) and `content_hash = join('|', operation,
  input-ids)` (`Node.pm:96`), so node IDs are class-name-invariant.
- **NEVER add an unfiltered-output golden.** It would encode the vendored class
  names and make the gate rename-sensitive for no benefit.

The Phase-5 coverage harness compiles **unfiltered**
(`Phase5LibCoverage.pm:62`), so its JSON changes wholesale post-rename — 
harmlessly, because its `own_pkg` filter (:56) matches the target's declared
names. The vendored classes *ceasing* to match `own_pkg` is precisely the
contamination fix.

**Floor to hold: gate-green >= 156, worklist 0.** Self-verified by the
coordinator on committed HEAD, never a subagent report.

## Risks

1. **Byte-compat goldens depend on `nodes()` walk order.** The rename must
   preserve behavior EXACTLY. Do not "clean up while in there" — no reordering,
   no refactoring. A pure mechanical rename.
2. **104 files is a large mechanical diff.** Partition by path for parallel work;
   verify on a CLEAN build (stale `blib`/`site_perl` copies mask deletions —
   perl5-son needs `-Ilib -Iblib/lib`, run `-j1`).
3. **Duplicated `_all_nodes_topo` can now drift.** That is the accepted cost of
   divorce — state it rather than pretending duplication is free. Mitigation is
   the **corpus gate**: it runs B::SoN → chalk's loader end-to-end, so a
   divergence between the two copies on any of the 156 covered shapes fails it.
   Uncovered shapes (TryCatch/Unwind) are the residual exposure, and the
   follow-up corpus cases close them. A cross-repo conformance test was
   considered for this and cut as premature — drift measured today is zero.
4. **Self-hosting recursion.** After the rename, B::SoN can compile
   `Chalk::IR::*`. It still cannot compile its own `SoN::IR::*` (same collision,
   new namespace). That is acceptable — those are not the capstone target — but
   it should be stated, not discovered later.

## What this does NOT do

**It does not make anything lower.** Emission is not lowering. It converts 90
class files from *uncompilable* to *measurable*. Expect the honest Phase-5
coverage number to stay low afterward; `merge` at 41 nodes will hit real gaps.
The value is that the number becomes real.

Today's `0.00%` (47 own units, 8 files) is partly a measurement artifact. The
true lowerable surface is unknown until this lands.

**One way the plan UNDERSELLS itself** (assess finding): post-rename, a target's
`use Chalk::IR::Node` will actually load **chalk's real file** during target
compilation. Today that resolves to a `%INC`-shadowed vendored copy which
compiled *before* B::SoN's rpeep suppression and therefore GAPs heavily. So
dependency-graph quality improves for **every measured file**, not only the 90.
Expect harness runtime and emitted JSON size to grow correspondingly.

## Acceptance criteria

1. `perl -I<son>/lib -MB::SoN -e '...%INC...'` reports **0** `Chalk::*` modules.
2. `lib/Chalk/IR/Graph.pm` compiles under B::SoN with no "Cannot reopen" error and
   emits **7 methods** including `_seed` (25 nodes, Return x1), `merge` (41,
   Return x1), `unmerge` (27, Return x1) — matching the reproduced proof.
3. Corpus gate holds: gate-green >= 156, worklist 0, all three legs.
   Coordinator-verified on committed HEAD, never a subagent report.
4. perl5-son suite green on a CLEAN build (`prove -Ilib -Iblib/lib -j1`) —
   including the 27 renamed `t/` files.
5. Phase-5 coverage harness re-run and its NEW number recorded honestly — whatever
   it is, including if it is still 0%.
6. No dangling `SoN::MOP` / `SoN::Scheduler::*` / `SoN::Target::*` references
   remain (the dead-file trim landed).
7. Each walk-order comment block (both repos) carries the one-line
   "this is the cross-repo contract; the corpus gate enforces it" note.

**Dropped from the ACs by the ponytail review:** the standalone contract doc and
the cross-repo conformance test (with its checksum-pinned fixtures). Replaced by
a follow-up issue: add TryCatch/Unwind cases to the corpus.

## Execution sequence (smallest path to a real number)

1. **perl5-son:** delete the 13 dead vendored files + strip the dead
   `require Chalk::MOP` loader half. Suite green on a CLEAN build
   (`prove -Ilib -Iblib/lib -j1`).
2. **perl5-son:** mechanical rename of the remaining 91 `Chalk::` → `SoN::` —
   use-lines, ~25 `isa()` literals, 2 string-built dispatch maps, copy
   `_all_nodes_topo`, and the 27 `t/` files. **No cleanup while in there.**
3. **Verify:** `%INC` shows 0 `Chalk::*` under `-MB::SoN`; corpus gate >= 156 /
   worklist 0 (coordinator-run, committed HEAD); the `Graph.pm` 7-method proof
   reproduces.
4. **Chalk:** re-run the Phase-5 harness, record the number honestly.
5. **Follow-up issue (written down so it is not drift):** add TryCatch/Unwind
   corpus cases.

## Resolved by assessment (2026-08-01)

1. **Is a pure rename sufficient?** YES. Full cross-reach inventory in Scope §2.
   Nothing beyond the `use` lines, the ~25 `isa()` literals, the two string-built
   dispatch maps, and `_all_nodes_topo`.
2. **Trim the vendored tree?** YES — delete the 13 never-loaded files; see
   Scope §4.
5. **Cheaper alternative?** Both examined and rejected — see "Considered and
   rejected."

3. **Contract doc location — CLOSED. The doc is CUT.** An earlier decision (a
   copy in each repo) was SUPERSEDED once the ponytail review observed that the
   mechanical rename copies the comment blocks automatically. The comments ARE
   the contract; the corpus gate is the enforcement. No standalone doc, in
   either repo.
4. **Conformance-test fixtures — CLOSED, moot.** The conformance test was cut, so
   the fixture-provenance question (checksums / vendoring / provenance stamps)
   disappears with it. That workstream existed only to serve machinery that
   should not be built.

## Review history

- **crochet:assess** (Fable, adversarial, 2026-08-01) — reproduced the central
  proof independently to the digit, verified every cited line number, examined
  and rejected both cheaper alternatives. Verdict: SOUND ENOUGH TO REFINE. Four
  IMPORTANT findings folded in (perl5-son `t/` in scope; dead-file trim; rejected
  alternatives recorded; filtered-vs-unfiltered wire precision).
- **ponytail** (second lens, 2026-08-01) — "the core is right-sized; ~40% wrapped
  around it is drift insurance bought before any drift exists." CUT the
  conformance test and the contract doc; KEEP the rename, the trim, and the
  `_all_nodes_topo` copy; SKIP the stopgap (its number is biased low because
  Stage-3 `lower()` takes the whole shared MOP). Accepted in full by perigrin.

**Why the double-lens mattered here:** assess validated that the plan is TRUE;
ponytail asked whether it is the SMALLEST TRUE THING. Assess passed the doc and
the conformance test without challenge — they survived the first lens and died to
the second.
