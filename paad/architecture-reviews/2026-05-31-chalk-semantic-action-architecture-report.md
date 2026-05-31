# Architecture Report — Chalk (Semiring / Context / Actions layer)

**Date:** 2026-05-31
**Commit:** f3a457f1aabd15467cd742c056585082a702dbc0
**Languages:** Perl 5.42 (feature class)
**Key directories:** lib/Chalk/Bootstrap/Semiring/, lib/Chalk/Bootstrap/Context.pm, lib/Chalk/Bootstrap/Perl/Actions.pm
**Scope:** The semantic-action / IR-construction layer specifically (not the full compiler). ~6,700 lines across 9 files.

## Repo Overview

Chalk is a self-hosted optimizing compiler for a restricted Perl subset, parsing into a Sea-of-Nodes IR. The layer under review is where IR is built: a 5-ary `FilterComposite` semiring `[Boolean, Precedence, TypeInference, Structural, SemanticAction]` runs during Earley parsing. The first four are pure filtering semirings (produce disambiguation verdicts / annotation tags). The fifth, `SemanticAction`, is fundamentally different: it hosts the per-grammar-rule action methods (in `Actions.pm`) that construct IR nodes and mutate a graph, threading state through a comonad `Context`.

This was commissioned to assess one architectural question: **is hosting IR construction inside a filtering-semiring framework — where semantic actions are a synthesized-attribute fold (children before parents, no inherited / left-sibling→right-sibling flow, per the Loup Vaillant model Chalk aligns to) — the right design, or a forced fit?** The findings below are diagnosis only.

## Strengths

### [S1] Filtering semirings are cleanly decoupled from the IR layer
- **Category:** S3 (loose coupling) / S4 (dependency direction)
- **Impact:** High
- **Explanation:** Boolean/Precedence/TypeInference/Structural touch only their own annotation slot — none reference `->graph`, `->bindings`, `->control_head`, `->factory`, or `->mop`. The disambiguation half is fully independent of IR construction.
- **Evidence:** grep for IR-field access across the four filter semirings returns NONE; `Precedence.pm:653` `slot_name { 'precedence' }` reads only `annotations->{precedence}`.
- **Found by:** Coupling, Structure

### [S2] Slot-based composite is open/closed for filtering components
- **Category:** S3 (loose coupling) / S14 (pragmatic abstraction)
- **Impact:** High
- **Explanation:** `FilterComposite` discovers components structurally via `slot_name()` and dispatches `multiply`/`add`/`is_zero` polymorphically. A new filtering semiring slots in without touching the composite core.
- **Evidence:** `FilterComposite.pm:48-52` `grep { blessed($_) && $_->can('slot_name') && defined $_->slot_name() }`; uniform dispatch loop `:257-268`.
- **Found by:** Coupling

### [S3] Context comonad core is cohesive and faithful to the model
- **Category:** S2 (cohesion) / S13 (domain modeling)
- **Impact:** Medium-High
- **Explanation:** `extract`/`extend`/`duplicate` + the iterative tree-walk family are a tight, immutable, single-purpose set modeling the synthesized-attribute fold. Iterative (not recursive) walks avoid deep-stack issues on tall trees.
- **Evidence:** `Context.pm:24-170`. Marred only by the later `cfg_state` accretion (F-Struct).
- **Found by:** Structure

### [S4] Immutability held under the in-flight divorce; control_head migration well-pinned
- **Category:** S11 (testability) / S13
- **Impact:** Medium
- **Explanation:** Every mutation path returns a new Context via `->new`; hash-cons identity preserved. The C1 `control_head` field has a focused unit test (`context-control-head.t`) covering default/constructor/extend/override — the disciplined shadow-field-then-migrate sequencing is bisect-friendly.
- **Evidence:** `context-control-head.t`; `Context.pm:52`, `_mul_ctx`, `cfg_state` threading.
- **Found by:** Code-Quality, Structure

### [S5] Disambiguation observability behind zero-cost env flags
- **Category:** S8 (observability)
- **Impact:** Medium
- **Explanation:** `CHALK_COUNT_FILTER_TIES` / `CHALK_TIE_CONTEXT` / `CHALK_AUDIT_FILTER` instrument the filter-tie path (rule, position, per-component verdicts) with no production cost when unset.
- **Evidence:** `FilterComposite.pm:383-427`.
- **Found by:** Error-Handling, Integration

### [S6] Per-parse factory unification gives single-owner node identity
- **Category:** S13 (domain modeling)
- **Impact:** Medium
- **Explanation:** `_one_ctx` seeds the Context's factory; `_mul_ctx` propagates one factory through every merge. Cross-factory Start identity (a prior blocker) is resolved.
- **Evidence:** `SemanticAction.pm:74-103`, `:137`.
- **Found by:** Integration

## Flaws / Risks

### [F1] SemanticAction is not a semiring in the same sense as its four siblings — the framework is a forced fit
- **Category:** Flaw 11 (low cohesion) / Flaw 13 (inconsistent boundaries) / Flaw 24 (inconsistent contract)
- **Impact:** High (root finding)
- **Explanation:** The four filter members are pure, hash-consable, associative verdict producers. SemanticAction's `_complete_sa` dispatches arbitrary effectful IR construction, mutates a shared graph, is explicitly NOT hash-consed ("side effects"), and returns `undef` from `slot_name()`. FilterComposite special-cases it (computes `_sa()` separately, threads TI's tags in via `set_type_context`, skips it in `_filter_compare`). It satisfies the semiring *interface* while violating the semiring *contract* (purity, associativity, identity-stable hash-consing) the composite relies on everywhere else. The mailbox (F2) and the Block rebuild (F4) exist *because of* this placement.
- **Evidence:** `SemanticAction.pm:296-298` "Not hash-consed: semantic actions may have side effects"; `FilterComposite.pm:264-283` bespoke TI→SA threading; `SemanticAction.pm:544` `slot_name` returns undef while the four filters return real names.
- **Found by:** Structure, Coupling, Integration

### [F2] Action↔semiring contract runs through class-lexical mutable "mailbox" statics, not return values
- **Category:** Flaw 1 (global mutable state) / Flaw 12 (hidden side effects) / Flaw 27 (temporal coupling)
- **Impact:** High
- **Explanation:** Five class-lexical scalars (`$_pending_scope_update`, `$_pending_graph_update`, `$_pending_annotations_update`, `$_pending_control_head_update`, `$_current_instance`) are the real action-result channel. Actions look like pure `Context -> IRNode` functions but smuggle scope/graph/control/annotations out by mutating these statics; `_complete_sa` clears-then-dispatches-then-applies in a fixed positional order. Class-lexical means not reentrant: a nested complete event would corrupt the outer event's mailbox (no save/restore). A missed clear leaks state across rule completions.
- **Evidence:** `SemanticAction.pm:23-43` declarations; `:299-311` clear+dispatch; `:330-398` apply; ~50 `current_instance`/`update_*` call sites in Actions.pm.
- **Found by:** Structure, Coupling, Integration, Error-Handling

### [F3] Context is a 14-field coupling hub; adding a field requires ~16-site shotgun edits — with a confirmed latent drop
- **Category:** Flaw 3 (tight coupling) / Flaw 6 (leaky abstraction) / Flaw 9 (shotgun surgery)
- **Impact:** High
- **Explanation:** Context mixes pure-comonad mechanics with five payload concerns (bindings, control_head, graph, mop, factory) plus parser metadata. Because it's immutable with no `with`/copy helper, every `Context->new` site must enumerate all fields. There are ~10 such sites in SemanticAction + ~6 in FilterComposite; the C1 `control_head` commit had to touch them all. **VERIFIED LATENT BUG:** the graph-inherit (`:426-439`) and factory-inherit (`:447-460`) rebuild blocks in `_complete_sa` both OMIT `control_head`, silently dropping it to undef when they fire — dormant only because the Block rebuild reconstructs control downstream and masks it.
- **Evidence:** `Context.pm:8-21` (14 fields); `SemanticAction.pm:426-439` and `:447-460` omit `control_head` while sibling blocks at `:344`/`:375`/`:417` include it.
- **Found by:** Coupling, Structure, Code-Quality (latent-drop confirmed by verifier)

### [F4] The Block control-chain rebuild is a load-bearing god-method compensating for the missing left-sibling→right-sibling flow
- **Category:** Flaw 2 (god method) / Flaw 12 (hidden side effects) / Flaw 17 (multiple writers of control edge)
- **Impact:** High
- **Explanation:** `Block()` (~158 lines) does statement collection, exit-type inference, fall-through typing, AND a ~85-line loop that rewires every side-effect node's control input in source order — mutating already-constructed nodes via `set_control_in` and `unmerge`/`merge`. It exists because the synthesized-attribute fold gives statement N+1's action no view of statement N's materialized IR node. Two writers of the control edge: each statement action sets it optimistically (to Start via `control_head // make('Start')`), the Block rebuild overwrites it with the real chain tail. The C4 redundancy audit (commit f3a457f1) confirmed it fires in 22/46 blocks — it is NOT redundant.
- **Evidence:** `Actions.pm:1500-1658`; rebuild loop `:1567-1651`; `set_control_in` at `:1633`, `:1647`.
- **Found by:** Structure, Integration, Error-Handling, Code-Quality

### [F5] Control-threading boilerplate is smeared across ~11 fallback sites + ~16 update call sites, then re-reconciled by the rebuild
- **Category:** Flaw 9 (shotgun surgery) / Flaw 10 (feature envy)
- **Impact:** High
- **Explanation:** Every CFG-producing action re-implements `$ctx->control_head // $factory->make('Start')` then publishes scope/control/graph/annotations through the mailbox. The Block loop then checks `refaddr($existing_ctrl) != refaddr($current_control)` *because the action's guess is usually wrong*. The control-flow contract is spread across many methods plus a reconciliation pass that can disagree with them.
- **Evidence:** 11 `control_head // make('Start')` sites (`Actions.pm:365,1344,1352,1758,2389,2457,2594,2733,2817,2971,3114`); `Block` rebuild's refaddr-mismatch guards.
- **Found by:** Structure, Error-Handling

### [F6] `_transferred_scope` is a write-only DEAD back-channel — a documented repair that is actually inert
- **Category:** Flaw 31 (dead code) / Flaw 12 (hidden side effect) / Flaw 17 (data ownership)
- **Impact:** Medium (VERIFIED: 2 writes, 0 reads)
- **Explanation:** `on_merge` cannot replace `$correct`'s identity (caller holds the ref), so it mutates `$correct->annotations()->{_transferred_scope}`. Nothing in lib/ or t/ ever reads that key. The entire `on_merge` bindings-reconciliation past the zero-guard produces a result that is silently discarded; the comment describes a transfer that does not happen.
- **Evidence:** `SemanticAction.pm:531,538` (only occurrences); verifier grep confirms zero readers.
- **Found by:** Integration, Error-Handling, Code-Quality (cross-confirmed)

### [F7] Three competing owners of "scope": Context.bindings field, mailbox static, and the (dead) annotation channel
- **Category:** Flaw 17 (no clear data ownership) / Flaw 24 (inconsistent contract)
- **Impact:** High
- **Explanation:** The same logical datum (lexical bindings) lives in `Context.bindings` (flows bottom-up via `_merge_bindings`), `$_pending_scope_update` (flows via mailbox, applied in `_complete_sa`), and `annotations->{_transferred_scope}` (dead). `_complete_sa` reconciles field-vs-mailbox (mailbox overrides, then field-inherited-if-absent) but never reconciles the annotation path. No single source of truth.
- **Evidence:** `Context.pm:19`; `SemanticAction.pm:23`, `:330-347`, `:401-420`, `:531`.
- **Found by:** Integration, Coupling

### [F8] No error taxonomy: parse-fail Contexts, bare `die` strings, and silent `// make('Start')` fallbacks coexist; the `error` field is dead
- **Category:** Flaw 20 (weak error handling) / Flaw 34 (inconsistent error conventions)
- **Impact:** High
- **Explanation:** Three unrelated error modalities with no unifying strategy: (a) `zero()`/`is_zero` for parse rejection; (b) ad-hoc `die "..."` with interpolated strings for invariants (no source position) — e.g. `$MAP{$op} // die "Unknown op"` hard-aborts a whole compile on grammar/map drift; (c) silent `// $factory->make('Start')` masking missing control. **VERIFIED:** the `error` Context field is propagated through ~7 rebuilds but NEVER assigned a non-undef value — dead infrastructure.
- **Evidence:** `Context.pm:16` field; verifier confirms only `error => $x->error()` propagation, no origination; `die` sites at `Actions.pm:814,817,1899,1961,2329,2396,2463,2583`.
- **Found by:** Error-Handling (error-field death verified)

### [F9] The correctness assert that guarded control wiring was added (C2) then deleted (C3) with no replacement
- **Category:** Flaw 20 (weak error handling)
- **Impact:** Medium-High
- **Explanation:** C2 added `die "control_head/scope.control divergence..."` at the top of `_complete_sa`. C3 deleted it ("no second path to check" — valid for the *divergence* check, since `scope.control` is gone). But nothing now asserts `control_head` is non-undef / on-chain where required; the `// make('Start')` fallbacks (F5) absorb exactly the mis-wiring the assert would have caught. A correctness check was removed and the silent-fallback gap it covered was not closed.
- **Evidence:** commit 9d18c032 (added) / 959f82cd (deleted); fallbacks at the 11 sites in F5.
- **Found by:** Error-Handling

### [F10] Observability is absent exactly where the wiring happens
- **Category:** Flaw 21 (no observability)
- **Impact:** Medium-High
- **Explanation:** Precedence has ~20 `DEBUG_PRECEDENCE` warns and FilterComposite has the env-flag audit (S5), but SemanticAction's `_complete_sa` (fires every action, mutates the graph) and the Block rebuild (the load-bearing control wiring) have ZERO tracing. There is no hook to observe `control_head` evolution or before/after chain state — the place most likely to harbor a mis-wiring bug is the least observable.
- **Evidence:** no warn/DEBUG/trace in SemanticAction.pm / Context.pm / Actions.pm Block; contrast `Precedence.pm:152-489`.
- **Found by:** Error-Handling

### [F11] Per-parse config is process-global class state requiring `reset_cache` discipline; incomplete reset
- **Category:** Flaw 22 (config sprawl) / Flaw 23 (DI misuse)
- **Impact:** Medium-High
- **Explanation:** `set_mop`/`set_factory` write class-lexicals shared across all instances and invalidate `$_one_singleton`. Actions.pm pushes the factory in via `set_factory` from an ADJUST block (wrong-direction, F12). Two parses can't coexist; tests must call `reset_cache` (59 test files do). **And `reset_cache` clears only `%_ctx_cache` + the two singletons** — not `$_mop`, `$_factory`, `$_type_context`, or the four pending statics, so an aborted parse leaks state into the next.
- **Evidence:** `SemanticAction.pm:241,252` setters; `:194-198` partial reset; `Actions.pm:96` `set_factory` in ADJUST.
- **Found by:** Error-Handling, Coupling, Code-Quality

### [F12] Wrong-direction dependency: the action callback table reaches back into the semiring engine
- **Category:** Flaw 4 (unstable dependency) / Flaw 27 (temporal coupling)
- **Impact:** Medium-High
- **Explanation:** Actions.pm is dispatched BY the semiring (`$actions->$rule_name($ctx)`) yet calls back into the semiring class statically for `current_instance`, `current_type_context`, and `set_factory` — a circular runtime dependency. It also bakes in the FilterComposite ordering invariant (TI must run before SA so `current_type_context` is populated).
- **Evidence:** `Actions.pm:96`, `:813`; `FilterComposite.pm:264-283`.
- **Found by:** Coupling

### [F13] `cfg_state` and `@_cfg_struct_keys` push IR/CFG vocabulary into the generic comonad
- **Category:** Flaw 10 (misplaced method) / Flaw 28 (magic strings) / Flaw 29 (dumping ground)
- **Impact:** Medium
- **Explanation:** Context (a generic comonad) has accreted a `cfg_state` walker that knows compiler concepts (`if_node`, `loop`, `try_node`, ...) as a hardcoded 18-element `@_cfg_struct_keys` whitelist, and inspects IR node `->operation eq 'Start'`. Adding a CFG annotation requires editing the comonad. The reconstruction relies on a co-existence invariant (control_head ⇒ bindings) that is documented in prose but not enforced.
- **Evidence:** `Context.pm:189-196` key list; `:224` operation-string inspection; `:216-218` prose invariant.
- **Found by:** Structure, Coupling, Integration, Error-Handling

### [F14] Stalled-migration residue: `scope()` shim, dual opt-keys, `update_scope` misnaming, stale comments
- **Category:** Flaw 31 (dead code / drift)
- **Impact:** Low-Medium
- **Explanation:** `Context.scope()` shim + `scope` extend opt-key are annotated "deleted in C5" but C4 is blocked, stalling C5. `update_scope` writes the `bindings` field (no `update_bindings` exists). Comments still reference `Scope.control` and `should_scan`, both removed. Classic 80-90%-migration drift the project's own CLAUDE.md warns about.
- **Evidence:** `Context.pm:31,50`; `SemanticAction.pm:203`; stale comments `Structural.pm:363`, `Actions.pm:1570,1640`.
- **Found by:** Code-Quality, Coupling

### [F15] Duplicated tree-walkers/extractors across TypeInference.pm and TypeInferenceActions.pm
- **Category:** Flaw 31 (copy-paste divergence)
- **Impact:** Medium
- **Explanation:** Two near-identical depth-tracked prune-capable walkers (`_walk_annotations` vs `_walk_ann`) plus four `_get_*` extractors reimplemented in both files, with prune semantics independently coded — divergence-prone in a correctness-critical disambiguation layer.
- **Evidence:** `TypeInference.pm:83` vs `TypeInferenceActions.pm:19`; overlapping `_get_rightmost_type`/`_get_call_symbol`/`_get_item_types`/`_get_list_arity`.
- **Found by:** Code-Quality

### [F16] The load-bearing Block rebuild + cfg_state + on_merge have no isolated unit tests
- **Category:** Flaw 32 (missing critical-path coverage)
- **Impact:** High
- **Explanation:** The rebuild is exercised only through full end-to-end grammar parses (build the generated grammar, eval, parse source). No test constructs a Block Context with known sibling side-effect nodes and asserts the resulting `inputs[0]` wiring directly. A regression in the rewire branches surfaces only as a downstream golden/codegen diff. This is *why C4 is hard to land safely* — there is no behavioral unit spec to retire the rebuild against.
- **Evidence:** `mop/build-graph-control-chain.t` drives via `perl_pipeline`+`eval`; no direct Block-rebuild unit test; `on_merge` tested only for the zero no-op.
- **Found by:** Code-Quality

### [F17] Idempotency/order-sensitivity: side-effecting multiply can re-run and double-merge on packed-ambiguity distribution
- **Category:** Flaw 19 (idempotency, reinterpreted for in-process pipeline)
- **Impact:** Medium
- **Explanation:** `_complete_sa` is not hash-consed and mutates the graph; `FilterComposite.add`/`multiply` distribute over packed-ambiguity survivors, which can fire the same complete action once per alternative, each re-running side effects (graph merges). The Block rebuild then unmerges/merges again. The only guard against double-merge is `Graph::merge`'s own hash-cons idempotency.
- **Evidence:** `SemanticAction.pm:296-298`; `FilterComposite.pm:234-246`.
- **Found by:** Integration

## Coverage Checklist

### Flaw/Risk Types 1–34
| # | Type | Status | Finding |
|---|------|--------|---------|
| 1 | Global mutable state | Observed | F2, F11 |
| 2 | God object | Observed | F4 |
| 3 | Tight coupling | Observed | F3 |
| 4 | High/unstable dependencies | Observed | F12 |
| 5 | Circular dependencies | Observed (runtime) | F12 |
| 6 | Leaky abstractions | Observed | F3, F13 |
| 7 | Over-abstraction | Observed (minor, Precedence) | — |
| 8 | Premature optimization | Not observed | — |
| 9 | Shotgun surgery | Observed | F3, F5 |
| 10 | Feature envy / anemic domain | Observed | F5, F13 |
| 11 | Low cohesion | Observed | F1 |
| 12 | Hidden side effects | Observed | F2, F4, F6 |
| 13 | Inconsistent boundaries | Observed | F1 |
| 14 | Distributed monolith | Not applicable | single process |
| 15 | Chatty service calls | Not applicable | single process |
| 16 | Synchronous-only integration | Not applicable | single process |
| 17 | No clear data ownership | Observed | F6, F7 |
| 18 | Shared database | Not applicable | single process |
| 19 | Lack of idempotency | Observed | F17 |
| 20 | Weak error handling | Observed | F8, F9 |
| 21 | No observability | Observed | F10 |
| 22 | Configuration sprawl | Observed | F11 |
| 23 | DI misuse | Observed | F11 |
| 24 | Inconsistent API contracts | Observed | F1, F7 |
| 25 | Business logic in UI | Not applicable | no UI |
| 26 | Poor transactional boundaries | Not applicable | single process |
| 27 | Temporal coupling | Observed | F2, F12 |
| 28 | Magic numbers/strings | Observed | F13 |
| 29 | Utility dumping ground | Observed (minor) | F13 |
| 30 | Security as afterthought | Not applicable | compiler, no attack surface in layer |
| 31 | Dead code / unused deps | Observed | F6, F14, F15 |
| 32 | Missing critical-path test coverage | Observed | F16 |
| 33 | Hard-coded credentials | Not applicable | none |
| 34 | Inconsistent error/logging conventions | Observed | F8 |

### Strength Categories S1–S14
| # | Category | Status | Finding |
|---|----------|--------|---------|
| S1 | Clear modular boundaries | Observed (filter half) | S1 |
| S2 | High cohesion | Observed (Context core) | S3 |
| S3 | Loose coupling | Observed (filter half) | S1, S2 |
| S4 | Stable dependency direction | Observed (filter half) / violated (SA half) | S1 / F12 |
| S5 | Dependency management hygiene | Not assessed | — |
| S6 | Consistent API contracts | Not observed | (F1, F7 are the inverse) |
| S7 | Robust error handling | Not observed | (F8 is the inverse) |
| S8 | Observability present | Observed (filter/precedence only) | S5 |
| S9 | Configuration discipline | Not observed | (F11 is the inverse) |
| S10 | Security built-in | Not applicable | — |
| S11 | Testability & coverage | Partial | S4 / F16, F7-test |
| S12 | Resilience patterns | Observed (ambiguity packing) | (Integration partial) |
| S13 | Domain modeling strength | Observed | S3, S6 |
| S14 | Simple, pragmatic abstractions | Observed (slot composite) | S2 |

## Hotspots

1. `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — the mailbox statics (F2), the non-semiring contract (F1), the dead `_transferred_scope` channel (F6), the `control_head`-dropping inherit blocks (F3 latent bug), the deleted assert (F9). The center of gravity for the whole question.
2. `lib/Chalk/Bootstrap/Perl/Actions.pm` Block() at 1500-1658 — the load-bearing rebuild (F4), the smeared control boilerplate (F5), no unit coverage (F16).
3. `lib/Chalk/Bootstrap/Context.pm` — the 14-field hub (F3), CFG vocabulary leak (F13), stalled-migration residue (F14).

## Next Questions

1. Is the synthesized-attribute fold (no inherited / sibling flow) an immovable constraint of the Earley-semiring composition, or could a post-parse `act`-over-Context pass (where left-to-right state is natural) replace the mailbox + Block rebuild without breaking disambiguation?
2. Does IR construction *need* to interleave with parsing/disambiguation at all, or could the parse produce a disambiguated Context tree that a separate pass then folds into IR?
3. If SemanticAction's side effects were removed from the semiring product, would the four pure filters compose more simply (no `_wrap_sa_result`, no TI→SA `set_type_context`, no SA skip in `_filter_compare`)?
4. What is the actual cost of the `control_head`-dropping inherit blocks (F3) — is there an input that reaches them with a live control_head that the Block rebuild does NOT later reconstruct?
5. Can the load-bearing Block rebuild be given a behavioral unit spec (F16) independent of end-to-end goldens, so any future restructuring has a safety net?

## Analysis Metadata

- **Agents dispatched:** Structure & Boundaries, Coupling & Dependencies, Integration & Data, Error Handling & Observability, Security & Code Quality (5 parallel specialists) + orchestrator verification pass
- **Scope:** lib/Chalk/Bootstrap/Semiring/*.pm (7 files), Context.pm, Perl/Actions.pm — ~6,700 lines
- **Raw findings:** ~40 across specialists
- **Verified findings:** 17 flaws + 6 strengths (after dedup + code-confirmation)
- **Cross-specialist agreement:** F1 (3 agents), F2 (4), F3 (3), F4 (4), F6 (3), F7 (2) — high-agreement findings are the most reliable
- **Verifier-confirmed against code:** _transferred_scope dead (2 writes/0 reads), error field never set, control_head dropped in 2 inherit blocks
- **Steering files consulted:** CLAUDE.md (project + global), block_action_workaround_accretion.md, phase_3a_migration_cross_stmt_scope.md
