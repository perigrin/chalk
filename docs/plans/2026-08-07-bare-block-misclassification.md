# Plan: a bare block is a lexical scope, not a loop

**Status:** plan, awaiting assessment. No implementation.
**Source:** `docs/2026-08-07-loop-condition-blocker-audit.md` (read-only characterisation).
**Repos:** chalk `phase5-capstone` @ `48099a09`, perl5-son `pu` @ `f9273138`.

## The defect

A bare block — `{ ... }` at statement level, one of Perl's most basic constructs — has
**three** failure modes depending on its contents. All reproduced on committed HEAD:

```perl
{ my $z = 5; print "b\n"; }
  -> GAP: loop without a lowerable condition                    (acceptable)

my $c = 0; { my $x = 0; $x = 1 if $c; print "after\n"; } print "end\n";
  perl  -> "after\nend"
  chalk -> "end"          NO GAP                                (SILENT MISCOMPILE)

my $c = 1; { same block }
  -> lli died on signal 11                                      (SEGFAULT)
```

The middle case is a **GAP-not-miscompile invariant violation** — the same class as the
four miscompiles `effect-chain-fix` just closed, and the reason this work is worth doing.

## Root cause

Perl compiles `{ ... }` to `enterloop`/`leaveloop`. The producer routes **every**
`enterloop` into `_translate_while_loop` (`~/dev/perl5-son/lib/SoN/FromOptree.pm:567-572`).

- `_walk_loop_body` assigns `$exit_proj` only at `:3131` or `:3274`. A bare block reaches
  neither, terminates at `leaveloop` (`:3056`), and the GAP fires at `:2698`.
- Worse: `_walk_loop_body:3249` accepts a statement-modifier `if` **as the loop's header
  condition**. The remainder of the block then becomes loop body that never executes —
  which is the silent drop, and on the true polarity a malformed graph that segfaults.

**The fix is a classification correction, not new machinery:** an `enterloop` with **no
back-edge** is a lexical scope, not a loop. The correct handling already exists next
door, in the `enter`/`leave` path at `:582-597`.

## Honest payoff — read this before writing any AC

**The payoff is CORRECTNESS and DIAGNOSTICS. It is NOT pass-count.**

Measured under a bare-block-transparent producer probe:

| metric | before | after |
|---|---|---|
| ring files passing | 1 of 31 | **1 of 31** |
| ring files whose blocker CHANGES | — | 7 (`cmp.t`, `opsubs.t`, `our.t`, `package.t`, `concat.t`, `fold.t`, `proto.t`) |
| distinct symptom messages collapsed | 7 + a `StackSim` internal error | 1 correct path |

**Zero files are unblocked.** Every affected file advances exactly one step, with 5-8
further distinct blockers visible per file (`package.t` ≥5, the others ≥3).

No AC may claim files-unblocked. Ranking work by that number is the proxy-metric error
this project has now made three times — see memory `feedback_proxy_metrics`. The
justification here is that a basic construct silently drops statements and segfaults,
which is the north star itself (does the program produce the right answer), not a stand-in
for it.

## Scope

**In:** the `enterloop` classification at `FromOptree.pm:567-572`, routing a
back-edge-less `enterloop` to the existing lexical-scope path; corpus cases pinning the
three shapes; whatever falls out of `_walk_loop_body` no longer being handed non-loops.

**Out, and do NOT bundle:**

- **Shape 2** — `t/cmd/for.t`, a headless loop whose only exit is a non-first-statement
  `last if`. Genuinely independent: `:3113-3116` gates head-of-body hoisting on
  `$stmt_count == 1`, and the mid-body handler (`:3162-3246`) builds an `If` and a
  break-proj but never assigns `$exit_proj`. **It already has a ready-made RED** —
  corpus **T4c** (`t/corpus/mdtest/control-flow.md:1412`), whose source is the exact
  trigger.
- **The corpus contract gap** — `son-corpus-wide.t:133-139` `pass()`es a GAP-declared
  case **without running its source**, so neither GAP-message drift nor a GAP-declared
  case that has silently started working is detectable. T4c's declared message ("last not
  at the head of a loop body") already does not match what the producer emits ("loop
  without a lowerable condition"). **File it; do not fix it here.**

## Corpus reality

There is **no existing mdtest case for a statement-level bare block** — grep over all 12
files returns nothing. `D10` covers `do { }`, which is `enter`/`leave`, a different path,
already GREEN.

So this milestone must **add** its corpus cases. The three reproduced shapes are the
natural bilateral set:

1. plain bare block with a print (currently GAP) → GREEN
2. bare block with a statement-modifier `if`, **false** polarity (currently silent drop)
3. the same, **true** polarity (currently segfault)

(2) and (3) are the bilateral pair the project's coverage rule requires — one on each
side of the guard — and they are the cases that prove the miscompile closed rather than
merely moved.

## Verification

- Corpus gate floor **157**, three legs, **coordinator-self-verified on committed HEAD**.
  Never a subagent report. Floor rises by however many GREEN cases this adds.
- The silent-miscompile and segfault shapes must be verified **behaviorally against
  perl** — stdout and exit status — not by inspecting emitted LLVM. The harness has no
  exit-code oracle (`Mode1Runner.pm:167`), so the segfault case needs an out-of-band
  check.
- Executable gate must stay at **4/5**.

## Risks

1. **Cross-repo with no producer version pin.** `son-corpus-wide.t:17` resolves the
   producer as a live filesystem path, so "chalk first" is wall-clock, not repo state.
   **Serialize execution — one agent at a time** — and record the paired SHA in every
   commit message.
2. **The classification change is upstream of every loop.** `_translate_while_loop`
   currently receives all `enterloop`s; narrowing its input set could change behaviour for
   real loops, not just bare blocks. The corpus's existing loop cases (D2*, D3*, T4*) are
   the regression surface.
3. **`_walk_loop_body:3249` may be load-bearing for real loops.** Accepting a
   statement-modifier `if` as a header condition is wrong for a bare block; verify it is
   not the mechanism some real loop shape depends on before changing or bypassing it.
