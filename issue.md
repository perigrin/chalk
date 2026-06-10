---
title: "Reconciliation 3/3: node convergence Phases 4-5 (MOP+dispatch) + docs"
state: done
urgency: normal
milestone: codegen-harness
blocked_by:
- 019eaacc-4dd8-7a5f-b095-29fc817b6442
blocks:
- 019eaa51-c48d-74ad-920e-da2f3ce94c5b
- 019eaa51-bd3e-7b89-b376-c13304da68f7
created: 2026-06-09T05:12:56.566413405Z
updated: 2026-06-10T02:47:28.114144747Z
sessions:
- start_sha: b1a6dcea4421bd9726b002a0e0995f6c2d466f9f
  end_sha: b1a6dcea4421bd9726b002a0e0995f6c2d466f9f
  commits: 0
  started_at: 2026-06-10T02:47:20.698046407Z
  ended_at: 2026-06-10T02:47:28.114144747Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-10T02:47:20.698046407Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-06-10T02:47:28.114144747Z
---

Reconciliation 3/3 (final): converge Cluster B (MOP + dispatch) onto the canonical MOP/ClassInfo layer + canonical Call, then docs. Plan: docs/plans/2026-06-08-ir-taxonomy-reconciliation.md (Cluster B ~130-145, I2 ClassInfo-input spec ~266-283, Phase 4 decomposed ~330-348, Phase 5 ~350-362, Phase 6 docs ~364, acceptance ~431-449). Blocks G6/G7. Read memory r2_node_convergence_baseline.md first.

CONVERGENCE INVARIANT (C1): t/bootstrap/corpus/classes.t (the 7 classes.md cases) MUST stay GREEN at every phase — only IR shape changes, observable behavior unchanged. Capture baseline first. Each phase: extend TypedInvariant for the canonical op + bilateral well-typed-graph.t case (C5); per-phase commit. Phases 4+5 are ENTANGLED (Call.target IS a MOP::Method Phase 4 provides) — land as one coherent set.

CONSTRAINT: consume ONLY the immutable ClassInfo/MethodInfo read surface (id()/add_consumer); do NOT wire the stalled SoN-MOP migration internals (docs/plans/2026-04-21-chalk-mop-migration-plan.md; class-scope-vars.t fails at MOP/Class.pm:100 = that migration surface = known-baseline, don't entangle).

Phase mapping (parallel node -> canonical, all exist in lib/Chalk/IR/Node/; LLVM still dispatches them):
- 4.0 (I2): ClassInfo/MethodInfo-as-ir-block-input builder support in MdtestCorpus.pm _build_node_from_rhs (recognizer like Coerce/New); teach LLVM to CONSUME a ClassInfo for vtable+object-struct+ADJUST order, WITHOUT deleting any node yet (both paths coexist). RED/GREEN: ClassInfo-carried graph lowers identically to ClassDecl-subtree.
- 4.1 ClassDecl -> ClassInfo (delete ClassDecl)
- 4.2 MethodDef -> MethodInfo (delete MethodDef)
- 4.3 FieldDef -> MOP::Field; field READ stays FieldAccess (delete FieldDef)
- 4.4 FieldWrite -> Assign(FieldAccess-lvalue) carrying field_index+field_stash (delete FieldWrite; DISSOLVES F9)
- 4.5 AdjustBlock -> MOP::Phaser::Adjust (delete AdjustBlock)
- 5: MethodCall -> Call(dispatch_kind=method) via MOP vtable/target (delete MethodCall); New -> Call(name=new) with malloc/vtable/:param/ADJUST as the new-Call lowering (delete New)

FOLD IN (R2-reopen review V1-V5, deferred here because they share the store machinery with 4.4 FieldAccess-lvalue — keep field/hash/array store ptrtoint guards consistent in one pass):
- V1 (Important): _lower_assign HASH-lvalue store LLVM.pm:2054 has NO ptrtoint guard (array branch 1966-1974 does) -> ref-into-hash-slot = `store i64 <i8*>` invalid IR. Mirror 1966-1974 in the $lbl_wupd block.
- V2 (Important): _lower_hash_read (3520-3535) lacks the ArrayRef||HashRef inttoptr result branch _lower_array_read has (3385-3393) -> ref-valued hash slot read returns i1 not i8*. Add the elsif.
- V3 (Important): I-B(HashRef-value) test in t/bootstrap/ir/llvm-aggregate-latent-fixes.t:250-291 is VACUOUS (Return wires Length($inner), $hash never lowered). Rewrite as Return(Length(Subscript($hash,"k"))) using the V2 read branch; assert lli==2; pins V1+V2+construction guard.
- V4 (Suggestion): no loud-die on _arr_table//cache double-miss (3335/3431); robustness die-guard mirroring _lower_length 3241-3247.
- V5 (Suggestion): _str_len_for(...)//0 silently zeroes untracked hash-key lengths (2001/3434/3172) -> spurious match; loud GAP die per the I-C contract.

PHASE 6 (docs, same change-set): update docs/architecture/sea-of-nodes-ir.md (converged aggregate+MOP vocabulary; any KEPT new node documented here); strike stale doc text (typed-ir-representation.md Coerce Q2/Q3 answered). Fold R2-deferred S2 (stale 'ArrayRead'/'HashRead' GAP-labels LLVM.pm 3373/3575), S3 (stale HashWrite comment 3261), S4 (~50 cosmetic .ll labels), S5 (TypedInvariant ArrayRef/HashRef/Assign bilateral coverage), S6 (R6/R7 read-back coverage).

VERIFY (lesson): do NOT run the full non-C surface twice serially as a background sweep (perl-recognize-phase5.t / perl-target-perl-tier-*.t take minutes each, starve everything, pile up across turns). Instead: (1) R3-sensitive surface at HEAD = ir/ corpus/ mop/ + self-hosting tier (perl-actions-tier-a/b, codegen-target, codegen-perl, perl-target-perl-tier-a, bnf-target-c); (2) spot-check specific unfamiliar failures HEAD-vs-base via temp `git worktree add --detach <base>`. Kill stragglers (pkill -f 'It/lib t/bootstrap') before launching. Subagent test-run claims have been unreliable this session — independently re-run the gate yourself.

Known-baseline failures (NOT regressions): bootstrap-validation.t, c-*.t family, codegen-{builtin-hash-arg,hash-init,no-pragma,pipeline}.t, comonad-threading.t, cfg-loop-phi/cfg-loop/cfg-statements.t, perl-actions-tier-b.t (test 49), integration-phase2b-parse-ir.t, method-return-type.t, parser-semantic-boundary.t, mop/{class-scope-vars,codegen-byte-compat,codegen-byte-compat-schedule,ir-completeness}.t.

DONE: /paad:agentic-review after; git zhi issue edit 019eaacc-4df6 --state done; git zhi sync --push (NOT plain push); G6/G7 unblock; commit the review report to paad/code-reviews/. R1+R2 done+synced on origin/phase1-lateral-bindings.
