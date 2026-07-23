# Milestone coercion-slice-a Postmortem

Scope: 4 issues (1 buildable code + 3 decision/doc placeholders), the first
PROVING SLICE of the "everything is a coercion" architecture. Gate 152 -> 153,
floor pinned 148 -> 153, worklist 1 -> 0. Slice A landed a real Coerce(Int->Num)
node in the producer graph (perl5-son 41506dc + chalk 79ec5e1b), flipping the
divide invariant leg green and PROVING C2 (value-coercion-as-node) end-to-end.

## What Worked Well

- **The full pipeline earned its keep at every stage, and the whole thing was
  produced by workflows.** This milestone came out of a long design arc
  (capture -> assess+ponytail -> refinement -> chain-review -> execute), and each
  gate caught something the next would have paid for:
  - The slice-plan WORKFLOW (Fable investigation + Opus synthesis) killed one
    over-built slice (C3's 200-line registry -> "already falsified, document it")
    and produced the "do A, then see" shape.
  - chain-review's pushback lens caught TWO blocking findings the alignment lens
    couldn't: the floor pin was unfalsifiable (hardcoded 148 contradicted the
    anti-hardcode AC) and the C1 doc-fix was a no-op targeting the wrong file
    while the plan CONTRADICTED ITSELF (said "drop IRModule" and "should be
    IRModule" in different sections). Both real; both fixed pre-execution.
  - The PAAD review found a real IMPORTANT contract gap (below).
- **Slice A was genuinely shovel-ready.** The pre-execution adversarial assess
  had REPRODUCED its red invariant leg by execution and verified every reuse site
  against head, so execution hit zero surprises: the 4 edits were exactly as
  scoped, ~45-65 lines, no rewire helper needed, one clean session.
- **The mandatory self-verified gate held.** I (coordinator) ran the corpus gate
  myself on committed HEAD (not the subagent's report), twice for determinism,
  and verified the floor pin is falsifiable (fails at 154). gate-green rose 152
  -> 153 with a REAL floor bump and worklist -> 0. No false-green.
- **Right-sizing the review.** A ~45-line cross-repo change got a focused
  correctness review (one code-reviewer on the diff), not the full multi-agent
  PAAD suite -- proportionate, and it still found the real gap.

## What Didn't Work

- **The PAAD review found an IMPORTANT contract gap the executor's scope note
  under-described.** `_coerce_int_to_num` keys on the BUILD-TIME stamp, so
  Divide operands that are unstamped at build but inferred Int by the LOADER
  (ordinary `foo()/bar()`, `@_`-bound pads) reach Divide un-bridged and fail
  TypedInvariant -- masked today only because no such case is in the corpus. The
  commit's "TARGMY twin out of scope" caveat under-described this (it's any
  build-time-unstamped operand, not just `$x /= 2`). Coordinator-verified
  (`foo()/bar()` -> Divide with 0 Coerce nodes). NOT a blocker: no silent
  miscompile (the backend's `_lower_as_double` promotes independently -> correct
  value, or a loud GAP). Filed as 019f8cbd; issue body corrected.
- **git-zhi's session-window model fought the doc/decision issues repeatedly.**
  `--state done` requires in-progress-then-done AND commits in the window; the 3
  placeholders (deliverable = a doc commit that predated their start marker) and
  even Slice A (commits predated `--state start`) all needed `--force`. Not a
  process failure -- the intended flag for verification-only / retroactive-commit
  issues -- but 4 of 4 issues hit it. The `milestone add` CLI also has no
  `--body` flag (the architect used git plumbing).
- **My own AC command was imprecise and I over-engineered the fix.** The floor
  AC `ag "gate_green.*>=.*148"` false-matched the floor-history PROSE on line 220
  (which contains "floor 148->153"), not the assertion. I then spent two rounds
  on fragile nested-quote regex before settling on the robust `! grep -qF
  "q{>=}, 148,"` (the assertion span never appears in prose). Should have reached
  for the fixed-string form first.

## What Puzzles Us

- The producer-side Coerce insertion is PARTIALLY REDUNDANT with the backend's
  `_lower_as_double`: for value-CORRECTNESS the Coerce node isn't what fixes
  division (the backend already sitofp-promotes); the Coerce's real job is
  satisfying the INVARIANT. So "value-coercion-as-node" (C2) is proven as an
  IR-well-typedness property, but the runtime already worked without it. That is
  arguably the POINT (the invariant is the architecture's contract, not the
  runtime), but it means the slice proved a typing property, not a behavior fix --
  worth being precise about when C2 is cited as justification for the registry.

## What Will We Change

- **Coercion insertion must run AFTER (or fold into) loader repr-inference.** The
  019f8cbd gap is structural: a build-time producer wrap can't see loader-inferred
  types. This is the "coercion follows type inference" direction (the
  narrowing-inference operand-demand gap in TypeInferenceActions). Any future
  coercion-node work should insert on the TYPED graph, not at produce time -- or
  the same build-time-vs-inferred split will recur for every op.
- **Scope notes must name the CLASS of the exclusion, not an instance.** "TARGMY
  twin out of scope" named one instance of a gap that is really "any
  build-time-unstamped operand." Decomposer/executor should state exclusions by
  their generalization so the gate's future coverage is predictable.
- **Reach for fixed-string ACs over regex greps against files that contain
  historical prose.** son-corpus-wide.t:220's floor message is a giant prose blob
  that false-matches loose patterns; `grep -qF` on a distinctive assertion span is
  the robust form.

---
Generated by crochet:postmortem on 2026-07-23
Data sources: issue list, milestone show, git log, self-verified corpus gate,
PAAD review (code-reviewer), coordinator reproduction of finding 1.
