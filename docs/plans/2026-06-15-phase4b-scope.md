# Phase 4b — Computation Slice: Cross-Repo Scope

**Date:** 2026-06-15
**Stage:** Phase 4, Stage 4b (computation slice green through B::SoN)
**Depends on:** 4a seam re-audit (`docs/plans/2026-06-14-phase4a-seam-reaudit.md`)
**Brief:** `docs/plans/2026-06-12-phase4-bson-brief.md`

4a decided the three open questions and named the work. This doc scopes the
**cross-repo mechanics** — the part 4a deliberately left open — and sequences
4b's idiom-by-idiom work behind its one hard blocker.

## Why this is different from every prior issue on this branch

Every issue so far lived entirely in the Chalk worktree. 4b is the first
**two-repo** stage:

- **Producer** = `~/dev/perl5-son` (`SoN::FromOptree`, `B::SoN`). Branch `pu`,
  clean, own remote `git@github.com:perigrin/perl5-son.git`. The XS
  `FieldInfo` component is BUILT (`blib/arch/auto/SoN/SoN.so`, Apr 7).
- **Consumer** = Chalk (`Chalk::Target::LLVM` L corner,
  `Chalk::Bootstrap::Perl::Target::Perl` P corner,
  `Chalk::IR::Serialize::JSON` loader).
- **Bridge** = the corpus harness + `t/bootstrap/son-compare.t`, which already
  spans both repos: it locates perl5-son via `PERL5_SON_LIB`
  (default `~/dev/perl5-son/lib`), runs `perl -MO=SoN,json,package=...` and
  Chalk's `script/chalk-emit-son-json` as siblings, and diffs the JSON
  (son-compare.t:14-40). The seam already exists and works; 4b grows what
  flows across it.

### Cross-repo working rules (decided)

1. **perl5-son gets a feature branch off `pu`** for the 4b producer work
   (`phase4b-single-exit` or similar), same discipline as Chalk
   (branch-per-stage, merge back to its `pu`). Do NOT commit producer work on
   perl5-son's `pu` directly.
2. **Two independent commit streams, one logical change.** A 4b idiom often
   needs a producer change (FromOptree emits the right nodes) AND a consumer
   change (Chalk lowers them) AND a corpus/test change (the harness verifies
   lli==perl). Commit each in its own repo; cross-reference by stage name in
   the messages (perl5-son commits can't ride Chalk's git-zhi chain).
3. **The corpus harness is the integration gate**, not per-repo unit tests.
   A 4b idiom is "green" when its mdtest perl source flows
   source → B::SoN → JSON → Chalk loader → backend → run == perl oracle. The
   per-repo tests (perl5-son's `t/from-optree-*.t`, Chalk's ir/ suite) are
   the fast inner loop; the harness is the contract.
4. **Verification stays Chalk-side** (the trusted instrument). perl5-son
   output is SUSPECT until the harness proves it — a divergence is a B::SoN
   bug (the brief's rule), now sound because Gate 0 closed the backend's own
   miscompiles.

## The blocker that orders 4b: multi-exit bodies (DOUBLE-sided)

4a's biggest finding. Real `lib/` methods are early-return-heavy, and a
multi-exit body is broken on BOTH sides:

- **Producer:** `SoN::FromOptree`'s `return` handler returns the graph at the
  FIRST `return` op (FromOptree.pm:290-304); an early-return sub
  (`return 1 if $x; return 2`) is silently swallowed by `B::SoN.pm:102`'s
  `catch{}` — probe produced NO output.
- **Consumer:** `Chalk::Target::LLVM::_method_body_root` DIES on >1 Return
  ("the lowering root must be exactly one — multi-exit method bodies are not
  lowered yet", LLVM.pm ~360-363).

**Decision (4a (c)): normalize to single-exit in FromOptree** (collect all
returns, merge via Region+Phi into one Return). This is a producer-side fix
for a constraint that bites both corners, and it satisfies the LLVM
single-Return root for free.

**Caveat worth stating plainly:** the single-Return requirement is an L-corner
(LLVM) limit. The P corner (schedule-driven Perl target) may already tolerate
multi-Return — but since the PRODUCER doesn't emit a correct multi-exit graph
anyway, fixing it at the FromOptree seam is the one change that unblocks both
corners, rather than relaxing `_method_body_root` AND fixing the producer
truncation separately. If a later stage wants true multi-exit IR (not
normalized), that is an L-corner backend feature, filed separately — not 4b.

**4b therefore STARTS here.** Nothing non-trivial flows until single-exit
normalization lands; son-compare on real `lib/` stays green-on-trivia until
it does.

## 4b work order (behind the blocker)

Each item = a producer change + (often) a consumer change + a harness-verified
corpus case. Ordered by dependency and by what the 4a gap map marked
`producible-now` (cheap wins to validate the seam) vs `blocked-by-*`.

1. **Single-exit normalization** (producer; FromOptree). The blocker. Merge
   multi-return bodies to one Return via Region+Phi. Verify: an early-return
   sub flows through the harness; `_method_body_root` no longer dies.
   *Consumer side may need nothing* (one Return is what it wants) — confirm.
2. **PadAccess `targ` stability** (producer; the noted cross-graph identity
   blocker, FromOptree.pm:380/656/787). The pad index is CV-local; two
   semantically-identical graphs diverge on `targ`. Decide: drop `targ` from
   the identity-bearing serialization (keep `varname`), or normalize. Needed
   before son-compare on real bodies means anything (4a Debt A).
3. **Validate the `producible-now` slice end-to-end** (harness). The 4a gap
   map marks arithmetic, variables A1/A4/C1, logical L1-L4, strings S1-S3,
   control-flow D1/D6/D2-D3 (suspect), references R1-R5/R9-R11, statements,
   subs F1-F3 as producible-now. Run their corpus perl sources through the
   full B::SoN→harness path; each that lands == perl oracle is a real green,
   each that doesn't is a newly-localized producer bug. This is the gap map
   turning red→green and is the bulk of 4b's value.
4. **Field/element writes** (producer; the confirmed drop). `$n += 1` lowers
   to `FieldAccess; Add; Return` — the store back is ABSENT (4a §1b probe).
   Wire the result back as an Assign-over-FieldAccess/Subscript lvalue (the
   Chalk store shape). Unblocks references R6/R7 and is a prerequisite for the
   4c class tier's mutation methods.
5. **CompoundAssign** (producer). `+=`/`.=` map to Call/branch, not the
   CompoundAssign node (4a). Unblocks variables C2, strings S4.
6. **Increment modeling** (producer). `++`/`--` → Call (OpMap:70-77);
   semantics + postinc return-value unverified. Unblocks increment K1/K2.

Loop-Phi correctness (D2/D3/D5) is marked `producible-now (suspect)` — verify
under item 3; if the loop merge is wrong it joins this list.

**Out of 4b scope** (later stages, per the brief): the MOP/class tier
(`needs-MOP-contract` — that's 4c: declarative class-structure JSON replayed
Chalk-side via declare_*/seal, decided in 4a (b)); RegexCapture wiring,
EnvRead, TryCatch lowering (4d, gated on 019eb6ff item 1 = the regex/host/try
tier). The corpus `GAP(compile-time)` cases (pragmas, non-ASCII encoding) stay
honest GAPs.

## Open question — RESOLVED at scope time (2026-06-15)

The producer-side single-exit normalization needs a Region+Phi merge in
FromOptree. Confirmed: FromOptree ALREADY builds general branch-merge IR, not
loop-only — `make_cfg('If', ...)` (FromOptree.pm:107/:597), `$sim->merge(...)`
producing a Region (:130 for if/else, :154 for try/catch), and Phi (:197),
via `_walk_branch` (:750) with convergence detection. So single-exit
normalization REUSES this machinery: instead of returning the graph at the
first `return` op, the `return` handler defers — collect each return's value +
control edge, then merge them through the existing Region+Phi path into one
Return. **Item 1 is a rework of the `return`/`leavesub` handler
(FromOptree.pm:290-304, :516), not new producer IR plumbing.** Reasonably
sized; the merge primitive already exists.

## Net

4b is producer-heavy (most work is in perl5-son's FromOptree), gated on the
corpus harness as the integration contract, sequenced behind single-exit
normalization. The Chalk side mostly already works (the consumer slice is
Gate-0-clean); 4b's job is making B::SoN PRODUCE the IR the corpus already
proves the backend can lower. Start: confirm the producer's branch-merge IR
(open question above), then item 1.
