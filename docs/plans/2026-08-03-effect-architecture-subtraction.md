# Design: fix four effect-ordering miscompiles, add the missing control-chain check, delete the wire `cfg` flag

**Status:** design, v3 — reworked after two rounds of adversarial review
(`crochet:assess` Fable + independent ponytail, twice each). Not a plan; no
implementation.
**Defers:** `2026-08-02-effect-world-token-design.md` (DEFERRED, trigger = GCM design).
**Prior art:** `docs/research/2026-08-02-effect-ordering-prior-art.md`.

## Honest scope (v2's title was wrong)

v2 was titled "effect-architecture subtraction" and claimed 6 mechanisms → 4. Counted
against the inventory, this work deletes **M6 (the wire `cfg` flag) in full and one of
three M5 sites**. It leaves M1 intact and *extends* it (step 4 pins every Call), and
it *adds* a table to the M3 family (the invariant's op set). Measured, it deletes ~36
lines and adds >100: **it is net line-positive.**

The value here is not subtraction. It is **four live miscompiles, two of them silent,
and the fact that nothing anywhere checks the effect chain.** That is a good document;
it just needed the honest label. (v1 additionally proposed the `If`/`Loop`
normalization and the identity-branch collapse; both were cut on measurement — see
"Cut, with reasons".)

## The four bugs, reproduced on HEAD by three independent reviewers

Baseline: corpus `178 ok / 0 not ok`, `gate-green=156 behavior=156 shape=156
invariant=156 worklist=0`, gap-declared 21. Exec gate 0/5.

```
F1  perl exit=255 out="before\n"   chalk exit=255 out=""
F2  perl exit=255 out="t\n"        chalk exit=0   out="t\nz\nInt:1\n"
F3  perl exit=0   out="a\nc\nb\n"  chalk exit=0   out="a\nb\nc\nInt:2\n"
F4  perl exit=0   out="x"          chalk exit=0   out="Int:3\n"   graph: Start Constant Return
```

- **F1** — `$sim->set_control($unwind)` puts the Unwind on the chain but
  `Unwind.control_in` stays UNDEF, so the backward walk stops there. It also violates
  chalk's own contract: `Unwind.pm` declares `value()` as `inputs->[0]` with the
  comment *"Control flows through the control_in decoration … not through inputs"*, so
  every producer-built Unwind returns its **control node** from `value()`.
- **F2** — wrong output *and* wrong exit, executing code perl never reaches.
- **F3** — an exact-equality RED today; `strip_epilogue` leaves `a\nb\nc\n` vs `a\nc\nb\n`.
- **F4** — the `Call` vanishes from the graph entirely. No GAP fires.

## The work

**Order: 4 → 6 → 2, with 8 filed.** (v2 ordered `6 → 4`; step 6 must land *green*, so
it moves after the fix. See "Why the check lands green".)

### Step 4 — the four-bug fix

**Cross-repo landing order is load-bearing and unenforceable by tooling.**
`son-corpus-wide.t:17` resolves the producer as a live filesystem path
(`$ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib"`), so "chalk first" is a
wall-clock instruction, not a repo-state property — abandon mid-step and the pair
state is not reproducible by `git checkout` in either repo. **Discipline: record the
paired producer SHA in each chalk commit message.** There is no mechanism; it must be
prose.

Sub-steps, each measured green at its intermediate state:

1. **Memoize `_lower_call_direct`** — `Context.pm:4384`, `:4408`. Chalk-only.
   Measured: 156/156/156/156, IR suite 58/58. Without it, 4.4 goes **red at 153**
   with exactly `xx`, `callercalleecallee`, `yyyy`.
2. **F1** — `SoN/FromOptree.pm:783-785`, `:3813-3815`. Producer-only. Measured 156.
   Use `inputs => [\@args]` — **an arrayref, not flattened**. The mirror at
   `Actions.pm:1450-1457` wraps, and `Unwind.pm`'s ABOUTME says "exception-args
   arrayref". v2 specified `[$args->@*]`, which flattens; it happened to be
   gate-green, but it contradicts the node contract F1 exists to restore.
3. **F2** — `Context.pm:2836-2843`: replace the one-hop `_find_unwind_consumer` scan
   (its assumption is stated in its own comment at `:2833-2835`) with a BFS over
   consumers-whose-`control_in`-is-this-node, stopping at `Region`. Chalk-only.
   **Requires F1** — and see the hazard below.
4. **F3/F4** — `SoN/FromOptree.pm:1155`, `:1188` (the `set_control_in … if $void`
   lines; v2 cited `:1156`/`:1189`, which are the `_place_call` calls). Drop the
   guard, pin unconditionally, push the value only when non-void — **and advance the
   chain with `$sim->set_control($node)`**, the second half of the Print precedent.
   v2 omitted that; without it, following effects chain past the Call.
   `_place_call` (`:3403-3407`) becomes dead. This *is* R1.0 effect-by-default.
5. **Delete `Target/LLVM.pm:901-910`** (the M5 seed). Folded in here rather than being
   its own step: it is 7 lines of a mechanism that is **corpus-dead at all three
   sites** (0 of 156 loaded graphs carry a multi-input `Return`), so "corpus stays
   green" is vacuous evidence either way. The correct justification — which v2 got
   wrong — is that **step 4.4 pins every Call, making the M5 encoding unproducible at
   the source.** File the other two sites: `Serialize/JSON.pm:994-1002` (inside
   `_control_chain_nodes`, which **is** in `@FENCED_SUBS` per `mop-fence-audit.t:32`)
   and `Context.pm:4372-4378`.

**The F2-before-F1 hazard is real and UNPOLICED.** v2 claimed mis-ordering regresses
corpus T2/T2b. **Measured false:** F2's BFS on the HEAD producer gives 156 green. T2
is the *not-taken* arm; T2b is GAP-declared and corpus-skipped before the legs run.
Under a mis-ordered stack the taken-die probe gives **lli exit 0 / `Int:42` where perl
exits 255 — the abort silently lost, gate fully green.** So F2 ships with a
unit-level abort test (the `llvm-mainline-die.t` pattern, asserting the arm's
`exit(255)`/`unreachable` in the emitted `.ll`, or comparing exit codes out-of-band).
Nothing else catches a mis-order.

**Acceptance criteria:**

- Corpus 156/156/156/156, worklist 0, coordinator-verified on committed HEAD.
- **Executable gate 0/5 → 1/5** (`die-aborts` flips DIFF→PASS, measured). Pin the
  floor. This is the only non-corpus RED→GREEN the work produces, and v2 dropped it.
- All four repro programs match perl on stdout **and** exit status.
- A corpus case pinning **F4's unused-result shape** (`sub f { print "x"; 2 } my $r =
  f(); 3`). F9–F11 pin *used-result* inlining only. Unlike the die shapes this one
  **is** assertable by the behavior leg (exit 0, stdout + epilogue).
- The effect-before-die-in-arm bilateral case (`control-flow.md` T2/T2b are both
  die-first, which is why F2 survived). **Land it GAP-declared and say so** — post-fix
  chalk exits 255, the behavior leg cannot pass, so it is a marker, not a regression
  guard, until an exit-code oracle exists.

**Test cost:** 1 producer file — `from-optree-method-dispatch.t` tests 4, 6, 7 (test 4
at `:92-102`; 6-7 are the Return-shape subtests at `:122-154`). They pin the
*pre-R1.0* convention and are change-detectors for a deliberate policy inversion.
`from-optree-shift-pop.t` and `from-optree-element-store-effect.t` stay green.

### Step 6 — the missing check, landing GREEN

`TypedInvariant.pm` is the corpus's third leg, runs on all 156 cases, and has **zero**
control/effect assertions today.

**Why the check lands green, not RED.** The gate's only hard assertion is
`cmp_ok($tally{gate_green}, '>=', 156)` at `son-corpus-wide.t:220` — **not**
TODO-wrapped, unlike the per-case worklist failures above it. Committing the check RED
drops gate_green below the floor and takes the project's mandatory gate hard-red for
the entire window, across two repos, during which a *new* regression is
indistinguishable from the deliberate one — the signal is a single scalar already tens
below floor. That is `red_tests_hide_real_bugs`, except it blinds the gate itself.

So: **the RED lives in a standalone repro file over F1–F4** (precedent:
`t/bootstrap/ir/llvm-mainline-die.t`), red-then-green and scoped to what is being
fixed. The TypedInvariant leg lands green at the end of step 4.

**The op set, defined correctly.** v2 said "narrow to what the Block fixup threads."
That is wrong twice: the Block fixup (`Actions.pm:1686-1752`) threads the **full**
ten-op `%STATEMENT_EFFECT_OPS` table by *position*, not by op — and it **never runs on
the producer-built graphs this leg checks**. An implementer who greps `Actions.pm`
derives the wrong set.

The set comes from the **producer's build-site policy**, verified by reading the
construction sites:

| Op | Producer pins `control_in`? | Evidence |
|---|---|---|
| Print | always | `FromOptree.pm:2091` |
| Assign | always | `FromOptree.pm:1717` |
| Return | always | measured 156/156 |
| Call | after step 4.4 | `:1155`, `:1188` |
| Unwind | after step 4.2 | `:783-785`, `:3813-3815` |
| RegexSubst / RegexMatch / Match | **never, in any position** | `:760`, `:1536`, `:1543` — bare `make()`, no `set_control_in` |

Start green with `{Print, Assign, Return}` (measured 15/0, 25/0, 156/0 on HEAD);
step 4 extends it to `{Call, Unwind}` as its own acceptance criterion. Measured after
step 4: **0 violations on all 156.**

The exemption must be written as a **falsifiable claim** — *"the match family is
value-ordered through its `RegexCapture`/`Assign` data edges"* — not as a citation.
Supporting evidence, and its limit: a reviewer tried and **could not** construct a
miscompile from an unpinned regex node (two ordered `s///` give `Str:caa`, two matches
with both captures read give `Str:abcd`, both matching perl). That is evidence, not
proof. `NotMatch`/`BacktickExpr` have **zero corpus instances** and must be settled by
code inspection, not by the corpus.

**Scope the claim honestly.** This polices *a chain-break on a node present in the
graph*. It does **not** catch F4 in either shape — the graph is `Start Constant
Return`, there is no node to flag — and post-fix it cannot detect an F4 regression
either. It also cannot see an F2 backend-scan regression, since that is not a
`$g->nodes` property. Say so at the check site, along with the fact that the leg
receives `$g->nodes` only, so control-only-reachable effects are invisible to it.

### Step 2 — delete the wire `cfg` flag

Genuinely dead. `Serialize/JSON.pm:17` defines `%CFG_OPS`, `_is_cfg` at `:37` is used
by the emit at `:296`, then the loader at `:372` reads `$nd->{cfg}` **off the wire**
instead of consulting the table 355 lines above; `:476` branches on it. All copies are
the identical 7-op list and `%CFG_CLASSES` (`NodeFactory.pm:116-118`) covers exactly
those 7, so deriving from the op is provably equivalent. Origin `e75c8447`,
**2026-04-07** — older than the namespace divorce, older than `%STATEMENT_EFFECT_OPS`,
older than `control_in` being on the base node.

**Three parts, not two.** v2 missed a third loader.

1. **2a-chalk** — `lib/Chalk/IR/Serialize/JSON.pm:372` derives locally.
2. **2a-producer** — `~/dev/perl5-son/lib/SoN/IR/Serialize/JSON.pm:368` derives
   locally. Consumed by `t/from-optree-control-in-forward-ref.t:53` and
   `t/from-json-classes-branch.t:47`.
3. **2b** — both emitters stop emitting: `SoN/Serialize/JSON.pm` (the live emitter,
   `lib/B/SoN.pm:13`) and chalk's `:296`.

**Order matters.** Land 2b before either loader derives locally and every CFG node in
those producer tests flips from fresh-per-call to hash-consed — the exact collapse
`%CFG_OPS` exists to prevent (`NodeFactory.pm:144-155`, 019eb6ff item 1). The two
producer serializers are **not** twins: normalized `diff` is 1185 lines.

**Test cost:** chalk `t/bootstrap/ir-serialize-json.t:39`
(`like($json, qr/"cfg"\s*:\s*true/)`); producer `t/serialize-json.t:71-73`. The
embedded fixture at `:236` and `mop-fence-base.pm` (a text snapshot for
byte-comparison, never executed) are unaffected — the fixture JSON still loads once
the loader ignores the key.

### Step 8 — file the gate blind spot (widened)

Not "the shape leg does not check `If` operands". `_rooted_match`
(`MdtestCorpus.pm:1146-1159`) starts at `Return.inputs[0]` and descends **value
operands only**, so any node reachable only through control gets a presence check and
**never** an operand check. Measured: identical → PASS; wrong `If` condition → PASS;
wrong branch-arm store value → PASS.

File as **"the shape leg does not check operands of control-reachable nodes."** This is
the prerequisite for the cut `If`/`Loop` normalization ever being safe.

## Cut, with reasons

**`If`/`Loop` → `control_in` — CUT.** Largest diff, smallest oracle: ~120-131
positional `make('If'|'Loop')` sites across 23-27 files (counting method varies;
magnitude is not in dispute), 30 ir-block lines (7 two-operand `If`, 16 one-operand
`Loop`), plus `Loop`'s `inputs[1]` backedge index shifting against 77 `backedge`
references. **Nothing validates it** — step 8 shows the gate is blind to exactly what
it changes, so those sites could keep passing while silently constructing malformed
`If`s. The largest single site is `t/lib/Chalk/CodeGen/Harness/HandGraphs.pm:31` —
**the shape leg's own spec oracle**, so the diff would edit the oracle and the subject
together. The shim it deletes has zero measured runtime cost and is already correct at
the reader (`If.pm:19-25`). **Blocked on step 8.**

**Identity-branch collapse — CUT.** Both reviews found the same hazard independently:
`make_cfg` (`NodeFactory.pm:352-361`) **never writes `$cache{$id}`**, `all_node_ids()`
(`:367-369`) returns `keys %cache`, `DCE.pm:47` iterates it and `:71` calls
`remove_node`. Merging puts `If`/`Proj`/`Region`/`Loop` into DCE's worklist **for the
first time** — silent-miscompile-shaped, for ~25 lines. The blocks are also not
byte-identical (differing class-maps and die text), and their 13 comment lines each
record a distinct historical miscompile that CLAUDE.md forbids deleting. It is
cross-repo, and during review it **half-landed undetectably**: applied to chalk only,
full gate and both suites stayed green.

**Cross-repo drift detector — CUT, as a pair with the collapse.** Measurement
re-derived exactly: 91 shared files, **90 code-identical**, sole diff
`Serialize/JSON.pm`. That is the argument against it — **the measurement is the
detector**, one shell loop with a `sed` normalize, no committed file and no allowlist
to maintain. The detector existed only to police the duplication the collapse would
half-migrate; deleting both removes the hazard instead of instrumenting it.

## Beyond scope, filed not folded

**There is no exit-code oracle anywhere.** `Mode1Runner.pm:167` turns any nonzero lli
exit into a skip and never compares `$?`. That is why F1's dropped `print` is invisible
to the harness, why F2 reads PASS while returning `Int:1` where perl exits 255, why
T2b is GAP-declared, and why this plan's die-in-arm corpus case can only be a marker.
Adding the comparison is small **but not free** — nobody has measured how many
currently-green cases would flip.

Also out of scope: the world token (DEFERRED, revisit when GCM is designed —
`chalk-parse-perl-plan.md:763`); fixing the step-8 blind spot; unifying the two
`NodeFactory.pm` copies (measured drift zero); the `Int:N` epilogue
(`Target/LLVM.pm:1006`), independently confirmed as the real exec-gate blocker —
`hello` fails on the `Undef:` epilogue line, **not** ordering.

## Verification

**The corpus gate is mandatory and coordinator-self-verified on committed HEAD after
every step** — floor 156, three legs, worklist 0. Never a subagent self-report.
Shadow-copy numbers here are evidence for planning only; every one that was
independently re-derived this round is marked "measured".

Cross-repo: chalk on `phase5-capstone`, perl5-son on `pu`; producer suites need
`prove -Ilib -Iblib/lib -j1` on a **clean** build (stale blib masks deletions).

## Correction this work carries

`2026-07-23-slice-b-inliner-effect-ordering.md:259` claims "the silent effect-drop
miscompile class is CLOSED". F4 is reproduced live on HEAD with no GAP — Commit 1's
guard inspects only the *callee's* attachment paths; the caller-side drop is
unguarded. True as scoped to the callee, **false as stated about the class**.

`2026-08-02-effect-world-token-design.md`'s deferral header says this work "removes
two mechanisms" — correct it to one plus one site. The deferral itself stands: its
rejection reasons (sibling-arm unsoundness, closes one of four bugs, arity ≠ ordering)
do not depend on the mechanism count.
