# Plan: a back-edge-less `enterloop` is a lexical scope, not a loop

**Status:** plan v2, double-assessed (`crochet:assess` + ponytail), ready to refine.
**Source:** `docs/2026-08-07-loop-condition-blocker-audit.md` (provenance marked per claim).
**Repos:** chalk `phase5-capstone`, perl5-son `pu` @ `f9273138`.

## What this actually is — v1 framed it too small

v1 called this "bare blocks." Measured, the misclassified shape is **every block-form
`class` and `package` declaration**:

```
package Foo { ... }   ->  enterloop(next->5 last->5)     back-edge-less
class Foo   { ... }   ->  enterloop(next->5 last->5)     back-edge-less
while (...) { ... }   ->  enterloop(next->a last->f)     a real loop
```

**159 of chalk's 166 `lib/` files contain that shape**, and `CLAUDE.md` mandates
`feature class`. This sits under the entire self-hosting path.

## The defect

A back-edge-less `enterloop` is routed into `_translate_while_loop`
(`SoN/FromOptree.pm:567`), producing three outcomes depending on contents:

```perl
{ my $z = 5; print "b\n"; }                              -> GAP (acceptable)
my $c=0; { print "first\n" if $c; print "after\n"; } print "end\n";
  perl  -> "after\nend"
  chalk -> "end"   both block prints stranded, NO GAP        (SILENT MISCOMPILE)
my $c=1; { same }                                        -> lli died on signal 11    (SEGFAULT)
```

The trigger is **any `and`/`or` inside the block followed by more statements** — v1 said
"statement-modifier `if`", but a full `if () { }` block triggers it too. `_walk_loop_body`
accepts the `and` as the loop's header condition (`:3249`, then `:3284` does
`$op = $op->other`), making the true-arm the "body" and dropping everything after it.

**Live-hazard status, stated honestly:** across the 31-file ring, the current FAIL count
is **0** — every affected file GAPs on a plain block before reaching a conditional one.
The miscompile fires in constructed probes and in nothing yet measured. It is a loaded
gun, not a fired one — but it is pointed at `class BLOCK`.

## The fix — 6 lines, one classification site

A bare block ⟺ `enterloop->nextop == enterloop->lastop` (both `leaveloop`). A real
`while`/`until`/C-style `for` has `nextop = unstack`; `foreach` never reaches the site
(`enteriter`); `do {} while` goes through `enter`/`leave`.

At `FromOptree.pm:567`:

```perl
my $nx = $op->can('nextop') ? $op->nextop : undef;
my $ls = $op->can('lastop') ? $op->lastop : undef;
if (ref $nx && $$nx && ref $ls && $$ls && $$nx == $$ls) {
    $op = $op->next;
    next;
}
```

The body then walks inline and terminates on `leaveloop`, which the main walk **already
handles** at `:665-668`. The same back-edge discriminator already exists 250 lines up the
file in `_is_postfix_while` (`:2321`) — this is a precedented shape, not an invention.

**Note the discriminator is `nextop == lastop`, NOT "no back-edge"** — a bare block does
have `redoop` set. v1's wording would have sent an implementer to the wrong op field.

### Why NOT "GAP loudly on all bare blocks" (the smaller candidate, rejected)

Two lines cheaper, closes the same two bugs — and **wrong**, for two measured reasons:

1. It would GAP on **159 of 166** of this project's own `lib/` files, blocking the
   self-hosting path.
2. It is **unpinnable**. `son-corpus-wide.t:133-139` `pass()`es a GAP-declared case
   *without running its source*, so every corpus case written against it would be a
   vacuous pass. Two lines is not a saving worth an unenforceable guard.

## Corpus — four GREEN cases, all executing

v1 proposed three cases and **two of them cannot work.** `$x = 1 if $c` hits a
*pre-existing unrelated* blocker — `FromOptree.pm:463`, "void-context 'and' arm combines
a void call with a scalar rebind" — which fires with no bare block present at all. Under
the fix those shapes become GAP-declared, hence `pass()`ed without running, hence
vacuous. v1 called them "the cases that prove the miscompile closed"; they would prove
nothing.

The deliverable set, all measured GREEN under the fix:

| case | source | HEAD |
|---|---|---|
| 1 | `{ my $z = 5; print "b\n"; }` | GAP |
| 2 | `package Foo { print "in\n" }` | GAP |
| 3 | `my $c=0; { print "first\n" if $c; print "after\n"; }` | **FAIL — silent drop** |
| 4 | `my $c=1; { same }` | **signal 11** |

Cases 3/4 are the genuine bilateral pair: a **void print** in the modifier arm instead of
a scalar rebind sidesteps `:463` entirely, and both polarities go GREEN.

**This also resolves the segfault-expressibility problem.** v1 said the segfault needed an
out-of-band check because `Mode1Runner.pm:167` turns nonzero lli exits into skips. True of
v1's case — irrelevant here: after the fix case 4 exits 0 with correct stdout, so the gate
compares it normally. **No exit-code oracle needed.**

Floor **157 → 161**.

## MEASURED OUTCOME (2026-08-08, post-fix, coordinator-run)

Landed: perl5-son `2162f8e` (6-line classification) + chalk `f3377a7f` (four corpus
cases, floor 157 → 161).

- post-fix ring: pass=1/31 unblocked=0 blocker-changed=5
- post-fix distinct blocker messages: 20 (measured by stripping the filename and any
  trailing ` at FILE:LINE` from each SKIP line in `ring-worklist.t`, then `sort -u`)
- StackSim/Stack underflow observed in the ring: no

**The headline number: `"loop without a lowerable condition"` fell from 5 files to 1.**
That is the fix working — the remaining one is `t/cmd/for.t`, which is shape 2 (a real
loop, deliberately out of scope, filed as Part D2 of the followups).

**Both of v1's diagnostics claims were wrong, in opposite directions.** v1 said the fix
collapses "7 messages plus a StackSim internal error" into 1; a reviewer then measured
baseline at 4 and predicted 7 after. Measured reality: **20 distinct messages remain**,
because each newly-reachable file reveals its own next blocker. Message-collapsing was
never this fix's property — v1 credited it with the *rejected* GAP-loudly variant's
behaviour, on a number the original (empty) audit asserted and nothing backed.

**`StackSim`/"Stack underflow" is observed 0 times in the ring.** The string does exist
in the source (`SoN/FromOptree/StackSim.pm:25`) — so the correct statement is
"not observed", not "does not exist". v1 said the fix eliminates it; there was nothing
to eliminate.

**Two further corrections to v1's framing:**

- v1 described the miscompiling shape as emitting no output at all. Measured: one line
  survives (`end`); the two block prints are stranded. Off by one line, corrected above.
- v1's "159 of 166 lib files / sits under the entire self-hosting path" **overstates the
  lib/ axis**. The GAP always lands on `main::__PROGRAM__`, never on a class or method
  unit, and `Phase5LibCoverage.pm:94` does not count `__PROGRAM__` — so this fix buys
  **zero Phase-5 lib coverage**. Where it IS load-bearing is `__PROGRAM__` itself: the
  bare-file / executable path. That is the truer and stronger claim.

## Honest payoff — no AC may claim files-unblocked

| metric | before | after |
|---|---|---|
| corpus gate | 157/157/157/157 | **161** (4 new GREEN) |
| ring files passing | 1 of 31 | **1 of 31** |
| ring FAIL | 0 | 0 |
| files whose blocker advances | — | 7 (`cmp.t`, `opsubs.t`, `our.t`, `package.t`, `concat.t`, `fold.t`, `proto.t`) |

**Zero files unblocked.** The 7 advance one step and reveal their next honest blocker;
`RingWorklist`'s own ABOUTME says the ring exists to *be* the next-feature worklist, so
that is the harness working as designed. Ship it as an observation, **never as an AC**.

**v1's diagnostics claim was backwards and is deleted.** v1 credited this fix with
collapsing "7 messages plus a StackSim internal error" into one. Measured: baseline has
**4** distinct messages across those files, **no `StackSim`/"Stack underflow" appears
anywhere in the ring**, and the fix produces **7 distinct** messages (more, not fewer).
Message-collapsing is the *rejected* GAP-loudly variant's property. v1 credited this fix
with the alternative's benefit.

## Verification

- Corpus gate floor 157 → 161, three legs, **coordinator-self-verified on committed
  HEAD**. Never a subagent report.
- **Regression risk measured at zero**: the fix applied to a shadow producer gives
  `gate-green=157 behavior=157 shape=157 invariant=157 gap-declared=21 worklist=0`,
  per-topic breakdown byte-identical to baseline, zero `not ok`; ring `PASS=1 SKIP=30
  FAIL=0`, no file regressed. All D2\*/D3\*/T4\* loop cases green.
- A bare block *inside* a real loop still GAPs honestly (`_walk_loop_body:3097`,
  untouched) — verified residual and loud.
- Executable gate stays 4/5 (free — all five programs are one-liners with no blocks).

## Out of scope — do not bundle

- **Shape 2** — `t/cmd/for.t`, headless loop whose only exit is a non-first-statement
  `last if`. It is a *real* loop (`nextop=unstack`), untouched by this fix; blocker
  verified unchanged. Ready-made RED already exists: corpus **T4c**.
- **The corpus contract gap** — `son-corpus-wide.t:133-139` `pass()`es GAP-declared cases
  without running their source. It is the reason v1's cases 2/3 were unshippable. **File
  it**; T4c's declared message already does not match what the producer emits.

## Risks

1. **Cross-repo, no producer version pin** — and this one bit the reviewer: a concurrent
   session wiped its shadow producer mid-run, producing 31 spurious "B::SoN produced no
   JSON". **Serialize execution, one agent at a time**, paired SHA in every commit.
2. ~~Upstream of every loop~~ — **measured non-risk**: zero regression across 157 corpus
   cases and 31 ring files.
3. ~~`_walk_loop_body:3249` load-bearing~~ — **answered**: the fix narrows the walker's
   input set and does not touch the walker.
