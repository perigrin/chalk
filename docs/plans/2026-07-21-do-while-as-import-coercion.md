# do/while as an OpTree->SoNGraph import coercion (illustrative first cell)

ABOUTME: Implements do{}while/until lowering as a structured import-coercion,
ABOUTME: the smallest real example that makes the OpTree-import-boundary concrete.

Date: 2026-07-21
Status: DESIGN (capture) — pending assess -> refine -> chain-review -> execute

## Purpose: illustrate the change, on a real GAP

This is NOT a miscompile fix. Verified on head (perl5-son pu): every non-folded
`do{}while`/`until` form GAPs LOUDLY ("loop without a lowerable condition") — the
GAP-not-miscompile invariant is upheld. do/while simply does not LOWER yet.

We implement it as the FIRST DELIBERATELY-STRUCTURED import coercion, to make the
"OpTree->SoNGraph is a foreign-function import boundary" reframe concrete instead
of philosophical (see memory: optree-import-boundary). do/while is the ideal
vehicle: it is a small, self-contained shape that currently GAPs, and its
post-test semantics force the coercion to CARRY structure (entry-order) that the
existing pre-test walk destroys.

## Honest framing (what survived adversarial verification)

- **Import boundary: YES.** B::SoN reads perl's optree via B reflection
  (`$op->name`/`->next`/`->first`/`->targ`). The OpTree->SoNGraph walk is a
  genuine importer from a foreign compiler's IR. Self-hosting bypasses OpTree
  entirely (Earley SourceText->SoN direct), so this coercion is permanently
  gen-0 bootstrap tooling by nature, not a weakness.
- **Clean cell table: NO.** The `$op->name` if-chain in FromOptree.pm:174 is
  recursive-descent-WITH-SHARED-STATE — arms share `$sim`, `%visited`,
  `$ctx->{pending_method}`, `@exits`, and each steers the cursor. So this doc
  does NOT pretend do/while is "add an independent cell to a registry." It adds
  a NAMED SUB-COERCION (`_import_dowhile`) that participates in the shared walk
  but is a self-contained, testable OpTree-shape -> SoNGraph-shape mapping. The
  illustration is: what a structured import sub-coercion looks like GIVEN the
  stateful mechanism — the honest middle, not the aspirational registry.

## The FROM shape: the real do/while optree (verified 2026-07-21)

`do { $x = $x + 1 } while $x < 3;` compiles to (B::Concise on the CV):
```
e  <@> leave vK*                 <- do-block scope wrapper (NOT enterloop)
5     <0> enter v                <- scope entry
d     <|> and(other->6)          <- THE LOOP: logical-and with a back-edge
c        <2> lt   ($x < 3)       <-   condition, tested at the TAIL
         ... body: add[$x] ...   <-   body ops, inside the and's other-branch
9        <0> unstack             <-   back-edge -> jumps to #a (the condition)
```
Discriminant vs a plain `while` (which uses `enterloop`/`leaveloop`): do/while is
a `leave`/`enter` scope wrapping an `and(other->body)` whose back-edge `unstack`
targets the CONDITION, with the body reached FIRST on entry. This is a SIBLING of
the `_is_postfix_while` statement-modifier shape (also enter/unstack based),
distinguished by the do-block scope wrapper. Detection therefore belongs next to
`_is_postfix_while` in the `enter` handler (FromOptree.pm:536/2246), which today
returns false for this shape.

## The TO shape: a post-test Loop/Phi SoNGraph

A pre-test `while` imports to: `Loop(header) -> If(cond) -> [body Proj | exit
Proj]`, condition-first. The post-test coercion imports the SAME Loop/Phi
vocabulary but with the ENTRY EDGE into the body:
```
  preheader --> BODY --> header(test cond) --> [back to BODY | exit]
```
i.e. the body block is the loop ENTRY (runs unconditionally once); the condition
rides the back-edge. The value merge (Phi) is unchanged in kind — the loop-carried
slot's Phi takes [init-from-preheader, back-edge-from-body-end] as usual; only the
control entry differs.

## The coercion, in three honest pieces

1. **Discriminate (producer, FromOptree.pm `enter` handler ~:536):** recognize the
   do-block-scope + `and(other->body)` + tail `unstack` shape as post-test.
   Sibling to `_is_postfix_while`; returns a `post_test` marker.
2. **Import (producer, `_import_dowhile` / a `post_test => 1` arg to the existing
   `_translate_while_loop`):** walk BODY-first, condition on the back-edge, emit
   the Loop with body-as-entry. Reuses the existing Loop/Proj/Region/Phi
   construction (`$factory->make_cfg('Loop', ...)`, :2595) — the ONLY difference
   from the pre-test path is walk order + which control edge enters the body.
3. **Carry the distinction (defaulted, zero blast radius):** post-test-ness rides
   as a `post_test` flag DEFAULTING to pre-test. Do NOT add a required field to
   the Loop schema (NodeFactory.pm:137) — Chalk::IR is a VENDORED COPY in
   perl5-son (two Loop.pm files), a required :param breaks every construction site
   in both repos, and `= false` defaults break B::SoN self-hosting (use omit /
   `= undef`). Consing is safe: Loop is ROUTED_CFG, allocated not content-hashed
   (NodeFactory.pm:125).
4. **Lower (backend, chalk Context.pm `_process_loop_node` :2326):** when
   post-test, the preheader's entry edge targets the BODY block, not the header;
   the existing header test runs on the back-edge. ~5 lines; pre-test unchanged.
5. **Wire format:** `post_test` must round-trip through SoN/Serialize/JSON.pm
   (producer) and chalk IR/Serialize/JSON.pm (loader) — a defaulted scalar, omit =
   pre-test.

## Scope fence

**IN:** discriminate + `_import_dowhile` + defaulted `post_test` carrier + wire
format + backend entry-edge branch + RED corpus cases + the illustrative doc value.
**OUT:** the `$op->name` if-chain -> registry refactor (needs the shared state
untangled first — separate, large); foreach/nested/headless loops (different
shapes / backend-only); the value-lattice coerce vtable (unrelated).

## Acceptance (self-verified corpus gate mandatory, coordinator-run)

- RED first: corpus cases that currently GAP and must turn GREEN —
  `do{$x=$x+1}while $x<3; $x` (expect 3) and a bilateral `until` twin
  (`do{$x--}until $x<1`). Bilateral: one that runs the body multiple times, one
  that runs it exactly once (`do{$x++}while 0` already folds to 1 — keep as a
  guard that folding still works).
- After: the GAP cases LOWER and lli==perl; `t/bootstrap/corpus/son-corpus-wide.t`
  gate-green floor NOT regressed, worklist behaves as designed (coordinator runs
  it, never a subagent self-report).
- mod.t tests 14 + 15 lower (the drain target).
- No pre-test loop corpus case regresses (pre-test path untouched).

## Evidence base (verified 2026-07-21)

- Real do/while optree shape: B::Concise on the CV (dumped this session).
- do/while GAPs loudly today (not a miscompile): matrix run this session; issue
  019f7786-d690 reclassified MISCOMPILE->GAP.
- Producer single head-test Loop build: FromOptree.pm:2595, :517-520.
- `_is_postfix_while` (the sibling shape): FromOptree.pm:526-547, :2246.
- Backend single loop lowering: Context.pm:2326.
- Loop schema / routed-not-consed: NodeFactory.pm:137, :125.
- Vendored Chalk::IR in perl5-son (two Loop.pm): ~/dev/perl5-son/lib/Chalk/IR/Node/Loop.pm.
- Import-boundary reframe (import: yes, cell-table: no): memory optree-import-boundary.
