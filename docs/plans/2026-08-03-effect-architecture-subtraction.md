# Design: effect-architecture subtraction — fix the bugs, add the check, delete two mechanisms

**Status:** design, v2 — reworked after `crochet:assess` (Fable) and an independent
ponytail review. Not a plan; no implementation.
**Defers:** `2026-08-02-effect-world-token-design.md` (DEFERRED, trigger = GCM design).
**Prior art:** `docs/research/2026-08-02-effect-ordering-prior-art.md`.

## What changed in v2 — and why v1 was wrong

v1 proposed 8 steps ordered `1→8`. Both reviews rejected that ordering and three of
the steps. **The single worst call: step 4 is the only step that fixes wrong output —
three confirmed live miscompiles, two of them silent — and v1 sequenced it fourth,
behind three cosmetic normalizations.** Abandon at 60% and you gain nothing plus a
half-normalized `If`.

**Cut: v1 steps 1, 3, 7.** Reasons measured, below.
**Promoted: the invariant, from sixth to first, as a committed RED.**

v1 numbers that were wrong, all re-derived on HEAD:

| v1 claim | Measured |
|---|---|
| step 1 costs "6 chalk + 1 producer test file" | **120 positional `make('If'\|'Loop')` sites across 26 files** |
| "12 stale ir-blocks" | **30** `= If(`/`= Loop(` spec lines (7 two-operand `If`, 16 one-operand `Loop`) |
| `%CFG_OPS` duplicated 5× | 5 in lib, **plus a 6th** at `t/bootstrap/fixtures/mop-fence-base.pm:231,284` |
| step 3 blocks "byte-identical, only comments differ" | different class-maps and die text; **`make_cfg` omits the `$cache{$id}` write** |
| "F3/F4 are not equality REDs" | **F3 IS one.** `strip_epilogue` leaves `a\nb\nc\n` vs `a\nc\nb\n` — a plain FAIL, TDD-able today |
| step 3 "test cost: none" | see the DCE hazard below |
| net −56 lines | table sums to **−52**; reconcile at implementation |

## The four bugs, re-verified on HEAD

Baseline re-confirmed independently: corpus `178 ok / 0 not ok`,
`gate-green=156 behavior=156 shape=156 invariant=156 worklist=0`. Exec gate 0/5.

- **F1 mainline die — LIVE.** `print "a\n"; die` → perl `a\n` exit 255; chalk **empty**
  exit 255. `$sim->set_control($unwind)` puts the Unwind on the chain but
  `Unwind.control_in` stays UNDEF, so the backward walk stops there.
  Node dump: `Unwind#3 control_in=UNDEF inputs=[Print#2, Constant("boom\n")]`.
  It also violates chalk's own contract: `Unwind.pm` declares
  `method value() { return $self->inputs->[0] }` with the comment *"Control flows
  through the control_in decoration … not through inputs"* — so every producer-built
  Unwind returns its **control node** from `value()`.
- **F2 die-after-effect-in-arm — LIVE.** `print "a\n"; if ($x) { print "t\n"; die }
  print "z\n"` → perl `a\nt\n` exit 255; chalk `a\nt\nz\n` exit 0. Wrong output *and*
  wrong exit, running code perl never reaches.
- **F3 inlined effect reordered — LIVE, and an exact-equality RED.**
  `sub f { print "c\n"; 2 } print "a\n"; my $r = f(); print "b\n"; $r;`
  → perl `a\nc\nb\n`, chalk `a\nb\nc\n`.
- **F4 inlined effect dropped — LIVE.** One review could not reproduce it; the other
  did, with a cleaner shape: `sub f { print "x"; 2 } my $r = f(); 3` → perl prints
  `x`; the loaded graph is `Start Constant Return` — **the Call vanished entirely**,
  lli prints only `Int:3`, no GAP. Treat F4 as confirmed on that shape.

## The work

**Order: 6 → 4 → 5 → 2, with 8 filed.** Every prefix is a win; nothing is left
half-migrated if work stops at any point.

### Step 6 (FIRST) — the missing check, committed RED

`TypedInvariant.pm` is the corpus's third leg, runs on all 156 cases, and has
**zero** control/effect assertions today. This is the highest value-per-line item in
the document and v1 ranked it sixth.

Evidence it is the right oracle: implemented as a probe and run over the six repro
programs, it fired **6/6, and in every case the flagged node IS the miscompiling
node** — including a case that currently reads PASS.

**REWORK REQUIRED — the v1 invariant is false as specified.** Measured over the
corpus: `%STATEMENT_EFFECT_OPS ∪ {Return, Unwind}` having a defined `control_in` is
violated on **36 of 156 gate-green cases**. Step 4 cures 27 (the Calls) and F1 cures
T2's Unwind — but **9 are cured by nothing in this plan**: regex R1–R7 and host
H1–H2, via *value-position* `RegexMatch`/`Match`/`RegexSubst`.

Those 9 are not bugs. `NodeFactory.pm:144-159` puts matches in
`%STATEMENT_EFFECT_OPS` because a match writes capture state and needs per-call
identity; the adjacent `%ALLOC_OPS` comment draws the line the invariant missed —
allocations are *"value-producing and are NOT control-threaded by the Block fixup."*
A value-position match is the same category.

**So narrow the op set to what the Block fixup actually threads in statement
position**, not all of `%STATEMENT_EFFECT_OPS`. Name the exempt set explicitly and
justify it in the code, so this stays a contract rather than a fudge.

Known weaker-than-the-prose caveat: the leg receives `$g->nodes` only, so an effect
reachable *only* through control is invisible to it. Say so at the check site.

### Step 4 — the four-bug fix

**Cross-repo landing order is load-bearing and v1 omitted it. Measured: producer
pin first ⇒ gate RED at 153**, three double-print REDs (`xx`,
`callercalleecallee`, `yyyy`). Chalk memoize first ⇒ IR suite 58/58 against the HEAD
producer. **Land chalk-side first.**

**F2 requires F1, also omitted by v1.** `set_control_in` calls `add_consumer`, so F1
lands green alone. But F2's BFS ("consumers whose `control_in` is this node") finds
nothing *before* F1, because producer Unwinds have `control_in=UNDEF` — land F2 first
and you regress corpus T2/T2b.

Ordered sub-steps:

1. **Memoize `_lower_call_direct`** — `Context.pm:4384`, `:4408`. Chalk-only. Without
   it F3/F4's fix goes red at 153.
2. **F1** — `SoN/FromOptree.pm:783-785`, `:3813-3815`: `inputs => [$args->@*]` +
   `$unwind->set_control_in($sim->control)`. Mirrors `Actions.pm:1450-1457`; precedent
   already in-file for `Print` (`:2091-2093`) and `Assign` (`:1716-1719`). Producer-only.
3. **F2** — `Target/LLVM/Context.pm:2836-2843`: replace the one-hop
   `_find_unwind_consumer` scan (assumption stated in its own comment at `:2833-2835`)
   with a BFS over consumers-whose-`control_in`-is-this-node, stopping at `Region`.
   Chalk-only. **Requires F1.**
4. **F3/F4** — `SoN/FromOptree.pm:1156`, `:1189` (v1 cited these; one review reads
   them as `:1155`/`:1188` — confirm at implementation). Drop the `if $void` guard;
   pin unconditionally, push the value only when non-void. This *is* R1.0
   effect-by-default (memory `effect_by_default_call_classification`).
   `_place_call` (5 lines) becomes dead.
5. **Add the missing bilateral corpus case** — effect-*before*-die-in-arm.
   `control-flow.md` T2 (`:1167`) and T2b (`:1204`) are both die-first, which is why
   F2 survived. CLAUDE.md's bilateral rule owes this regardless. **Part of step 4, not
   after it.**

**Test cost:** 1 producer file, 3 subtests in `from-optree-method-dispatch.t` — but
only test 4 is at `:92-102`; tests 6–7 are the Return-shape subtests at `:122-154`.
They pin the *pre-R1.0* convention and are change-detectors for a deliberate policy
inversion, not correctness oracles. `shift-pop.t:53` and `element-store-effect.t:66`
stay green.

### Step 5 — delete `Target/LLVM.pm:909`

**v1 over-claimed this as "delete a mechanism, −1". It deletes one of three M5
sites.** The others: `Chalk/IR/Serialize/JSON.pm:996-1002` (`_control_chain_nodes`
seed — inside a **fenced** sub, so deleting it trips `mop-fence-audit.t`) and the
`@trailing_effects` GAP guard at `Context.pm:4372-4375`.

**The "requires 4" dependency is asserted, not shown.** Probe: **0 of 177** corpus
graphs carry a multi-input `Return` on the HEAD producer, and
`FromOptree.pm:893-898` now documents `inputs=[value]` always — so corpus-wise
`:905-911` looks deletable today. The dependency may be protecting non-corpus inputs
(whole t/base files). Keep the ordering conservative; do not promote it.

Retitle honestly: *"delete the LLVM copy of the M5 seed"*, and file the other two.

### Step 2 — delete the wire `cfg` flag

Genuinely dead. `Serialize/JSON.pm:17` defines `%CFG_OPS`, `:37` emits with it, then
`:372` reads `$nd->{cfg}` **off the wire** instead of consulting the table 355 lines
above; `:476` branches on it. All 5 lib copies are the identical 7-op list and
`make_cfg`'s `%CFG_CLASSES` covers exactly those 7 — deriving from the op is provably
equivalent. Origin `e75c8447`, **2026-04-07**: older than the namespace divorce, older
than `%STATEMENT_EFFECT_OPS`, older than `control_in` being on the base node.

Best abandon-safety in the document: **each half lands alone and stays green
forever.** `2a` (chalk loader derives locally) reads old JSON fine; `2b` (producer
stops emitting) produces JSON the new loader reads fine.

**Test cost — v1 disclosed only the producer's.** Also breaks
`t/bootstrap/ir-serialize-json.t:39`
(`like($json, qr/"cfg"\s*:\s*true/)`). Producer side:
`perl5-son/t/serialize-json.t:71-73`. The embedded fixture at `:236` and
`mop-fence-base.pm` are fine — the fixture JSON still loads once the loader ignores
the key.

### Step 8 — file the gate blind spot (widened)

Not "the shape leg does not check `If` operands." Measured: `_rooted_match`
(`MdtestCorpus.pm:1146-1159`) starts at `Return.inputs[0]` and descends **value
operands only**, so any node reachable only through control gets a presence check and
**never an operand check**. Probes:

```
identical       -> PASS
WRONG If cond   -> PASS
WRONG arm store -> PASS
```

File as **"the shape leg does not check operands of control-reachable nodes."** This
is the prerequisite for the cut step 1 ever being safe.

## Cut, with reasons

**v1 step 1 (`If`/`Loop` → `control_in`) — CUT.** Largest diff, smallest oracle: 120
positional sites across 26 files, 30 ir-block lines, plus `Loop`'s `inputs[1]`
backedge index shifting against 77 `backedge` references. And **nothing validates
it** — the plan's own step 8 shows the gate is blind to exactly what this step
changes, so 120 sites could keep passing while silently constructing malformed `If`s.
The shim it deletes has zero measured runtime cost and is already correct at the
reader (`If.pm:19-25`). **Blocked on step 8.**

**v1 step 3 (collapse the 5 identity branches) — CUT.** Both reviews independently
found the same hazard: `make_cfg` (`NodeFactory.pm:352-361`, both repos) **never
writes `$cache{$id}`**, while `DCE.pm:47` iterates `all_node_ids()` and `:71` calls
`remove_node`. Merging it into a caching helper puts `If`/`Proj`/`Region`/`Loop` into
DCE's worklist **for the first time** — a silent-miscompile-shaped behavior change
bought for ~25 code lines. The blocks also are not byte-identical (differing
class-maps and die text), and their 13 comment lines each record a distinct
historical miscompile that CLAUDE.md forbids deleting. It is also cross-repo: the v1
reviewer applied it to chalk and forgot the producer, and **the full gate and both
suites stayed green** — a step that half-lands undetectably, in a project with a
documented half-landing habit.

**v1 step 7 (cross-repo drift detector) — CUT, as a pair with step 3.** Measurement
re-derived exactly: 91 shared files, **90 code-identical**, sole diff
`Serialize/JSON.pm` (expected). That is the argument against it — **the measurement
is the detector**, one shell loop with a `sed` normalize, no committed file and no
allowlist to maintain. The 2026-08-01 divorce plan already cut a conformance test on
this evidence; two days and zero drift later nothing has changed. The detector existed
only to police the duplication step 3 would half-migrate; deleting both removes the
hazard instead of instrumenting it.

## Beyond scope, but found and worth filing

**There is no exit-code oracle anywhere.** `Mode1Runner.pm:167` —
`return (undef, "lli exited $exit: $out", $g) if $exit != 0;` — turns any nonzero lli
exit into a skip and never compares `$?`. That is why F1's dropped `print` is
invisible to the harness and why F2 reads PASS while returning `Int:1` where perl
exits 255. Adding the comparison is small **but not free**: nobody has measured how
many currently-green cases would flip. File it; do not fold it in here.

## Verification

**The corpus gate is mandatory and coordinator-self-verified on committed HEAD after
every step** — floor 156, three legs, worklist 0. Never a subagent self-report.
Shadow-copy numbers in this document are evidence for planning only.

Cross-repo: chalk on `phase5-capstone`, perl5-son on `pu`; producer suites need
`prove -Ilib -Iblib/lib -j1` on a **clean** build (stale blib masks deletions).

Independently confirmed as green under step 4 (fix + memoize): 156/156/156/156,
worklist 0; chalk IR suite 58/58 with memoize alone.

## Out of scope

- **The world token** — DEFERRED with triggers in its own doc; revisit when GCM is
  designed (`chalk-parse-perl-plan.md:763`, Phase 9).
- **Fixing the shape-leg blind spot** (step 8 files it only).
- **Unifying the two `NodeFactory.pm` copies** — measured drift is zero.
- **The `Int:N` epilogue** (`Target/LLVM.pm:1006`) — independently confirmed as the
  real exec-gate blocker (`hello` fails on the `Undef:` epilogue line, **not**
  ordering). Entry/epilogue protocol's work.

## Correction this work carries

`2026-07-23-slice-b-inliner-effect-ordering.md:259` claims "the silent effect-drop
miscompile class is CLOSED". F4 is re-proven live on HEAD with no GAP — Commit 1's
guard inspects only the *callee's* attachment paths, and the caller-side drop is
unguarded. True as scoped to the callee, **false as stated about the class**.
Re-scope that line.
