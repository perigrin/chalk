# IR Completeness Audit

**Date:** 2026-05-22
**HEAD on `pu` at writing:** `e50d76ba` (with `019a71a7`, `322d0bd1` on
`fixup-audit-baseline` not yet pushed).
**Scope:** Catalogue gaps where Chalk's IR fails to represent
constructs in the Perl subset it claims to compile. Read-only audit
producing a punch list. No source modified.

## Why this audit

The Phase 3/4 audit
(`docs/plans/2026-05-22-phase-3-4-audit.md`) and subsequent design
discussion established two things:

1. **The graph is the program** in Sea of Nodes architecture, not a
   peer to a source-order schedule. A scheduler (GCM or equivalent)
   lowers the graph back into linear emit order. Chalk has no
   scheduler yet.
2. **`MOP::Method->body` is a pre-scheduler workaround** — an
   arrayref of statement-root IR nodes recording what the parser saw,
   used directly by codegen because no scheduler exists to produce a
   schedule from the graph.

Before designing a scheduler we must verify the IR can actually
represent every program we want to compile. If the IR is incomplete,
no scheduler can recover what isn't there.

This audit probes Chalk's Perl subset construct by construct. For
each, it records:

- Does the construct's principal IR node appear in `MOP::Method->body`?
- Is that node also present in `MOP::Method->graph->nodes`?
- If present in the graph, is it reachable from a terminator
  (`Return`/`Unwind`) by any-direction `inputs()` BFS?

A node that is in `body` but not in `graph` represents data the
parser captured but the IR dropped. A node that is in `graph` but
unreachable from terminators represents structure the IR has but
can't be reached by a downstream pass walking from the program's
exits.

## Method

`script/probe-ir.pl` parses a corpus of 56 small Perl snippets
(committed to `t/fixtures/ir-audit-corpus.pl`) covering grammar
categories:

- **A:** variable declarations (5 snippets)
- **B:** bare statement calls — `push`, `print`, etc. (8)
- **C:** assignments and compound assignments (5)
- **D:** control flow — if/else, while, foreach, postfix modifiers,
  ternary, nested, try/catch (8)
- **E:** return/die patterns (4)
- **F:** call expressions (3)
- **G:** deref + subscript (4)
- **H:** map / grep / sort / anonymous sub (4)
- **I:** ADJUST, top-level sub, my sub (3)
- **J:** regex (3)
- **K:** pre/post increment (2)
- **L:** boolean operators (4)

For each snippet, the probe prints `body` and `graph` summaries and
flags two failure modes:

- **[miss]:** body item is not in `graph->nodes` at all
- **[unreach]:** body item is in graph but not reachable from a
  `Return`/`Unwind` terminator by any-direction `inputs()` BFS

## Findings

### Two distinct failure modes, 26 affected snippets out of 56

**[miss] — body item missing from the graph (16 cases):**

| Snippet | Missing node type |
|---|---|
| A4: VarDecl no initializer | `Assign` |
| B1: bare push | `Call` |
| B2: bare print | `Call` |
| B3: bare say | `Call` |
| B5: bare function call no return | `Call` |
| B6: bare method call no return | `Call` |
| B7: bare unshift | `Call` |
| B8: bare warn | `Call` |
| C1: simple reassignment | `Assign` |
| C2: compound assignment | `CompoundAssign` |
| C3: string concat assign | `CompoundAssign` |
| C4: array element assignment | `Assign` |
| C5: hash element assignment | `Assign` |
| I3: my sub | `Chalk::IR::SubInfo` (not even an IR node) |
| J2: regex substitution | `RegexSubst` |
| K1: pre-increment | `CompoundAssign` |
| K2: post-increment | `CompoundAssign` |

**Pattern:** statement-position side-effect operations. The parser
constructs the IR node and stores it as a `body` element, but never
calls `$graph->merge($node)` to register it. The node exists only
in the body arrayref; it never enters the SoN graph.

**Consequences for a scheduler:** zero — these nodes aren't in the
graph at all. A scheduler walking the graph wouldn't see them. The
current codegen survives only because it walks `body`, not graph.

**[unreach] — body item in graph but unreachable from terminator (10 cases):**

| Snippet | Unreachable node type |
|---|---|
| D1: if/else with reassignment | `If` |
| D2: while loop | `Loop` |
| D3: foreach loop | `Loop` |
| D4: postfix if | `If` |
| D5: postfix while | `Loop` |
| D7: nested if | `If` |
| D8: try/catch | `TryCatch` |
| E2: explicit return in branch | `If` |
| E3: return from inside loop | `Loop` |
| E4: die from inside method | `If` |

**Pattern:** control-flow CFG nodes. The parser builds the
`If`/`Loop`/`TryCatch` correctly with branch projections, region
merges, and Phi nodes — but `Return.inputs[0]` (the control input)
points at a pre-CFG node (typically the last `VarDecl` before the
if/loop), not at the Region/Loop the control should flow through.

**Concrete example — D1 (if/else with reassignment):**

Source: `class C { method m($n) { my $x = 0; if ($n > 0) { $x = 1; } else { $x = 2; } return $x; } }`

Graph contains: `Start`, `VarDecl($x=0)`, `If`, `Proj`, `Proj`,
`Assign($x=1)`, `Assign($x=2)`, `Region`, `Phi(merge)`, `Return`,
plus constants.

`Return.inputs[0]` is `VarDecl`. The path Return → VarDecl → Start
**bypasses the entire If/Region/Phi structure.** The if/else
machinery is built and structurally correct in isolation, but the
Return doesn't reach it.

**Consequences for a scheduler:** severe. A scheduler walks back
from terminators to find what code must precede them. With
`Return.inputs[0]` pointing at the wrong node, the scheduler would
emit only `my $x = 0; return $x;` and drop the entire if/else.

### Summary by failure mode

- **30 of 56 (54%) snippets fail.** 16 [miss] + 14 [unreach]
  (D8/E2/E4 not counted twice).
- **Every form of statement-position assignment** fails [miss] (A4,
  C1-C5, K1, K2).
- **Every form of bare-statement call** fails [miss] (B1-B8 except
  B4 `die`, which goes through `ReturnStatement`/`Unwind` path and
  doesn't trigger the miss).
- **Every form of structured control flow** fails [unreach] (D1-D7,
  D8, E2, E3, E4).
- **The IR successfully represents:** plain VarDecl with initializer,
  expression-position function/method calls (where the result feeds
  data flow), literals, qw/regex match, deref/subscript reads,
  boolean operators, anonymous subs, map/grep/sort, ADJUST.

## Two questions the IR doesn't currently answer

1. **For statement-position effects:** what's the canonical way to
   register them in the graph? `Call`, `Assign`, `CompoundAssign`,
   `RegexSubst` are all built as data nodes (no control input field).
   To enter the SoN effect chain they need either a control edge in
   their `inputs` or a separate control-input field, plus a
   `$graph->merge` call at construction.
2. **For structured control flow:** after an `If`/`Loop`/`TryCatch`,
   how does the next statement's control input update? `Return`
   currently uses `_ctx_control($ctx)` which reads `scope->control`,
   and `scope->control` isn't being advanced to the Region/Loop-exit
   when the CFG node is built. The pieces exist; the wiring
   doesn't propagate.

## How this changes the framing

The Phase 3a-migration spec said:

> Each side-effect node's control input is the previous side-effect
> node (or `start` for the first). … Side-effect actions read the
> control input via `$ctx->scope->control`, construct their node
> with that as the control operand, and extend with
> `$scope->with_control($new_node)`.

What shipped in Phase 3a-migration:
- VarDecl: yes, threads correctly.
- Return: yes, threads correctly.
- Everything else listed above: no.

What shipped in Phase 3b (if/else Phi insertion):
- The Phi structure: built correctly, eliminates trivial Phis.
- The control wiring from the if/else's Region back into the
  enclosing scope's control: not done. The Region is constructed
  but `scope->with_control($region)` is not called, so the next
  statement's `_ctx_control` still returns the pre-if VarDecl.

What shipped in Phase 3c (loop Phi insertion):
- Same pattern. Loop nodes built with backedge wiring; surrounding
  scope.control not advanced past the loop exit.

So the Phase 3a/3b/3c work landed the *node construction* but not
the *scope.control propagation*. The data structures are correct;
the linking is incomplete.

## Recommended remediation

This is real compiler work, not plumbing. It should be its own
phase, scoped explicitly. Suggested name: **Phase 3d — IR effect
chain completion.**

### Scope

For each construct in the [miss] list, modify its Actions.pm handler
to:
1. Read `_ctx_control($ctx)` and use it as the control input.
2. Call `$ctx->graph->merge($new_node)` (or equivalent) to register
   the node.
3. Call `$sa->update_scope($scope->with_control($new_node))` to
   advance the chain.
4. Call `$sa->update_graph($graph)` to propagate.

For each construct in the [unreach] list, modify its Actions.pm
handler so that after the CFG node is built and merged:
1. Identify the post-construct control point (Region for if/else,
   Loop exit for loops, post-catch for try/catch).
2. Call `$sa->update_scope($scope->with_control($exit_point))` so
   subsequent statements chain after it.

### Node-shape questions

Adding control inputs to `Call`/`Assign`/`CompoundAssign`/`RegexSubst`
data nodes changes their `inputs` arrayref shape and therefore their
`content_hash`. Two designs to consider before implementation:

- **Prefix the inputs arrayref with a control slot.** Simplest for
  the IR layer; requires updating every codegen reader that indexes
  `inputs` to skip the control prefix.
- **Add a separate `control_in` field on side-effect-bearing node
  classes.** Doesn't disturb `inputs` shape; requires a new field
  declaration per affected class.

Both are real surgery. The decision should be design-doc-shaped, not
ad-hoc.

### TDD targets

The corpus in this audit (`/tmp/ir-audit-corpus.pl`) is a natural
test set. A test file `t/bootstrap/mop/ir-completeness.t` could
codify each probe as an assertion: every body item is in graph AND
reachable from a terminator. Today 30/56 fail; the success state is
56/56.

### Out-of-scope here

- **The scheduler itself.** Cannot be designed against an IR with
  the gaps documented above. Phase 4-scheduler waits for Phase 3d.
- **Phi shape audits.** The audit confirmed Phi nodes are built for
  if/else and loops; whether they're *correct* in all cases
  (nested, multiple-exit, exception paths) is a separate question.
- **Type system completeness.** Whether TypeInference correctly
  annotates all node types is orthogonal.
- **Codegen behavior on incomplete IR.** Today codegen produces
  apparently-correct output for these constructs because it reads
  `body`. Whether the generated code is *semantically* equivalent
  is not tested by byte-compat alone (it might be syntactically
  identical to the input by accident, while masking IR gaps).

## Reproducing

```
$ perl script/probe-ir.pl t/fixtures/ir-audit-corpus.pl > /tmp/out.txt
$ grep WARN /tmp/out.txt | wc -l
27
$ perl -E '
my $cur_label = ""; my $mode = "";
open my $fh, "<", "/tmp/out.txt" or die $!;
while (my $line = <$fh>) {
    chomp $line;
    if ($line =~ /^== (.+)$/) { $cur_label = $1; $mode = ""; next }
    if ($line =~ /WARN:.*NOT in graph/) { $mode = "miss"; next }
    if ($line =~ /WARN:.*UNREACHABLE/) { $mode = "unreach"; next }
    if ($mode && $line =~ /^\s+(\S.*?)\s*$/) {
        say "[$mode] $cur_label :: $1";
        $mode = "";
    }
}'
```

The script `script/probe-ir.pl` is committed with this audit.

## What this audit does NOT prove

- That the constructs which pass [miss] and [unreach] checks are
  *semantically* correct in the IR. They might still encode wrong
  semantics; the audit only confirms structural presence and
  reachability.
- That every Perl construct in Chalk's subset is covered by the
  corpus. The corpus is 56 snippets across 12 categories; deeper
  pathological cases (nested method calls with side effects in
  arguments, e.g.) are not enumerated.
- That the [unreach] CFG nodes will become reachable simply by
  fixing scope.control propagation. The unreached-from-Return
  walking may need additional structural fixes (e.g., Phi nodes
  must merge correctly into the Region's effective control output;
  loop exits need an explicit terminator node the Return can chain
  after).

These are follow-up audits, not blockers to starting Phase 3d.
