# Audit: the "loop without a lowerable condition" blocker

**Provenance — read this first.** This file was committed EMPTY in `6ec7fffa`. The
characterisation ran as a read-only subagent audit which reported its findings in its
return message and never wrote the file; the path was staged without checking it had
content. The plan `2026-08-07-bare-block-misclassification.md` then cited it as its
source, so its payoff numbers were, for a time, backed by nothing in-repo.

Reconstructed below with each claim marked by how it is known:

- **[VERIFIED]** — reproduced by the coordinator directly, command output seen
- **[ASSESSED]** — independently reproduced by the `crochet:assess` reviewer, who ran a
  shadow producer and the full corpus gate
- **[UNVERIFIED]** — from the original audit's return message only, no artifact

## The defect [VERIFIED]

A statement-level bare block has three failure modes depending on contents. All three
reproduced on chalk `48099a09` / producer `f9273138`:

```perl
{ my $z = 5; print "b\n"; }
  -> GAP: loop without a lowerable condition                       (acceptable)

my $c = 0; { my $x = 0; $x = 1 if $c; print "after\n"; } print "end\n";
  perl  -> "after\nend"
  chalk -> "end"        NO GAP                                     (SILENT MISCOMPILE)

my $c = 1; { same block }
  -> lli died on signal 11                                         (SEGFAULT)
```

Re-confirmed separately that the middle case emits **no GAP** from the producer today —
`perl -MO=SoN,json` on it produces no GAP text at all.

## Root cause [VERIFIED by reading + ASSESSED by optree probe]

Perl compiles `{ ... }` to `enterloop`/`leaveloop`. `SoN/FromOptree.pm:567` routes every
`enterloop` into `_translate_while_loop`.

- `$exit_proj` is assigned only at `:3131` (head-of-body `last if`) and `:3274`
  (`and`/`or` header). A bare block reaches neither and the GAP fires at `:2698`.
- The silent drop: the middle case's `and(other->d)` reaches the generic header handler
  at `:3249`, and `:3284` does `$op = $op->other` — making the true-arm the loop "body"
  and dropping the trailing `print`.

**[ASSESSED] The discriminator is `nextop == lastop`, and it IS available at the
classification site.** `B::LOOP` exposes `nextop`/`lastop`; measured across shapes:

| shape | `nextop` vs `lastop` | classified |
|---|---|---|
| bare block, nested bare block | **equal** (both `leaveloop`) | bare — correct |
| `while`, `until`, C-style `for` | differ (`unstack` vs `leaveloop`) | loop — correct |
| **`while(1){ last if ... }`** | differ (`nextop=unstack`) | loop — correct |
| `foreach` | never reaches this site (`enteriter`) | n/a |
| `do { } while` | `enter`/`leave` path | n/a |

The specific worry that `while(1){last if}` has no conventional back-edge is **unfounded**
— it still has `nextop=unstack`. Note "no back-edge" is imprecise wording; the sound
signal is `nextop == lastop`. A bare block does have `redoop` set.

## Blast radius [ASSESSED]

The guard applied to a shadow producer, full corpus gate run against it:
**157/157 gate-green, floor 157, gap-declared 21 — identical to HEAD baseline.** No loop
case (D2\*, D3\*, T4\*) regresses. `_walk_loop_body:3249` stays load-bearing for real
loops and is untouched — the fix narrows the *input set*, it does not change the walker.

## What the fix actually achieves [ASSESSED — and it corrects the plan]

Under the reclassification the middle/segfault shapes do **not** become correct. They hit
a *different, pre-existing* GAP — `FromOptree.pm:463`, "void-context 'and' arm combines a
void call with a scalar rebind (2b-3 mixed effect not yet lowered)" [VERIFIED to exist
with that message].

So the fix converts them **silent-miscompile → loud GAP**. That satisfies
GAP-not-miscompile, which is the point. It is NOT a bilateral GREEN guard, and the plan's
corpus section was wrong to describe it as one.

## Payoff [UNVERIFIED — no artifact backs these numbers]

From the original audit's return message only:

- ring files passing: 1 of 31 before **and after** — **zero files unblocked**
- 7 files change blocker: `cmp.t`, `opsubs.t`, `our.t`, `package.t`, `concat.t`,
  `fold.t`, `proto.t`
- 7 distinct symptom messages plus a `StackSim` "Stack underflow" internal error collapse
  to one path
- depth behind this blocker: `package.t` ≥5, the other four ≥3

**The qualitative claim (zero files unblocked; blockers advance one step) is safe to rely
on. The specific counts are not** — treat them as indicative until re-measured.

## Related findings [VERIFIED]

- **Shape 2 is independent** — `t/cmd/for.t`, headless loop whose only exit is a
  non-first-statement `last if`. `:3113-3116` gates head-of-body hoisting on
  `$stmt_count == 1`; the mid-body handler never assigns `$exit_proj`. It is a real loop
  (`nextop=unstack`), so this fix does not reclassify it. Ready-made RED: corpus **T4c**.
- **A corpus contract gap** — `son-corpus-wide.t:133-139` `pass()`es a GAP-declared case
  **without running its source**. So neither GAP-message drift nor a GAP-declared case
  that has silently started working is detectable. **T4c's declared message ("last not at
  the head of a loop body") already does not match the producer's actual "loop without a
  lowerable condition."** Third gate blind spot found this session, after the shape leg
  not checking control-reachable operands and the missing exit-code oracle.
