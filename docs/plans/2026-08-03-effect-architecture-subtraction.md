# Design: effect-architecture subtraction — 6 mechanisms to 4, 0 checks to 1

**Status:** design, awaiting review. Not a plan; no implementation.
**Supersedes (for now):** `2026-08-02-effect-world-token-design.md`, now DEFERRED —
same four bugs, ~1/10th the cost, and it *removes* mechanisms instead of adding one.
**Prior art:** `docs/research/2026-08-02-effect-ordering-prior-art.md`.

## The thesis

Chalk's effect handling is **partly accretion, and the accreted parts are provably
removable**. Two of six mechanisms are dead. One is a single rule expressed five
times. One is a compatibility shim standing in for a migration that never happened.
Two are load-bearing and correctly designed. There is no check anywhere.

The system needs **subtraction**. The previously-proposed world token was addition —
a new mechanism, a new validator, and world Phis layered on top of a system where two
of the six existing mechanisms were already dead code nothing was checking.

Every number below was measured in shadow copies with both real repos untouched.
**Every step must be re-verified by the coordinator on committed HEAD** — shadow-copy
numbers are evidence for planning, never acceptance.

## What the architecture would be if designed today

| # | Need | Realisation | Verdict |
|---|---|---|---|
| 1 | effect ordering | `control_in` (M1) | keep — correct |
| 2 | memory-location ordering (the finer slice) | memory-SSA / `MemStart` (M4) | keep — correct |
| 3 | branch structure | `inputs[0]` on `Proj`/`Region` (part of M2) | keep |
| 4 | per-position identity | `%STATEMENT_EFFECT_OPS` + `%ALLOC_OPS` + 5 dispatch branches + wire `cfg` (M3+M6) | **one set, one branch** |
| — | a check that #1 is total over the effectful set | *nothing* | **missing** |

Four mechanisms and one check. Today: six mechanisms and zero checks.

Worth noting against the deferred design: need #2 **already exists**. The world-token
doc called memory slicing "future optimization" while `MemStart` was shipping it.

## Mechanism archaeology

| Mech | Origin | Live problem? |
|---|---|---|
| M1 `control_in` | `3f745573` 2026-05-22 (promote to base Node) | **YES** — the ordering edge |
| M2 control in `inputs[0]` | `f003f173` 2026-05-22 | **SPLIT** — `Proj`/`Region` structure: yes. `If`/`Loop` control: **shim** |
| M3 identity tables | `4e0d7ba8` 2026-06-11 (hash-cons collapse) + `d1e94ad8` 2026-06-12 (alloc aliasing) | **YES as policy, NO as dispatch** |
| M4 memory-SSA | 2026-07-05 | **YES** |
| M5 `Return.inputs[1..]` | exists *because of* the producer's `if $void` guard | **RESIDUE** |
| M6 wire `cfg` flag | `e75c8447` **2026-04-07** | **RESIDUE** |

### M6 is the oldest artifact and it is dead

`Serialize/JSON.pm:17` defines `%CFG_OPS`; `_is_cfg` at `:37` uses it for the *emit*
side; then the loader at `:372` reads `$nd->{cfg}` **off the wire** instead of
consulting the table 355 lines above it. The file asks the wire a question it can
answer itself.

Its only readers anywhere are three assertions at `perl5-son/t/serialize-json.t:71-73`
— a change-detector on a field nothing consumes. Origin 2026-04-07: older than the
namespace divorce, older than `%STATEMENT_EFFECT_OPS`, older than `control_in` being
on the base node. The op-set is duplicated **five** times: `Chalk/IR/NodeFactory.pm:117`,
`Chalk/IR/Serialize/JSON.pm:17`, `SoN/IR/NodeFactory.pm:117`,
`SoN/IR/Serialize/JSON.pm:17`, `SoN/Serialize/JSON.pm:16`.

### M3 is one rule written five times

`NodeFactory.pm:261-314` holds four byte-identical blocks — `%ROUTED_CFG`, `VarDecl`,
`ListAssign`, `%STATEMENT_EFFECT_OPS ∪ %ALLOC_OPS` — each doing `$cfg_counter++`,
`"${op}#${n}"`, `_register_consumers`, cache, return. `make_cfg` at `:352` is the
fifth. **Only the comments differ**, each recording a different historical reason for
the same rule.

Corroborating evidence in the same region: six comments say *"Mirrors Bootstrap's…"*;
`%INPUT_SPECS:138` carries `Return => ['value'], # though Actions uses inputs => [$ctrl, $val]`
— a table entry documenting that it does not match its caller; `%CFG_CLASSES`' header
states `Start`/`Return`/`Unwind` have two different identity policies depending on
which factory method the caller happened to pick.

### The two-slot convention is a shim, by its own documentation

`If.pm:19-25`: *"Override the reader so a walker that calls `$node->control_in()` gets
a consistent answer regardless of whether the node is a CFG control-flow node or a
statement-position data node."*

Already normalized **at the reader**; the *storage* was never migrated. Same
"literal moved, contract didn't" pattern CLAUDE.md flags for `compat_class`.

`If` is also built two ways: chalk's frontend named (`make('If', control => …)`, 11
sites), the producer positional (`make_cfg('If', inputs => [$ctrl, $cond])`, 6 sites).
`%INPUT_SPECS` exists purely as the adapter between them.

## The work, ordered by value per line

Each step is independently gate-verifiable. Dependencies noted.

| # | Change | Kind | Lines | Test cost |
|---|---|---|---|---|
| 1 | `If`/`Loop` control → `control_in`; delete both shims | normalize 2→1 | **−46** lib | 6 chalk + 1 producer test file; 12 stale ir-blocks |
| 2 | Delete the wire `cfg` flag; loader derives from `%CFG_OPS` | **delete a mechanism** | ~−10 | 3 assertions, `perl5-son/t/serialize-json.t:71-73` |
| 3 | Collapse the 5 identity branches into one `%FRESH_ID_OPS` | normalize 5→1 | **−30/repo** | none |
| 4 | The four-bug fix (see below) | correctness | +20/−11 | 3 subtests, `from-optree-method-dispatch.t:92-102` |
| 5 | Delete `LLVM.pm:909` (M5 seed) | **delete a mechanism** | −1 | none — **requires 4** |
| 6 | Control-chain leg in `TypedInvariant.pm` | **add the missing check** | ~+20 | none |
| 7 | Cross-repo drift detector | add | +6 | none |
| 8 | File the shape-leg `If`-operand blind spot | file an issue | 0 | — |

**Net: 6 mechanisms → 4, 0 checks → 1, −56 lines** (−86 once #3 lands in both repos).

### Step 4 — the four-bug fix, itemised

All four measured miscompiles, ~20 lines across two files in two repos:

- **F1 mainline die.** `SoN/FromOptree.pm:783-785` and `:3813-3815` emit
  `inputs => [$sim->control, $args->@*]` and never call `set_control_in`. Change to
  `inputs => [$args->@*]` + `$unwind->set_control_in($sim->control)`. Mirrors
  `Bootstrap/Perl/Actions.pm:1450-1458`; the surrounding producer code already does
  this for `Print` (`:2092`), `Assign` (`:1718,1769,1785,1807`), void `Call` (`:1189`).
  `Unwind` is the only holdout. **+2/−2.** Executable gate 0 → 1.
- **F2 die-after-effect-in-arm.** After F1 the IR is already correct; the defect is
  `_find_unwind_consumer`'s one-hop consumer scan
  (`Target/LLVM/Context.pm:2836-2843`, assumption stated in its own comment at
  `:2833-2835`). Replace with a BFS over consumers-whose-`control_in`-is-this-node,
  stopping at `Region`. **+11/−3.**
- **F3/F4 inlined effect reordered / dropped.** `FromOptree.pm:1156` and `:1189`:
  `$node->set_control_in($sim->control) if $void;` — a non-void `Call` gets no control
  pin, so it is unreachable from `Return` and the producer's reachability walk drops
  it. Pin unconditionally; push the value only when non-void. **This is the R1.0
  effect-by-default decision** (memory `effect_by_default_call_classification`).
  **+6/−4.** `_place_call` (5 lines) becomes dead.
- **F3 residual.** Pinning exposes a latent backend bug: `_lower_call_direct` never
  writes its result to `{cache}`, so the same `Call` inlines twice (measured: two
  `printf` calls, two `@str_const` globals for one literal). Memoize at
  `Context.pm:4384` and `:4408`. **2 lines edited.**

### Step 6 — the check, and why it goes in TypedInvariant

**Not** at construction: `set_control_in` is a late-binding setter by design
(`Node.pm:117-131`) because `Actions.pm`'s Block control-chain fixup sets it after the
fact — 13 of chalk's 19 call sites are in that one file.

At **graph completion** it works, and the chokepoint already exists and is already
wired into the gate: `TypedInvariant.pm` is the corpus's third leg, runs on all 156
cases, is 174 lines, and contains zero control/effect assertions today.

Invariant: every op in `%STATEMENT_EFFECT_OPS ∪ {Return, Unwind}` has a defined
`control_in`. ~20 lines, **zero ir-block rewrites** — it inspects `control_in`, which
the ir-block format carries on its `control:` line and which is not part of any
operand list.

It does not make the bad state unrepresentable. It makes it **un-shippable**. On this
project that is the property that matters.

### Step 7 — drift detection, not a conformance test

Measured: of 91 duplicated files between `lib/Chalk/IR/**` and `lib/SoN/IR/**`, **90
are code-identical** with comments and namespace normalized away. One genuinely
diverges (`Serialize/JSON.pm`, 70 lines — expected, the loader half is chalk-only).
The four other "differing" files are **comment-only differences**.

The 2026-08-01 divorce plan explicitly decided against a cross-repo conformance test
on the grounds that measured drift was zero. **Two days later it is still zero
executable lines — that cut stands.**

But "no conformance test" is not "no detector". A ~6-line normalized `diff` (strip
comments, normalize `Chalk::`/`SoN::`, allowlist `Serialize/JSON.pm`) asserts nothing
about semantics; it just refuses to let 90 files silently stop being the same file.

**The need was demonstrated in real time:** the reviewer applied step 3 to chalk's
`NodeFactory.pm` and forgot the producer's copy. Full corpus gate and both suites
stayed green. Nothing caught it.

### Step 8 — a gate blind spot found in passing

The shape leg does **not** check `If` operands. Probed directly: an ir-block with a
deliberately **wrong** `If` condition **passes**.

```
spec If(%vx, %cmp) vs real If(%cmp)+control_in  -> PASS
spec If(%vx, %n)   [WRONG condition]            -> PASS
```

This is why step 1 costs zero corpus churn — the leg does not look there. The 12
ir-blocks are still stale *documentation*; they are just not gate-enforced. File it;
do not fix it inside this work.

## Ordering and dependencies

- **5 requires 4** (M5's seed exists because of the `if $void` guard).
- **1, 2, 3 are independent** of each other and of 4.
- **6 and 7 are independent** additions; 6 is most valuable *after* 4, when the
  invariant it asserts is actually true everywhere.
- Suggested sequence: 1 → 2 → 3 → 4 → 5 → 6 → 7, with 8 filed at any point.

## Verification

**The corpus gate is mandatory and coordinator-self-verified on committed HEAD after
every step** — `t/bootstrap/corpus/son-corpus-wide.t`, floor pinned at 156, all three
legs (behavior / shape / TypedInvariant), worklist 0. Never a subagent self-report.

Shadow-copy composite measurement (bug fix + steps 1/2/3/5 layered), for planning
confidence only:

```
corpus:    178 ok / 0 not ok   gate-green=156 behavior=156 shape=156 invariant=156
exec gate: 1/5 (from 0/5)
F1 MATCH   F2 MATCH   F3/F4 ordering correct (residual = the Int:N epilogue)
chalk IR suite 52/58   producer suite 84/86
net lib delta: -56 lines
```

Cross-repo: chalk on `phase5-capstone`, perl5-son on `pu`; producer suites need
`prove -Ilib -Iblib/lib -j1` on a **clean** build (stale blib masks deletions).

### Known test costs, all legitimate

- **`from-optree-method-dispatch.t:92-102`** (3 subtests) assert the *pre-R1.0*
  convention — e.g. "a value-context method call is NOT a statement effect". They are
  change-detectors for a policy being deliberately inverted, not correctness oracles.
  Rewriting them is the honest cost of R1.0.
- **6 chalk + 1 producer test file** hand-build `make('If', inputs => [$ctrl, $cond])`
  positionally. Of 76 `make('If')` sites in `t/`, only these exercise the lowering path.
- **3 assertions** in `perl5-son/t/serialize-json.t:71-73` pin the wire `cfg` field.

The chalk IR suite reads 52/58 in the composite shadow state; the 6 are the
positional-`If` files above. **The coordinator must confirm that attribution on
committed HEAD** rather than accepting it — a red file with an assumed cause is
exactly the pattern `red_tests_hide_real_bugs` warns about.

## Out of scope

- **The world token.** Deferred with named triggers; see
  `2026-08-02-effect-world-token-design.md`.
- **Fixing the shape-leg `If` blind spot** (step 8 files it only).
- **Unifying the two `NodeFactory.pm` copies into one definition.** Step 7 detects
  drift; merging the definitions is a larger cross-repo question and the measured
  drift is currently zero.
- **The `Int:N` type-tag epilogue** (`Target/LLVM.pm:1006`), which is what actually
  holds the executable gate at 1/5 — three of the five programs there fail for the
  epilogue and one for unlowered `exit`, **none for effect ordering**. That is the
  entry/epilogue protocol's work, not this.

## Corrections this work carries

- **`2026-07-23-slice-b-inliner-effect-ordering.md:259`** claims "the silent
  effect-drop miscompile class is CLOSED". Commit 1's guard inspects only the
  *callee's* attachment paths; F4 is a caller-side drop with no GAP possible. True as
  scoped to the callee, **false as stated about the class** — re-scope that line.
- **The F2 bilateral corpus case is missing.** `t/corpus/mdtest/control-flow.md` T2
  (`:1167`) and T2b (`:1204`) are both die-*first*-in-arm. No case puts an effect
  before the die — which is why F2 survived. Add it; per CLAUDE.md's bilateral
  coverage rule this is owed regardless.
- **F3/F4 are not equality REDs.** The unconditional `Int:N` epilogue defeats exact
  comparison for both. **F2 is the good RED** — exact MATCH at exit 255 `"t\n"`,
  because it aborts before the epilogue runs.
