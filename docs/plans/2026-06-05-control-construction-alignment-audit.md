# Control-Construction Alignment Audit — Option X vs During-Parse (Option Y)

**Date:** 2026-06-05
**Branch:** phase1-lateral-bindings @ 5c15aa5f (clean tree; `git diff --stat lib/ t/` empty at start and end)
**Auditor role:** read-only. No `lib/` or `t/` modifications. Probes ran in `/tmp` and were deleted.
**Subject:** is the current design's recommendation — **Option X** (post-parse Block rebuild is the
system of record for `control_in`; retire the during-parse lateral-seed channel) — well-founded, or
does it discard a genuinely-better during-parse path (**Option Y**) prematurely?

**Documents audited (in trajectory order):**
- `2026-06-02-control-wiring-trio-comparison.md` (trio + execution log; "rebuild stays as oracle, delete LAST")
- `2026-06-04-rebuild-deletion-readiness-audit.md` + `-rerun.md` + `2026-06-05-...-pass3.md` + `-pass4.md` (four passes, five leaks)
- `2026-06-05-clean-control-construction-design.md` @ ccee2d05 (the current Option-X recommendation)
- (Note: the brief named `2026-06-05-control-head-leak-suppression-design.md`; **that file does not exist** in the repo. The leak-suppression reasoning lives inline in the pass3/pass4 audits' "suggested remediation" sections.)

---

## (1) VERDICT on the central question: **GREEN — Option X is sound; construction-time `control_in` buys nothing concrete.**

**The central question** — does correct `control_in` *at construction time (during parse)* have concrete
value for a plausible future scheduler, or is correct *at schedule/hand-off time* (which the post-pass
provides) sufficient? — resolves decisively in favor of **correct-at-hand-off is sufficient**.

The honest answer is the one the brief flagged as decisive: **no plausible scheduler Chalk might adopt
needs construction-time `control_in`; correct-at-hand-off is the universal contract.** Therefore Option X
loses nothing real, and the during-parse channel's only distinctive property (correctness *observable
during parsing*) has **zero consumer** in the codebase. This is not anchored on EagerPinning — see (2).

Three independent lines of evidence converge:

1. **There is no mid-parse `control_in` reader (grep-confirmed, (3) below).** Every consumer of
   `control_in` runs after the parse completes: the scheduler (`EagerPinning`, on `$method->graph`),
   the post-parse reachability seed (`_finalize_body_graph`), and a small set of in-action *propagation*
   helpers that only *write* or *defined-guard*. No optimizer pass (DCE, Pass, StructPromotion) reads
   control for any decision. The parser itself does not read `control_in` to steer parsing. So
   "correctness during parse" is observable by nothing.

2. **The post-pass demonstrably corrects the exact case the channel breaks (probe, (5) below).** For
   `my $a=1; my $b=foo() if $c; return $a;` the rebuild-ON output is correct (single, properly-nested
   `my $b`); rebuild-OFF double-emits. The IR handed to any scheduler under Option X is correct.

3. **The June-2 adversarial pair already reached this conclusion, and four subsequent passes vindicated
   it.** The trio's Proposal 3 stated plainly: "in the byte-compat round-trip era, deferring control
   placement buys NOTHING ... the Click-1995 'control is a scheduling concern' justification does not
   apply yet." The team nonetheless pursued the during-parse capstone (Proposal 1) and hit **five leaks
   across four readiness audits** — all the same family (postfix, C-for my-init, elsif, C-for bare-init,
   my-decl-postfix). Option X is a *return* to the June-2 conclusion, now backed by the failure record
   the override produced. That is well-founded, not premature.

**Why Option X is not merely "good enough" but architecturally correct here:** the durable invariant the
design names (`CONSTRAINT`, Fact 2) is "the IR's `control_in` edges are correct *when a consumer reads
them*." Every consumer reads post-parse. A post-pass over the materialized source-ordered `@stmts` is
*correct by construction* over that order — no construct can escape an exhaustive O(n) iteration — whereas
the during-parse channel must independently solve a leak problem at every construct that hoists or
self-publishes a control node, with no fire-time visibility of whether it is at a statement boundary
(`update_control_head` is a single shared mutable slot, `SemanticAction.pm`, conflating "advance the
sibling chain" with "I am a sub-expression"). The asymmetry is structural, not incidental.

**One YELLOW caveat that does not change the verdict (see (4)):** the design has an internal
plan-vs-code contradiction about whether the rebuild's `merge()` calls are redundant. It does not affect
the X-vs-Y decision (both end states keep a graph that includes every node), but it must be resolved
before the deletion lands, and the design's own Part 5 already flags it as "DECISION NEEDED."

---

## (2) GCM / scheduler evidence (the scheduler-independent argument)

The user's explicit constraint: the decision must NOT be anchored on EagerPinning (a placeholder slated
for GCM or other). So the argument must hold for *any plausible* Sea-of-Nodes scheduler.

**Click & Paleczny 1995, "A Simple Graph-Based Intermediate Representation" / Click's GVN-GCM
(PLDI'95 "Global Code Motion / Global Value Numbering").** GCM operates in distinct phases over a
**completed graph**:
- It first builds the **dominator tree** and identifies loop nesting from the CFG. This requires a
  *complete, correct* CFG — but it reads that CFG once, at schedule entry, not incrementally during IR
  construction. The dominator tree is computed *from* the finished control edges; it has no notion of
  "when" those edges were written.
- It then computes **schedule-early** (each node as early as its inputs' dominator-tree depth allows) and
  **schedule-late** (as late as its uses allow), and places each node in the block on the dominator path
  between early and late with the *least loop depth*. Both passes consume the completed control/dominator
  structure as ground truth.

There is nothing in GCM that distinguishes "control_in correct since IR construction" from "control_in
correct since a post-pass rewired it 5ms ago." GCM's input contract is *a correct graph at the moment
GCM starts*. Option X satisfies that contract exactly.

**Cliff Click's early/late scheduling** is the canonical "schedule from a completed graph" design; it is
the strongest version of "correct-at-schedule-entry is the universal contract." It positively argues
*against* construction-time placement: the entire point of GCM is that the IR is built *without*
committing to a schedule, and placement is decided later from data/control dependence. A scheduler in
that tradition would actively prefer that `control_in` express only *true* control dependence (which
side-effect ordering is) and be free of premature placement — which is precisely what the post-pass
produces and what a leaky channel pollutes.

**Braun et al. 2013, "Simple and Efficient Construction of Static Single Assignment Form"** (already
referenced in this project) constructs SSA *during* IR building — but the thing it needs correct during
construction is the **sealing of basic blocks and predecessor edges of the CFG**, i.e. the block
structure, *not* a per-statement side-effect `control_in` chain. Braun's incremental requirement is
"a block's predecessors are known before its phis are resolved." Chalk's `control_in` here is the
linear effect chain within a block, a different object. Even granting a future Braun-style front end,
its construction-time need is *block predecessor completeness*, which the Block action already
establishes (it materializes `@stmts` and the if/loop region structure); it does not need the
side-effect `control_in` to be correct at each action's fire time.

**Conclusion of the literature scan:** every scheduler design Chalk plausibly adopts — GCM/GVN-GCM
(Click/Paleczny), early/late (Click), or a Braun-style SSA front end — consumes a *completed* graph or
needs *block-structure* completeness, neither of which requires the side-effect `control_in` edge to be
correct at IR-construction time. **No plausible scheduler benefits from construction-time `control_in`
over correct-at-hand-off.** If a future GCM design ever did surface such a need, the design's Part 8
prescribes the right response: build a *structurally* leak-free two-pass construction against concrete
requirements — not resurrect the leaky channel. That is sound.

---

## (3) Mid-parse `control_in` reader grep — result: **NONE**

Exhaustive grep of `lib/` for `control_in` readers, classified by *when* they run and *whether* they
read for a decision:

| Site | Runs | Reads control for a decision? |
|---|---|---|
| `IR/Scheduler/EagerPinning.pm` (58,66,71,105,111,123) | **post-parse** (schedule time, on `$method->graph`) | yes — but post-parse, the sanctioned consumer |
| `Actions.pm:1130` (`_finalize_body_graph`) | **post-parse** (graph finalize, `defined`-guarded) | reachability seed, not ordering |
| `Actions.pm:121` (`_thread_control_head`) | during parse | **no** — `defined`-guard then *writes* |
| `Actions.pm:2416` (init-fold copy) | during parse | **no** — *copies* control onto refined VarDecl |
| `Actions.pm:3226` (C-for rewire guard) | during parse | **no** — writer-side `refaddr` comparison |
| `Actions.pm:1692/1709/1731/1744` (the rebuild) | **post-parse** (Block action, after children fire) | the code under audit |
| `Target/Perl.pm:877`, `EmitHelpers.pm:2266`, `StructPromotion.pm:395` | post-parse codegen | **no** — read `->value()` (inputs[0]), not control |
| `IR/Node/{If,Loop,Region,VarDecl}.pm` | accessor defs | n/a |
| `Optimizer/DCE.pm`, `Optimizer/Pass.pm` | post-parse | **no control reads at all** (grep empty) |

**No parser-internal, value-numbering, or optimizer pass reads `control_in` mid-parse to make any
decision.** The during-parse channel's distinctive property — `control_in` correct *while parsing* — has
no consumer. This is the decisive empirical fact behind the GREEN verdict: Option X cannot lose a
correctness property nothing observes.

---

## (4) Merge keep-vs-delete — **definitive answer: KEEP a merge-only hygiene loop (do NOT delete the merges).** And a flagged plan-vs-code contradiction.

This is the one place the design and its own predecessor audits **directly contradict each other**, and
the brief's "VERIFIED FACT" sided with the design. I must report the contradiction honestly:

- **Current design, FACT 1 (ccee2d05):** the merges (`Actions.pm:1678/1691/1729`) are **REDUNDANT** —
  with them disabled behind a `$ENV{CHALK_NO_MERGE}` guard, gates stayed green and the orphan VarDecl
  stayed reachable via the `control_in` closure. Recommends deleting them (option b) "for cleanliness."
- **Pass-4 audit, Dimension 4 (d7070e25):** the merges are **LOAD-BEARING** — an independent
  closure probe (roots = Returns + CFG nodes, edges = inputs + control_in) **missed one top-level
  VarDecl** that was in `$graph->nodes` *only* because the rebuild's `merge($s)` put it there.
  "Wholesale deletion must retain a merge-only hygiene loop."

These cannot both be true as stated. I attempted the in-tree experiment but it requires editing `lib/`
(the `$ENV{CHALK_NO_MERGE}` guard FACT 1 describes is **not present in the code at HEAD** — it was a
temporary edit, reverted). An out-of-tree probe via `MethodInfo->graph->nodes()` returned a malformed
node list in the isolated harness (a raw ARRAY element leaked through the topo-sort), so I could not
reproduce either result cleanly read-only.

**Root-cause analysis of the contradiction (from the code, which I *can* read):**
`merge()` keys by `content_hash()`; `_seed()` (the closure's tool) keys by `id()`. Per Proposal-2
(d01bfea3), **VarDecl's `content_hash()` returns its unique id** — so for VarDecl, merge and seed key
identically, and a VarDecl reached by the closure *would* be deduplicated against a merged one. The
difference between the two audits is therefore **which roots the closure walks**: pass-4's probe rooted
at explicit Returns + schedule CFG nodes; FACT 1 used the *actual* `_finalize_body_graph`, which also
**synthesizes an implicit Return** (`Actions.pm:1056-1073`) whose `control_in` is seeded back into the
chain (it walks `reverse @fixed_body` to find the leading VarDecl). For a no-explicit-return body, that
synthetic Return is the bridge that reaches the orphan via `control_in`; a probe that omits it misses
the node. **The two audits measured different graphs.** FACT 1's measurement is the production one
(`_finalize_body_graph` always runs), so FACT 1 is *more likely* correct for the standard Perl-codegen
path — but pass-4's probe may have exposed a real gap in the *init-fold refined-node* case it described
(`AssignmentExpression` unmerges the bare VarDecl and merges the refined one; the refined node's id may
not be reachable from a Return when its consumer is itself rebuilt).

**Definitive recommendation:** **KEEP the merges as a thin, unconditional merge-only hygiene loop**
(the conservative option both pass-3 Prereq C and pass-4 Prereq C reached). Reasons:
- The grep for `$graph->nodes`-iterating consumers (the brief's secondary ask) finds **four** sites —
  `Target/Perl.pm:467` (aggregate sigils), `Actions.pm:839` (Call-target resolution),
  `IR/Serialize/JSON.pm:97` (serialization), and `DCE.pm:39` (uses `$input->nodes()` as the DCE root
  set). **None of these follow `control_in`+`inputs` themselves** — they take `$graph->nodes()`
  membership *as given*. (DCE.pm:39 is the most consequential: if a merge is load-bearing, a node
  missing from `nodes()` would be invisible to dead-code elimination's root set.) If a
  merge is load-bearing for even one method (pass-4's finding), one of these four would silently drop a
  node. The cost of keeping the merges is ~3 lines and one O(n) pass; the cost of being wrong is a
  dropped node in serialization or sigil aggregation. **Correctness > cleanliness** (project principle).
- FACT 1's "redundant" claim is only proven for the *gates that ran*, and only via a guard not in the
  tree. Deleting on that basis is exactly the "80–90% migration that drifts" pattern CLAUDE.md warns
  against. The design's Part 5 already flags this honestly as "DECISION NEEDED ... do not leave as
  unexamined residue" — so resolve it toward KEEP.

This does not change the X-vs-Y verdict (both end states retain a complete graph). It is a deletion-time
correctness gate, not an architecture choice.

---

## (5) #5 / #6 post-pass-corrects confirmation — **CONFIRMED for #5**

Direct probe (rebuild ON vs OFF via the `_generate_from_schedule` path, the same the
byte-compat-schedule gate uses), source `my $a=1; my $b=foo() if $c; return $a;`:

```
=== REBUILD ON ===                  === REBUILD OFF ===
    my $a = 1;                          my $a = 1;
    if ($c) {                           my $b = foo();      <-- SPURIOUS top-level duplicate
        my $b = foo();                  if ($c) {
    }                                       my $b = foo();
    return $a;                          }
                                        return $a;
ON: count of 'my $b' = 1 (correct)  OFF: count of 'my $b' = 2 (double-emit)
```

- **#5 post-pass corrects: YES.** Rebuild-ON produces correct, single, properly-nested codegen. The
  design's claim that "#5 is NOT worth fixing as a channel fix — the post-pass overwrites the leak" is
  **verified**. Fixing it in the channel would build infrastructure for a mechanism being deleted.
- **This same probe confirms FACT 3** (a leak corrupts the graph — double-emit — not just one edge) and
  is the most concrete single piece of evidence that Option X degrades gracefully where Y degrades into
  graph corruption.
- **#6 (StructPromotion.pm):** not independently re-probed here (pass-4 could not minimally isolate it
  and it is entangled with that file's *pre-existing* both-modes-broken codegen + the orthogonal
  `StructPromotion.pm:767` VarDecl write-shape bug, which I confirmed is still present at HEAD reading
  the old 3-input `[control, name, init]` shape). The design's "NOT worth fixing as a channel fix —
  same overwrite argument, plus orthogonal Proposal-2 follow-up" is consistent with the code; the
  write-shape bug is real and should be tracked as a Proposal-2 follow-up regardless of the X/Y decision.

---

## (6) Plan-vs-code spot-check — **all cited line ranges match HEAD**

Spot-checked the design's Part 5 deletion spec against the actual code at 5c15aa5f:

| Design citation | Code at HEAD | Match |
|---|---|---|
| toggle API `Actions.pm:91-94` | `_control_rebuild_enabled` + `disable/enable/control_rebuild_enabled` exactly at 91-94 | YES |
| `_thread_control_head` 119-124 | `my sub _thread_control_head($ctx,$node,$factory)` at 119-124, with the `defined $node->control_in` no-op guard | YES |
| `_find_pre_init_control_head` 134-149 | present at 134-149, Context multiply-tree walk recovering pre-init control_head | YES |
| VariableDeclaration self-publish 1900 | `$sa->update_control_head($var_decl)` at 1900 | YES |
| PostfixModifier publishers 2565/2629 | `$sa->update_control_head($region)` at 2565 (loop) and 2629 (if) | YES |
| rebuild loop 1685-1752, `$do_rewrite` gate 1684, merges 1678/1691/1729 | all exactly as cited; closure following `control_in` at 1130 (FACT 1's mechanism) | YES |
| `_finalize_body_graph` 1016-1138, control_in-following closure 1130 | confirmed; closure follows BOTH inputs() and control_in | YES |

No drift between the design's deletion spec and the code. The `control-head-leak-suppression-design.md`
file the brief referenced does not exist (the only inaccuracy found, and it is in the brief, not the
design). Gate suites green at HEAD: **control-threading.t 58/58, codegen-byte-compat-schedule.t 19/19.**

---

## Bottom line

**Option X is the right call, and it is the call the June-2 adversarial pair already reached before the
team overrode it and burned four readiness passes on five same-family leaks.** Construction-time
`control_in` correctness has no consumer in the codebase and no plausible-scheduler justification (GCM,
early/late, Braun-SSA all consume a completed graph or block-structure, not fire-time effect edges).
The post-pass is correct-by-construction over source order, degrades gracefully (FACT 3 / probe (5)),
and matches the documented architecture (`Node.pm:26-28`). Retire the during-parse channel.

**The single open item before deletion lands:** resolve the merge-redundancy contradiction toward
**KEEP a merge-only hygiene loop** (Section (4)) — not because it bears on X-vs-Y, but because FACT 1's
"redundant" finding rests on a guard not in the tree and a gate set narrower than the four
`$graph->nodes`-consuming sites that take membership as given. Correctness over cleanliness.
```
