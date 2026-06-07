# Spec: mdtest-style Typed-IR Corpus Format

**Date:** 2026-06-07
**Status:** DECIDED SPEC (all five open format questions resolved by perigrin
2026-06-07; see "Resolved decisions" below). Ready to build the runner +
migrate topic-by-topic. This replaces the earlier "draft for review" status.
**Decisions baked in (perigrin):** assertion surface = behavior + typed-IR shape;
first step = design format + build runner + migrate the existing corpus.
**Prior art mined:** `archive/pu-2026-03-24` `t/corpus/{ast,ir}/*.chalk` + `*.json`
(41 IR idioms with a node-graph `type` attribute) and
`docs/differential-testing-pattern.md` (compile→execute→compare-to-perl, the
proven oracle). The archive used SEPARATE mechanisms (a brittle full-graph `.json`
for IR + a differential test for behavior) and a FLAT two-files-per-case layout.
This format UNIFIES them into one self-documenting markdown file per topic, and
asserts IR *shape* declaratively rather than as a brittle full-graph dump.

Inspiration: ruff `ty`'s mdtest
(`crates/ty_python_semantic/resources/mdtest`) — topic-organized `.md` files,
embedded code blocks, inline assertions, cheap to add a case.

## What each case asserts (three layers)

1. **Source** — the Perl (`feature class` subset) snippet.
2. **Behavior** — what perl does when the snippet runs. The OCRACLE is perl,
   auto-captured (NOT hand-written) — the case declares HOW to exercise it
   (the driver/args, like the existing tier-2 exercise specs) and the EXPECTED
   value is whatever perl produces. The corpus author never writes the expected
   value by hand; the runner fills it from perl and the author confirms it.
3. **Typed-IR shape** — what a CORRECT typed SoN graph for this snippet looks
   like, in our Phase-3 model: which nodes, their `representation` (Int/Num/Str/
   Scalar/...), where `Coerce` nodes sit, and (where relevant) the L-corner
   verdict (L-GREEN / GAP-with-reason). This is the half that makes the corpus
   the SPEC B::SoN must produce — it says "for this source, the IR must have
   this typed shape." Asserted DECLARATIVELY (the interesting structure), not as
   a full-graph node-id dump (which renumbers and rots).

## Directory layout (topic-organized, like mdtest)

```
t/corpus/mdtest/
  arithmetic.md        # int/num arithmetic, coercion, div/mod semantics
  variables.md         # my-decl, assignment, compound-assign, increment
  control-flow.md      # if/else, while, foreach, ternary, postfix modifiers
  logical.md           # && || // ! (and their operand-returning semantics)
  strings.md           # literals, concat, interpolation
  references.md        # array/hash refs, deref, nested
  classes.md           # class/field/method/ADJUST/isa
  regex.md             # match, subst, qr
  builtins.md          # map/grep/sort/print/push/...
  ...
```

One `.md` per topic; many cases per file; each case a level-2 (`##`) heading.
A `_config.md` (or frontmatter) per dir may set shared pragma/preamble.

## A case — the markdown shape

Each case is a `## Heading` followed by labeled fenced blocks. Block languages
tag their role. Example file `t/corpus/mdtest/arithmetic.md`:

````markdown
# Arithmetic

Integer and numeric arithmetic, the coercion model, and Perl-specific
division/modulo semantics.

## Integer addition

Two integer literals add as native machine integers — no coercion, no SV.

```perl
# source
1 + 2
```

```behavior
# How perl is exercised + what it produced (oracle-captured; do not hand-edit
# the result — the runner writes it from perl and you confirm).
return: 3
context: scalar
```

```ir
# The typed-IR shape a correct SoN graph must have. Declarative: nodes by role,
# their representation, coercion edges. NOT a node-id full-graph dump.
Constant(1) :Int
Constant(2) :Int
Add(Int, Int) :Int        # native i64 add; no Coerce
Return(Add)
L: GREEN                  # lowers runtime-free; lli output == behavior
```

## Float division

Perl `/` is ALWAYS float division — `3 / 4` is `0.75`, not `0`. The IR must
coerce both operands to Num and divide as a double.

```perl
# source
3 / 4
```

```behavior
return: 0.75
context: scalar
```

```ir
Constant(3) :Int
Constant(4) :Int
Coerce(Int -> Num)        # explicit coercion edge on each operand
Coerce(Int -> Num)
Divide(Num, Num) :Num     # fdiv double; bare sdiv i64 would MISCOMPILE to 0
Return(Divide)
L: GREEN
```

## Integer modulo (right-operand sign)

Perl `%` follows the sign of the RIGHT operand: `-7 % 3 == 2` (LLVM `srem`
gives -1). The IR lowers with sign-correction.

```perl
# source
-7 % 3
```

```behavior
return: 2
context: scalar
```

```ir
Constant(-7) :Int
Constant(3) :Int
Modulo(Int, Int) :Int     # perl-semantics sign-corrected; not bare srem
Return(Modulo)
L: GREEN
```

## Variable read-after-reassign (a known GAP)

A variable read both before and after a reassignment is not yet lowerable
runtime-free (the SSA model has no program-point notion). Behavior is still
specified by perl; the IR shape is the GAP it must honestly report.

```perl
# source
my $x = 1; my $y = $x; $x = 2; $x + $y
```

```behavior
return: 3
context: scalar
```

```ir
# Behavior is specified; runtime-free lowering is a GAP (recorded, not faked).
L: GAP(stale-read: read before+after reassign; needs program-point reads)
```
````

## Block-language roles (the grammar of a case)

- ` ```perl ` (or ` ```chalk `) — the **source** snippet. Required.
- ` ```behavior ` — the **oracle**: `return:` / `context:` / `stdout:` /
  `stderr:` / `exception:` / `object-state:` etc. (the existing widened
  behavior-record axes). Runner-captured from perl; author confirms. Required.
- ` ```ir ` — the **typed-IR shape**: node-by-role lines with `:Repr`
  annotations, `Coerce(From -> To)` edges, and an `L:` verdict line
  (`GREEN` / `GAP(reason)` / would-be-`MISCOMPILE` guard). Optional per case
  (a case may assert behavior only, deferring IR-shape), but encouraged — it is
  the B::SoN spec half.
- Prose between blocks is documentation (the "why"), rendered as the case's
  rationale — the mdtest readability win.

## How the runner uses a case (the three checks)

For each case the runner:
1. **Extracts** the `perl`/`chalk` source, wraps it (pragma + driver per the
   `behavior` block), runs under perl 5.42 → captures S. Asserts S matches the
   declared `behavior` (or, in capture mode, fills it in).
2. **Builds** the typed SoN graph the `ir` block describes (during migration:
   from `HandGraphs`; eventually: B::SoN produces it and we check it matches the
   declared shape), runs it through the well-typed-graph invariant + the harness
   corners (P, L), and asserts the `L:` verdict + behavioral agreement with S.
3. **Records** the per-case verdict into the gap-map (this REPLACES the separate
   `llvm-gap-map.json` idiom table — the `.md` corpus becomes the single source).

## What this consolidates (the debt it pays down)

Today the corpus is THREE scattered places: `t/fixtures/ir-audit-corpus.pl`
(=== TAG catalog), `t/fixtures/codegen-harness/llvm-gap-map.json` (verdict
table), and hand-built graphs in `HandGraphs.pm` + test files. The mdtest
format makes ONE `.md` per topic the source of truth for source + behavior +
IR-shape + verdict — the architecture-review-flagged "stringly-typed config that
needs editing in N places per idiom" goes away.

## CONSTRUCTIVE ir-block (perigrin, 2026-06-07): the markdown IS the graph

Superseding the original "subset assertion against an external graph" model: the
`ir` block is now a COMPLETE, CONSTRUCTIVE, self-contained textual SoN-graph spec.
The runner BUILDS the graph by parsing the block — no external `graph_for`
builders, no `# ir-tag` punt. This makes each `.md` the single source of truth
(source + behavior + the actual typed IR) and gives us a readable, debuggable
SoN-dump format as a bonus. The `LLVMGapMap`/`HandGraphs` builders are RETIRED
into the corpus as topics migrate.

### Syntax: named SSA bindings (decided)

Each node gets a `%name`; inputs reference names. The runner walks lines in order,
mapping each to `factory->make(Op, inputs => [...], ...)` + `set_representation`.

```
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
```

Grammar:
- `%name = Op(args...) :Repr` — bind a node. `args` is a comma-separated list
  where each element is either a `%name` reference (an input) or a `key: value`
  keyword attr. `:Repr` is the representation (Int/Num/Str/Scalar/Bool/...),
  omittable when undef.
  - **N-ary inputs**: any number of `%name` references map to `inputs => [...]`
    in order. Example: `%t = TernaryExpr(%cond, %then, %else) :Int` builds a
    3-input TernaryExpr.
  - **Keyword attrs**: trailing `key: value` pairs (after all `%name` inputs)
    become named parameters on `make()`. Values may be a quoted string `"..."` or
    a bare token. Example: `%ca = CompoundAssign(%lhs, %rhs, op: "+=") :Int`.
- `Coerce(%x : From -> To)` — an explicit coercion node wrapping `%x`
  (e.g. `%cd3 = Coerce(%c3 : Int -> Num) :Num`). This is a special form for the
  Coerce node (not the general kwarg syntax).
- `return %name` — the (synthetic) Return over a value; the runner builds the
  Return node + wires control.
- `control: %a -> %b -> %c` (optional) — declares the control_in chain for
  effectful idioms (VarDecl/Assign sequencing), when control order matters and
  isn't implied by data edges.
- `L: GREEN` | `L: GAP(reason)` — the L-corner verdict (asserted against the REAL
  L corner, never the author's claim).
- A case may have NO buildable graph (pure GAP / not-yet-representable): write
  only `L: GAP(reason)` (no node lines) — the runner records the GAP without
  building/lowering. This is the honest form for idioms the IR can't represent
  runtime-free yet.

### Worked harder cases (proving the format on real idioms)

A1 `my $x = 1; return $x` (variable, control_in matters):
```
%one  = Constant(1) :Int
%xn   = Constant("$x") :Str        # the var name
%vx   = VarDecl(%xn, %one) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx                       # the decl is the control predecessor
L: GREEN
```

arith-div (Coerce edges):
```
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%d3  = Coerce(%c3 : Int -> Num) :Num
%d4  = Coerce(%c4 : Int -> Num) :Num
%div = Divide(%d3, %d4) :Num
return %div
L: GREEN
```

D6 ternary (N-ary 3-input form + NumGt Bool comparison):
```
%n    = Constant(5) :Int
%zero = Constant(0) :Int
%cmp  = NumGt(%n, %zero) :Bool            # binary op -> Bool/i1
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%tern = TernaryExpr(%cmp, %c1, %c2) :Int  # 3-input N-ary form -> LLVM select i1
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %tern) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
L: GREEN
```

C2 compound assign (keyword-arg form for op parameter):
```
%one   = Constant(1) :Int
%xname = Constant("$x") :Str
%vx    = VarDecl(%xname, %one) :Int
%two   = Constant(2) :Int
%read  = PadAccess(%vx, "$x_r") :Int
%sum   = Add(%read, %two) :Int
%lhs   = PadAccess(%vx, "$x_l") :Int
%ca    = CompoundAssign(%lhs, %sum, op: "+=") :Int  # kwarg: op distinguishes += from -=
%rx    = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %ca
L: GREEN
```

L1 `return $a && $b` (pure GAP, no buildable runtime-free graph):
```
L: GAP(&& returns an operand not a bool; needs If+Phi short-circuit)
```

### Runner change (constructive build)

The runner gains a graph-BUILDER: parse the `ir` block -> a symbol table of
`%name -> node`, construct each node via NodeFactory in line order
(set_representation per `:Repr`, wire Coerce from/to, build the Return + control
chain), return the Return node. Then: structural self-consistency is automatic
(the block built it), so the IR check becomes "the block parses and builds a
graph that passes the well-typed-graph invariant (TypedInvariant)" + the L corner
runs that built graph for the `L:` verdict + behavior. The honesty guards still
hold: behavior is perl-captured (never authored), L verdict is checked against
the real corner (a block claiming GREEN that really GAPs FAILS), and a block whose
nodes don't satisfy the typed-graph invariant FAILS loudly.

## Resolved decisions (perigrin, 2026-06-07)

1. **`ir` block syntax = node-by-role LINES** (`Constant(1) :Int`,
   `Coerce(Int -> Num)`, `Add(Int, Int) :Int`, `L: GREEN`). Readable, diffable,
   mdtest-ergonomic. NOT a structured YAML/JSON block.
2. **`ir`-shape match = STRUCTURAL / SUBSET.** The graph must CONTAIN the
   declared typed nodes + coercion edges (+ the `L:` verdict); incidental nodes
   are allowed. NOT an exact full-node-set match. Robust to renumbering and
   incidental structure — assert the interesting shape, not a full dump.
3. **CAPTURE MODE = yes.** On first write, the runner auto-fills the `behavior:`
   block from perl (the author leaves it blank or runs a capture flag); once
   filled it is FROZEN and thereafter ASSERTED. "Never hand-write the expected
   value" made mechanical — the author confirms perl's output, never authors it.
4. **Migration = TOPIC-BY-TOPIC, BEHAVIOR-FIRST.** Migrate one topic file at a
   time; within a topic do the `behavior` layer first (every case green on
   behavior), then add the `ir`-shape layer. Each topic file is fully green
   before starting the next. (The archive's 41 IR idioms + our ~80 tier-1 +
   the gap-map all fold into the topic files this way.)
5. **Location = `t/corpus/mdtest/`.** The `mdtest/` subdir names the format.

## Build order (now that the spec is fixed)

A. **Runner** (`t/lib/.../MdtestCorpus.pm` + a `.t` that drives it):
   parse a `.md` -> cases -> for each: extract `perl` source, run under perl
   (capture S, capture-mode fills `behavior`), build/obtain the typed graph,
   structural-subset-match the `ir` block, run the L corner, assert the `L:`
   verdict + S agreement. Emits per-case verdicts (the gap-map successor).
B. **First topic migration** (`arithmetic.md`): the cases already proven in
   3a-3c (add/sub/mul/div/mod) — behavior-first, then ir-shape. Validates the
   runner + format end-to-end on known-green idioms.
C. **Remaining topics** (variables, control-flow, logical, strings, classes,
   regex, ...) topic-by-topic, mining the archive inventory + existing corpus,
   each green before the next. The `llvm-gap-map.json` idiom table is retired
   into the corpus as topics land.
