# Codegen-Harness Operational Guide

> **Status:** Active. This is the how-to for the corpus-gate workflow: run the
> gate, add an idiom to the corpus, and read the gap map. It documents the
> tooling as it exists — the authoritative gate is
> `t/bootstrap/corpus/son-corpus-wide.t`.

The codegen harness measures how much of the Perl subset lowers end-to-end. It
runs every idiom in the mdtest corpus through B::SoN (the real IR/MOP producer),
lowers the resulting graph to LLVM IR, and checks a **triple contract** per
case. A contributor uses it three ways:

1. [Run the corpus gate](#1-run-the-corpus-gate)
2. [Add an idiom to the corpus](#2-add-an-idiom-to-the-corpus)
3. [Read the gap map](#3-read-the-gap-map)

The corpus format itself is specified in
`docs/plans/2026-06-07-mdtest-corpus-format-draft.md`; this guide is the
operational companion.

---

## 1. Run the corpus gate

### Command

From the repository root:

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl t/bootstrap/corpus/son-corpus-wide.t
```

No `-I` flags are needed — the test declares `use lib 'lib', 't/lib'`
internally. Run it from the repo root so the `t/corpus/mdtest/*.md` glob and the
`lib`/`t/lib` paths resolve.

### Environment it needs

The test opens with three `plan skip_all` guards. If any dependency is missing
the whole file skips (it does **not** fail), so a green-looking `# SKIP` is not
a pass — check the three paths first:

| Dependency  | Path                                                    | Override env      |
|-------------|---------------------------------------------------------|-------------------|
| perl 5.42   | `$HOME/.local/share/pvm/versions/5.42.0/bin/perl`       | —                 |
| perl5-son   | `$HOME/dev/perl5-son/lib` (checks `B/SoN.pm` is there)  | `PERL5_SON_LIB`   |
| lli (LLVM)  | `/usr/lib/llvm-15/bin/lli`                              | —                 |

The runner sets `CHALK_G7_TEST=hostval` for itself so the `host.md` H3 case
(`$ENV{CHALK_G7_TEST}`) gate-greens as it does in the dedicated `host.t` runner
— both the perl oracle and the `lli` child inherit the runner's environment.

### What it checks: the triple contract

For each case that is **not** a declared GAP, the gate asserts three things and
only counts the case as `gate-green` when **all three** hold:

1. **behavior** — the case source is run two ways and the type-tagged results
   must be byte-equal:
   - **perl oracle**: source run under perl 5.42, result printed as a canonical
     type tag (`Int:5`, `Bool:1`, `Bool:` for false, `Str:hi`, `Num:3.5`,
     `Undef:`, `Slot:` for bounds-checked element reads). The tag rule lives in
     `t/lib/Chalk/CodeGen/Harness/TypeTag.pm`.
   - **lli**: the case source goes through B::SoN (`-MO=SoN,json`), the JSON IR
     is loaded (`Chalk::IR::Serialize::JSON::from_json`), lowered
     (`Chalk::Target::LLVM->lower`), and the `.ll` is run under `lli`. Its
     stdout must equal the oracle's.
2. **shape** — a rooted-subset check (`shape_subset_check`). Every node
   signature the case's `ir` block declares must appear in the real producer
   graph, and the return wiring must match position-by-position. The real graph
   is allowed to carry *extra* scaffolding (pads, VarDecls, control) the
   hand-authored block omits — subset, not equality.
3. **invariant** — `Chalk::IR::Graph::TypedInvariant->check` over the loaded
   graph's nodes: the graph must be well-typed.

Each leg is exception-isolated: a die walking one graph costs that one case, not
the whole run.

### The `L:` verdict system

Every `ir` block ends with an `L:` line that declares whether the idiom is
expected to lower:

- **`L: GREEN`** — this idiom should lower end-to-end. The gate runs the full
  triple contract. If it passes, the case is `gate-green`. If it fails, the case
  becomes a **worklist** item (see below) — a TODO, not a hard failure.
- **`L: GAP(reason)`** — this idiom is *not* yet lowerable (needs an unbuilt IR
  node, an LLVM feature not in the slice, etc.). The gate skips the triple
  contract and records the case as `gap-declared`. The reason string documents
  why and, by convention, what would flip it to GREEN.

`parse_l_verdict_from_ir` reads this line; the default when no `L:` line is
present is `GREEN`.

### The floor assertion

The gate ends with a hard floor:

```perl
cmp_ok($tally{gate_green}, '>=', 97, 'gate-green floor (97; ...)');
```

This is the one real assertion in the file. `gate-green` cases must never
silently regress below the floor. Everything else (`worklist` items) is TODO, so
red = work-to-do, not a broken build. **When new GREEN idioms land, raise the
floor** — the floor's message is a running log of what most recently moved it.

### Reading the output

The final `TOTAL:` diag line is the scoreboard. A current run:

```
# TOTAL: gate-green=97  behavior=97  shape=97  invariant=97  gap-declared=13  worklist=0  (no-source sections=0)
```

- `gate-green` — passed all three legs (the number that matters).
- `behavior` / `shape` / `invariant` — per-leg pass counts (diagnostic: when
  these exceed `gate-green`, some case passes two legs but not the third).
- `gap-declared` — cases marked `L: GAP`.
- `todo` — cases with NO `ir` block, plus cases whose `ir` block is pure-GAP
  (only an `L: GAP(...)` line, no node lines). The shape and invariant legs
  report `TODO` for these: an unwritten spec is work we intend to do, not a
  check that does not apply. They never count toward `gate-green`. Distinct
  from `SKIP`, which is reserved for a genuinely inapplicable check — an
  unbuildable or unwalkable spec block, whose finding another leg reports.
- `worklist` — `L: GREEN` cases that failed the contract (should-lower but
  doesn't). `worklist=0` means every declared-GREEN idiom actually lowers.
- `no-source sections` — `##` headings with no `perl` block (prose only).

---

## 2. Add an idiom to the corpus

The corpus lives in `t/corpus/mdtest/*.md`, one topic file per family
(`arithmetic.md`, `classes.md`, `control-flow.md`, `variables.md`, `strings.md`,
`references.md`, `regex.md`, `logical.md`, `increment.md`, `statements.md`,
`subs.md`, `host.md`). Add a case to the topic file it belongs to.

### Case format

A case is a `##` heading followed by up to three fenced code blocks. The parser
(`t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm`, `parse_file`) keys off the
heading and the fence language tags (`perl`, `behavior`, `ir`):

    ## A1 my-decl with init and read

    Prose describing the idiom (optional, ignored by the runner).

    ```perl
    # source
    my $x = 1; $x
    ```

    ```behavior
    return: 1
    context: scalar
    ```

    ```ir
    %one  = Constant(1) :Int
    %xn   = Constant("$x") :Str
    %vx   = VarDecl(%xn, %one) :Int
    %rx   = PadAccess(%vx, "$x") :Int
    return %rx
    control: %vx
    L: GREEN
    ```

**The three blocks:**

- **`perl`** (also accepts `chalk`) — the idiom source. The last expression is
  the value under test (the oracle evaluates it as `do { ... }` in scalar
  context). A leading `# source` comment is conventional and stripped. Class
  cases declare the `class { ... }` and then use it in the driver body; the
  corpus-wide runner splits class declarations from the driver automatically.
- **`behavior`** — the expected result. `return:` is the value; `context:` is
  usually `scalar`. The `return:` value may be a bare literal (`1`, `hi` — the
  runner infers the tag) or an explicit type tag (`Str:Empty`, `Int:-10`,
  `Bool:`, `Undef:`). Prefer an explicit tag when the type is load-bearing
  (a Bool result vs its `Str` coercion is only distinguishable when tagged).
- **`ir`** — the named-SSA IR block, ending in an `L:` line. `%name = Op(...)`
  lines each build one IR node; `return %name` names the return value;
  `control:`, `branch_control:`, and `loop_backedge:` lines wire control edges.
  See the corpus-format draft for the full node grammar. For a declared GAP, the
  block may be minimal — just enough to satisfy the behavior oracle plus the
  `L: GAP(...)` line.

### How a new case behaves in the gate

- **New `L: GREEN` target that actually lowers** → `gate-green` count goes up.
  Raise the floor in `son-corpus-wide.t` to lock it in.
- **New `L: GREEN` target that does NOT yet lower** → shows up as a **worklist**
  item (a TODO `fail`, listed under `=== worklist ===`). This is the intended
  way to declare "this idiom *should* lower and here is the shape we want" as a
  red-until-implemented target. It does not break the build (it is TODO), but it
  keeps the goal visible. Do not raise the floor until it turns green.
- **New `L: GAP(reason)` target** → recorded as `gap-declared` and skipped by
  the triple contract. Use this for idioms genuinely outside the current
  lowering slice; the reason string is the documentation of what is missing.

### Bilateral coverage (from CLAUDE.md)

If your idiom touches operator precedence or rule chaining, the project's
coverage rules apply — a one-sided test can pass on a grossly wrong number:

- **Precedence levels**: cover at least one operator on **each** side of the new
  level (one tighter, one looser).
- **Rule chaining** (a rule that combines in chains): also cover multi-level
  invocations — `f X`, then `f g X`, then `f { ... } g X`. A flat-only test set
  can pass while chained contexts break.

---

## 3. Read the gap map

There are two gap-map surfaces. Know which is live.

### Live gap map: the gate's own diag output (source of truth)

The gate prints the current gap map every run. This is the authoritative,
always-fresh view because it re-measures the corpus against the real producer:

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl t/bootstrap/corpus/son-corpus-wide.t 2>&1 \
  | grep -A99 '=== Phase 4 corpus-wide status'
```

Three sections come out of the run:

- **`=== Phase 4 corpus-wide status ===`** — a per-topic table:
  ```
  control-flow    gate=7  behavior=7  shape=7  inv=7  gap=6  worklist=0
  ```
  Read `gap=N` to see how many idioms in a topic are declared GAP, and
  `worklist=N` for should-lower-but-don't.
- **`TOTAL:`** — the corpus-wide scoreboard (see [§1](#reading-the-output)).
- **`=== worklist ===`** — one line per `L: GREEN` case that failed the triple
  contract, each with the failing leg and reason
  (`lli 'X' != perl 'Y'`, `shape: missing [...]`, `invariant: ...`). This is the
  concrete to-do list. When `worklist=0` the section is absent.

To read **which idioms are declared GAP and why**, grep the corpus directly —
the `L: GAP(...)` reason string is the per-idiom documentation:

```bash
grep -rn 'L: GAP' t/corpus/mdtest/*.md
```

Each hit names the idiom's topic/line and its reason, e.g.
`control-flow.md:520:L: GAP(foreach body writes the iterator: aliasing
write-back to the array not modeled)`.

### Fixed snapshot: `script/print-gap-map.pl`

`script/print-gap-map.pl` exists and runs:

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl script/print-gap-map.pl
```

It pretty-prints `t/fixtures/codegen-harness/gap-map.json` — a **fixed,
committed snapshot** from an earlier codegen-harness milestone (verdicts are
`PASS`/`DEFERRED`/`REJECT` over a `denominator` of 80, keyed by hand-authored
graphs). It is **not** re-computed from the live corpus and does **not** reflect
the current `gate-green` count. Use it only for the historical hand-graph
verdict record; for the current state of what lowers, use the gate's diag output
above.

---

## Quick reference

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl

# Run the gate (from repo root)
$PERL t/bootstrap/corpus/son-corpus-wide.t

# Scoreboard only
$PERL t/bootstrap/corpus/son-corpus-wide.t 2>&1 | grep '^# TOTAL'

# Live gap map (per-topic table + worklist)
$PERL t/bootstrap/corpus/son-corpus-wide.t 2>&1 | grep -A99 '=== Phase 4 corpus-wide status'

# Declared GAPs and their reasons
grep -rn 'L: GAP' t/corpus/mdtest/*.md

# Fixed hand-graph snapshot (historical, not live)
$PERL script/print-gap-map.pl
```

### Key files

- `t/bootstrap/corpus/son-corpus-wide.t` — the authoritative gate.
- `t/corpus/mdtest/*.md` — the idiom corpus (one file per topic).
- `t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm` — corpus parser + shape check.
- `t/lib/Chalk/CodeGen/Harness/TypeTag.pm` — the type-tag oracle rule.
- `script/print-gap-map.pl` + `t/fixtures/codegen-harness/gap-map.json` — fixed
  hand-graph snapshot.
- `docs/plans/2026-06-07-mdtest-corpus-format-draft.md` — the corpus format spec.

## Harvester reproducibility (pinned perl5 blead SHA)

The `t/`-conformance harvester sources its corpus from a checkout of perl5
blead (`~/dev/perl5`). A corpus harvested against an unpinned/moving Perl is a
corrupted oracle, so the SHA is **pinned** as a single source of truth.

- **Pinned SHA:** `94e5086608`
- **Single source of truth:** `t/lib/Chalk/CodeGen/Harness/HarvestPin.pm`
  (`HarvestPin->pinned_sha`). No other harness module hard-codes the SHA; the
  test `t/bootstrap/corpus/harvest-pin.t` enforces that invariant.
- **Decision — regenerate-gated-on-SHA (not vendor):** the corpus does not
  exist yet, so we do NOT vendor Perl's `t/` into this repo. Instead, a future
  harvest run must call `HarvestPin->verify_checkout($perl5_path)` first and
  **refuse to proceed** unless the checkout is at the pin with a clean tree.
  `verify_checkout` only VERIFIES — it never regenerates or mutates the
  checkout. Re-harvest is a deliberate, separate act (no implicit drift).
- **Drift is LOUD.** `verify_checkout` returns `status` of `ok` / `mismatch`
  (HEAD is a different SHA — detail names both) / `absent` (checkout missing) /
  `dirty` (`git status --porcelain` non-empty — never harvest from a dirty
  tree). Every non-`ok` status carries `loud => 1`.

Bumping the pin is intentional: change the literal in `HarvestPin.pm` (and this
note), then re-run `harvest-pin.t`.
