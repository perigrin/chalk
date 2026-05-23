# Codegen Test Triage

**Date:** 2026-05-24
**For:** Phase 5b of the SoN scheduler migration plan
  (`docs/plans/2026-05-24-son-scheduler-design.md`).
**Status:** Triage report. Read-only analysis; no test files modified.

## Scope

Inspected **64** unique test files (62 from the candidate grep + 2 indirectly-affected Tier-C/Tier-D files that route through TestPerlHelpers helper module), plus 3 test helper modules in `t/bootstrap/lib/`.

Filter set used to identify candidates:

1. `grep -rln "generate_with_cfg|->generate(\$ir|->generate(\$raw_ir|MethodInfo|ClassInfo|SubInfo|FieldInfo|UseInfo|_cfg_lookup|cfg_state" t/`
2. `grep -rln "Chalk::IR::Program" t/`
3. `grep -rln "Chalk::Bootstrap::Perl::Target::Perl" t/` (catches tests that use the legacy entry point without naming any of the surface tokens above)

A crucial distinction surfaced during triage: tests calling
`$target->generate($raw_ir)` overwhelmingly use `$target =
Chalk::Bootstrap::BNF::Target::Perl->new()` — that is the **BNF-grammar
target** which emits a generated *grammar parser module*, not the
legacy Perl codegen path. That call is **out of scope** for Phase 6
deletion. The legacy Perl codegen path being deleted is reached via
`Chalk::Bootstrap::Perl::Target::Perl` instances calling `generate($ir)`
(Program input) or `_generate_with_cfg($ir, $sa, $ctx)`. Tests that use
only `Chalk::Bootstrap::BNF::Target::Perl->generate(...)` get classified
on the basis of their *other* legacy-path indicators (cfg_state reads,
Info-struct usage, etc.), not on the BNF generate() call.

False positives identified during triage:

- `t/bootstrap/emit-son-json.t` — only references "UseInfo.pm" as a
  string file path; no legacy-path code.
- `t/bootstrap/son-compare.t` — only references "Chalk::IR::Program"
  etc. as test-case file paths and package names; no legacy-path code.
- `t/fixtures/self-host-probe-2026-05-22.log` — fixture data file, not
  a test.

These three are excluded from the counts below.

## Summary table

| Outcome  | Count |
|---       |---    |
| KEEP     | 28    |
| MIGRATE  | 8     |
| REWRITE  | 19    |
| DELETE   | 10    |

**Total:** 64 unique test files + 3 helper modules. The file
`t/bootstrap/ir-use-info.t` appears in two outcome sections (KEEP and
DELETE) due to an unresolved disposition question — see Open Question
Q1. Counting it once gives the 64-file total; the per-section sum is
65 because of the dual listing.

The DELETE count counts files individually rather than deletion
justifications. Of the 10 DELETE files, 7 are deletions justified by
Info-class deletion (Program / ClassInfo / MethodInfo / SubInfo /
FieldInfo / UseInfo), 1 by Info-class deletion in a combined-type unit
test (ir-metadata.t), 1 by Info-class deletion in a one-tier unit test
(perl-ir-tier-a.t), and 1 is a prototype subsumed by ir-completeness
(ctrl-thread-prototype.t).

Helper modules (`t/bootstrap/lib/`) get separate treatment at the end
of the document; they are not counted in the four-outcome breakdown
above.

## Outcomes by file

### KEEP

These tests do not depend on the legacy Perl-target codegen path. They
either don't call the legacy codegen at all, or their only contact with
the listed surface symbols is incidental (parse-IR consumers that look
at `MethodInfo`/`ClassInfo` shape but don't go through codegen).

After Phase 6 their assertions remain valid against the new MOP-driven
IR shape, provided the parser still produces Info-struct instances at
parse time. Where it doesn't (because Phase 6 deletes those types
entirely), the assertion that "X isa Chalk::IR::MethodInfo" will need
re-pointing to the corresponding MOP types (`Chalk::MOP::Class`,
`Chalk::MOP::Method`, ...). That work is mechanical and orthogonal to
scheduler migration; it's listed here as a Phase-6 follow-up, not as
MIGRATE.

#### `t/bootstrap/cfg-if-else.t`
**Intent:** Verifies parsing `if (X) { ... } else { ... }` produces an
`If`/`Proj`/`Region` Sea-of-Nodes CFG subgraph (If has 2-input shape,
Region has 2-control merge, both Projs share the If parent).
**Why KEEP:** Walks the IR graph after parse; reads `cfg_state` from
the parse-result Context, but only to *find* the Region root for graph
traversal — never asserts on cfg_state shape, never invokes codegen.
After Phase 6, `cfg_state` reader is deleted from Context, so this
test's `$sem_ctx->cfg_state()` call breaks; the test should switch to
walking the MOP-method graph the same way `mop/build-graph-*.t` files
already do.
**Migration action:** Replace the two `$sem_ctx->cfg_state()` →
`$state->{control}` accesses with: pull the MOP from
`Chalk::Bootstrap::Semiring::SemanticAction::current_mop()`, find the
synthesized top-level method's `$graph`, walk to the Region from there.
The graph-walk assertions (Region has 2 Proj controls, etc.) are
unchanged.

#### `t/bootstrap/cfg-loop.t`
**Intent:** Verifies parsing `for my $x (...) { ... }` and `while
(cond) { ... }` produces `Loop`/`Proj`/`If`/`Region` CFG subgraphs.
Test 4 also asserts that the cfg_state carries loop/loop_if/body_proj/
exit_proj/body_stmts/iterator keys — those keys are codegen-internal
to the legacy path.
**Why KEEP** (with one DELETE sub-case noted below): Tests 1, 2, 3
walk the IR graph the same way `cfg-if-else.t` does — they happen to
use cfg_state as a graph-root finder, not as an oracle on cfg_state
shape. They survive the migration.
**Migration action:** Tests 1–3 migrate the same way `cfg-if-else.t`
does: graph-find via the MOP instead of cfg_state. Test 4 ("while
body cfg: state has body_stmts key", etc.) asserts on the legacy
cfg_state shape and **should DELETE**: that shape goes away in Phase 6,
and the new equivalent (ScheduleMeta-on-Loop) is covered by
`t/bootstrap/scheduler/schedule-data-loop-body.t`.

#### `t/bootstrap/cfg-loop-phi.t`
**Intent:** Verifies lazy Phi creation in for-loops: degenerate Phi
for read-only loop-variable, real loop-carried Phi for read-write,
no Phi for unread variables.
**Why KEEP:** Asserts on `Chalk::IR::Node::Phi` *shape and presence in
scope* after parse. Uses cfg_state only to get the post-parse scope.
Scope and Phi shape are first-class IR concerns and survive Phase 6.
**Migration action:** Same as `cfg-if-else.t`: replace
`$sem_ctx->cfg_state()->{scope}` with a MOP-graph walk that finds the
Phi node directly (`grep { $_ isa Chalk::IR::Node::Phi } @nodes`). The
assertion that `$x_binding isa Chalk::IR::Node::Phi` stays.

#### `t/bootstrap/context-cfg-annotation.t`
**Intent:** Verifies the cfg_state-on-SemanticAction read path — that
`$ctx->cfg_state()` reads scope and structural annotations correctly,
that `one()` produces a Context with a Start-control scope, that
`update_scope`/`update_annotations` propagate via multiply.
**Why KEEP:** All assertions are about the Context/Scope mechanism
that survives Phase 6. `cfg_state` is the only legacy-path-named API
this test uses, and even there it's a *read interface* over `scope`
and `annotations` — once cfg_state is deleted from Context, the same
reads work via `$ctx->scope()` and `$ctx->annotations()` directly.
**Migration action:** Replace `$ctx->cfg_state()` reads with
`$ctx->scope()` + `$ctx->annotations()` reads. Assertions on
`$state->{control}`, `$state->{scope}`, `$state->{if_node}` decompose
naturally. The `update_scope`/`update_annotations` propagation test
is untouched.

#### `t/bootstrap/ir-cfg-nodes.t`
**Intent:** Unit tests for CFG IR nodes (If, Proj, Region, Phi, Loop)
— construction, consumer wiring, hash-cons distinctness.
**Why KEEP:** Pure NodeFactory unit tests. Single token-match on
`cfg_state` is in a comment ("CFG nodes represent control flow
positions, not data values, so each creation site must produce a
unique node for cfg_state mapping").
**Migration action:** Drop the stale comment reference to cfg_state
(or leave it — comments are evergreen, this one references a now-
obsolete mechanism but the underlying invariant about non-hash-consed
CFG nodes is still true).

#### `t/bootstrap/ir-graph.t`
**Intent:** Unit tests for `Chalk::IR::Graph` container —
start/returns fields, topological sort, schedule hashref field.
**Why KEEP:** Tests `$graph->schedule()` as a HashRef field. Per the
scheduler design plan, `Graph->schedule` is **explicitly listed for
deletion in Phase 6** (Section 7 Phase 6, item 2). After Phase 6 this
test's `is(ref($graph->schedule()), 'HASH', ...)` assertions fail.
**Migration action:** Drop the four `schedule()`-related tests (lines
48–63). The rest (Start/Return/Add reachability, topological order,
dual-exit graphs) is untouched and load-bearing.

#### `t/bootstrap/ir-return-cfg-node.t`
**Intent:** Verifies the `make_cfg('Return', ...)` factory method
creates `Chalk::IR::Node::Return` nodes correctly and that the
ReturnStatement action produces them.
**Why KEEP:** Tests the IR Node factory and the Return CFG node. The
single `$sa->set_cfg_state(...)` call in the test exists only to give
the multiply() chain a `{control => $start, scope => $scope}` so the
action has something to read. Post Phase 6, set_cfg_state goes away
and the equivalent setup is `$ctx = Chalk::Bootstrap::Context->new(
scope => $scope->with_control($start), ...)` (already the idiom in
`t/bootstrap/scope-variable-lookup.t`).
**Migration action:** Replace `$sa->set_cfg_state($ctx, {control =>
..., scope => ...})` (2 sites) with constructing the Context with
the scope+control directly. The Return-node assertions are untouched.

#### `t/bootstrap/keyword-return-die.t`
**Intent:** Verifies that `return EXPR;` produces exactly **one**
`Chalk::IR::Node::Return` in the method's graph (not two — guards
against an earlier bug where `return` was treated both as keyword and
QualifiedIdentifier).
**Why KEEP:** Uses `Chalk::IR::MethodInfo` only in `use` line; never
constructs one. The assertions walk `$method->graph()->nodes()` and
count Return/Unwind nodes. The MethodInfo lookup happens through
`$cls->methods()`, which is a MOP::Class accessor in the new path.
**Migration action:** Drop the `use Chalk::IR::MethodInfo;` line. The
test as written already works against the MOP API
(`$cls->methods()->@*` is a MOP::Class accessor). After Phase 6 the
test is unchanged.

#### `t/bootstrap/implicit-return.t`
**Intent:** Verifies `_build_method_graph` synthesizes an implicit
Return node when the method body ends without an explicit return,
and that the Return appears in `graph->nodes()`.
**Why KEEP:** Uses ClassInfo/MethodInfo only via `$cls isa
Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2]` dispatch
— a dual-path holdover from an earlier migration. The real work is
graph-walking. After MOP, `$cls->methods()` directly returns
MOP::Method instances with `$method->graph()`.
**Migration action:** Remove the dual-path `$cls isa ... ? ... : ...`
construct and use `$cls->methods()` directly. Drop the `use
Chalk::IR::Program; use Chalk::IR::ClassInfo; use
Chalk::IR::MethodInfo;` lines.

#### `t/bootstrap/mop/block-type.t`
**Intent:** Verifies that Block contexts synthesize a `{graph, type}`
hashref at their focus, with `graph` being a Chalk::IR::Graph and
`type` a return-type string union for branching bodies.
**Why KEEP:** Imports the 5 Info classes only for the
`method_body_block()` helper that *excludes* contexts whose stmts
contain class-body Info objects. The exclusion check decides whether
a Block is a method body vs a class body. Post Phase 6, the MOP no
longer surfaces Info objects in the AST, but the exclusion check
becomes: "stmts contain no class-decl-shaped items" — same logic,
different types.
**Migration action:** When Info classes are deleted, the `grep { $_
isa Chalk::IR::MethodInfo ... } $f->{stmts}->@*` check has to switch
to checking against whatever the new "is this a class body stmt"
marker is (likely a MOP::ClassDecl IR-node-equivalent). The block-
synthesis assertions about `{graph, type}` are unchanged.

#### `t/bootstrap/mop/build-graph-control-chain.t`
**Intent:** Verifies that linear side-effect statements chain control
inputs (`inputs[0]`) back to Start via the Phase 3d Block control-
chain fixup.
**Why KEEP:** No Info-struct usage, no cfg_state usage, no Program
usage. Goes through `Chalk::Bootstrap::Semiring::SemanticAction::
current_mop()`, walks `$method->graph()`. Pure inputs[0]-chain
verification. This is the exemplar of what scheduler integration
tests should look like.
**Migration action:** None.

#### `t/bootstrap/mop/method-implicit-return.t`
**Intent:** Verifies fall-through synthesizes a Return; explicit
returns preserved; nested-Return-in-if becomes a method exit;
nested-Return-in-inner-sub does NOT become an outer-method exit.
**Why KEEP:** Pure MOP-API user. No legacy types in `use` list.
Walks `$method->graph()->returns()`.
**Migration action:** None.

#### `t/bootstrap/mop/method-lexical-bindings.t`
**Intent:** Verifies `MOP::Method->lexical_bindings` exposes the
VarDecls declared in the method body, with correct names and
operation tags.
**Why KEEP:** Pure MOP-API user. No legacy types.
**Migration action:** None.

#### `t/bootstrap/mop/ir-completeness.t`
**Intent:** Asserts every body item produced for the 56-snippet
audit corpus appears in `$method->graph->nodes()` AND is reachable
from a terminator (Return/Unwind). This is the Phase 3d TDD red.
**Why KEEP:** Uses Info classes only as exclusion markers ("skip
metadata structs that ride along in body for codegen — they're not
graph-resident by design"). After Phase 6 deletes Info classes, the
`$item->isa('Chalk::IR::SubInfo')` checks become unreachable (no
SubInfo instances ever appear in body anymore) — they can be deleted,
the loop body remains.
**Migration action:** Remove the 5 `next if $item->isa(...)` lines
once Info classes are deleted. The graph-walk-and-reachability
assertions are unchanged.

#### `t/bootstrap/mop/codegen-byte-compat.t`
**Intent:** Production-path golden tests — parses 19 fixture sources
through the MOP, calls `generate($mop)`, diffs against checked-in
goldens.
**Why KEEP:** This **is** the production test. Phase 5a's gate is
"this file still passes after `_generate_from_schedule` ships." Phase
5b's MIGRATE entries (Tier-A/B/C/D, perl-actions-tier-*) are direct
analogs of this test at per-file granularity.
**Migration action:** None for the file itself. The goldens may be
regenerated post-Phase-8 (semantic-equivalence cutover), per design
decision F.

#### `t/bootstrap/mop/codegen-hand-constructed-mop.t`
**Intent:** Codegen consumes a hand-constructed MOP (not parser-
produced) and produces valid output with no parser-specific coupling.
**Why KEEP:** Already on the new path. Calls `$target->generate($mop)`.
Tests Phase 4's MOP-public-API contract.
**Migration action:** None.

#### `t/bootstrap/mop/codegen-no-backchannel.t`
**Intent:** Asserts that the public surface no longer exposes
`generate_with_cfg` on Target::Perl or `generate_c_files` on Target::C.
Two `ok(!$target->can(METHOD))` assertions.
**Why KEEP:** This *is* a Phase 6 invariant guard. After Phase 6,
additional methods will also be deleted (`_generate_from_mop`,
`_body_from_graph`, `emit_cfg_*`, `_build_cfg_lookup`, `cfg_state`
reader); the test should grow `ok(!can)` checks for each. Survives
intact as a regression guard; just needs more assertions.
**Migration action:** Add `ok(!$target->can('_generate_from_mop'))`,
`ok(!$target->can('_build_cfg_lookup'))`, `ok(!$target->can(
'emit_cfg_if'))`, `ok(!$target->can('emit_cfg_loop'))`,
`ok(!$target->can('emit_cfg_try_catch'))`,
`ok(!$target->can('emit_from_cfg_state'))`,
`ok(!$target->can('_body_from_graph'))`. Match the deletion-list in
Phase 6.

#### `t/bootstrap/mop/codegen-perl-signature.t`
**Intent:** Tests that `Target::Perl::generate($mop)` exists and
returns a HashRef[Str].
**Why KEEP:** Already on the new path. Tests the production signature
contract.
**Migration action:** None.

#### `t/bootstrap/ir-use-info.t`
**Intent:** Unit tests for `Chalk::IR::UseInfo` (construction, id
content-addressing, add_consumer no-op).
**Why KEEP** (with a caveat): The UseInfo type itself is being
deleted in Phase 6. This test goes away **with** UseInfo. But "going
away with the type" is structurally a DELETE outcome for this file
— filed here as KEEP because the *semantics* the test is guarding
(use-decl IR captures name and args) survive in whatever the MOP
replacement is (currently `Chalk::MOP::Import`). The test gets
re-pointed at the replacement type. See also DELETE entries.
**Migration action:** Listed as KEEP in this report on the
"semantics survive" axis; pragmatically this is closer to DELETE.
Flagging the ambiguity in Open Questions.

#### `t/bootstrap/scheduler/schedule-data-foreach.t`
**Intent:** Verifies ForeachStatement populates EagerPinning::Loop
on the Loop IR node (iterator, list, is_for_style=false).
**Why KEEP:** This **is** the new architecture under test. The
`cfg_state` lookup at line 36 (`$result->cfg_state()`) is only used
to fetch the Loop IR node for inspection. After Phase 6 cfg_state is
deleted but the test's real assertions are on
`$loop->schedule_data` (an EagerPinning::Loop ScheduleMeta).
**Migration action:** Replace the `cfg_state` Loop-finder with a
MOP-graph walk that grep's Loop nodes (the same pattern
`build-graph-control-chain.t` uses for VarDecls).

#### `t/bootstrap/scheduler/schedule-data-for-style.t`
**Intent:** Verifies ForStatement populates EagerPinning::Loop with
`is_for_style=true`, `for_init`, `for_step`.
**Why KEEP / Migration action:** Same as
`scheduler/schedule-data-foreach.t`.

#### `t/bootstrap/scheduler/schedule-data-if-else.t`
**Intent:** Verifies IfStatement / ElsifChain / PostfixModifier
populate EagerPinning::If with then_stmts and else_stmts.
**Why KEEP / Migration action:** Same as
`scheduler/schedule-data-foreach.t`. `_parse_if()` helper extracts
the If node via `$r->cfg_state()->{if_node}`; replace with graph-walk
`grep { $_ isa Chalk::IR::Node::If } @nodes`.

#### `t/bootstrap/scheduler/schedule-data-loop-body.t`
**Intent:** Verifies Loop body stmts are exposed via EagerPinning::
Loop schedule_data after parse.
**Why KEEP / Migration action:** Same as
`scheduler/schedule-data-foreach.t`.

#### `t/bootstrap/scheduler/schedule-data-try-catch.t`
**Intent:** Verifies TryCatchStatement populates EagerPinning::
TryCatch with catch_var, try_stmts, catch_stmts.
**Why KEEP / Migration action:** Same as
`scheduler/schedule-data-foreach.t`.

#### `t/bootstrap/scope-variable-lookup.t`
**Intent:** Unit tests for variable-reference resolution from
Context-attached scope — ScalarVariable/ArrayVariable/HashVariable
consult `$ctx->scope()` to resolve bare-variable references to
their bound IR nodes.
**Why KEEP:** Already migrated past set_cfg_state. Comment in test
explicitly states "Phase 3a-infra deleted set_cfg_state — Context's
scope field is now the channel for control + scope state." Uses
`$ctx->cfg_state()` once (line 153) only to read the result's
post-resolution scope; otherwise the test goes directly through
Scope and Context API.
**Migration action:** Replace the one `$result->cfg_state()` call
with `$result->scope()`. The Scope+resolution mechanism survives.

#### `t/bootstrap/semiring-type-inference.t`
**Intent:** 1903-line omnibus testing TypeInference semiring's
keyword detection, scan-time/complete-time tag inference, integration
parses with full pipeline.
**Why KEEP:** Single integration block at line 290 imports
`Chalk::IR::Program` to type-check the extracted IR at line 950
(`$ir_node isa Chalk::IR::Program`). The other 1900 lines of
TypeInference unit tests don't touch the legacy path at all.
**Migration action:** In the one integration subtest, replace
`$ir_node isa Chalk::IR::Program ? [$ir_node->other_stmts->@*] :
$ir_node->inputs->[0]` dispatch with a MOP-aware accessor. Drop the
`use Chalk::IR::Program;` line. ~98% of the file is unchanged.

#### `t/bootstrap/precedence-spec.t`
**Intent:** Conformance test for Perl operator precedence per
perlop.pod — every subtest cites a level pair and asserts IR shape;
TODO = current gap.
**Why KEEP:** Depends entirely on `PrecedenceSpecHelpers::parse_expr`
which (helper-module section, below) needs migration. The 689-line
test file itself is parser/IR-shape testing, not codegen.
**Migration action:** None for the test file itself; rides on the
helper-module migration.

#### `t/bootstrap/struct-promotion/perl-lowering.t`
**Intent:** Unit tests for Target::Perl lowering of StructRef and
FieldAccess IR nodes — verifies StructRef emits as hash constructor,
FieldAccess emits as hash key access.
**Why KEEP:** Uses Target::Perl directly via `$target->emit_expr(
$node)` — emit_expr is *not* on the Phase 6 deletion list. The test
doesn't go through any cfg_state machinery, doesn't use Program,
doesn't use Info structs.
**Migration action:** None.

### MIGRATE

These tests have real behavioral assertions about the *output* of
the Perl codegen (assertions on generated source: "contains `if (`",
"has `class Foo`", "evals cleanly", etc.). They are the byte-compat
equivalents at a per-file granularity. The intent survives in the
new architecture.

After Phase 5a (`_generate_from_schedule` ships at byte-compat
parity), these tests can be re-pointed at `generate($mop)` and
should continue to pass.

#### `t/bootstrap/perl-target-perl-tier-a.t`
**Intent:** Verifies parsing and round-trip codegen for 4 Tier-A
Perl files (Start.pm, Return.pm, Target.pm, Pass.pm), then evals
the generated source and checks behavioral equivalence — e.g.
"the generated Start class's operation() method returns 'Start'".
**Why MIGRATE:** This is a real codegen test (parse → emit Perl
→ eval → behavioral assertions). The intent is exactly what the
new scheduler path must produce. The test calls
`_generate_with_cfg($ir, $sa, $sem_ctx)` directly today.
**Migration action:** Replace `parse_and_generate()` (which
calls `_generate_with_cfg`) with: get `$mop = current_mop()`
after parse, call `$perl_target->generate($mop)`, pick the value
for `'main.pm'` (or whatever the new `generate($mop)`
HashRef[Str] key is for each file).
**Phase 5a requirement:** Scheduler must produce byte-compat
goldens for the four Tier-A files. If `_generate_from_schedule`
diverges in trivial ways (variable order, etc.) that breaks the
`like($code, qr/...)` patterns, those patterns may need
loosening. The eval-and-behavioral checks are the durable
contract; they survive any byte-divergence.

#### `t/bootstrap/perl-target-perl-tier-b.t`
**Intent:** Same as Tier-A, but for Tier-B files (richer classes
with fields, string interpolation). The test asserts on shapes
like "has field $const_type", "evals cleanly".
**Why MIGRATE:** Same as Tier-A.
**Migration action:** Same as Tier-A — switch from
`$perl_target->generate($ir)` (Program input via parser→IR) to
`$perl_target->generate($mop)`.
**Phase 5a requirement:** Same as Tier-A.

#### `t/bootstrap/perl-target-perl-tier-c.t`
**Intent:** Round-trip codegen for Context.pm. Asserts methods
extract/extend/duplicate/leaves/scanned_text are emitted, then
evals and checks behavioral equivalence.
**Why MIGRATE:** Same as Tier-A. Uses TestPerlHelpers's
`parse_and_generate()` which calls `_generate_with_cfg`.
**Migration action:** TestPerlHelpers needs migration first (see
helper-modules section). Once TestPerlHelpers's
`parse_and_generate()` switches to `generate($mop)`, this test
follows without per-file changes.
**Phase 5a requirement:** Same as Tier-A.

#### `t/bootstrap/perl-target-perl-tier-d.t`
**Intent:** Dynamic scan of all `.pm` under `lib/`, parse and
codegen each, then eval. Known-broken files are marked TODO; the
rest must parse-and-eval cleanly.
**Why MIGRATE:** This is the broadest codegen regression test in
the suite. The intent survives entirely in the new architecture.
**Migration action:** Migrates via TestPerlHelpers (no direct
changes in this file).
**Phase 5a requirement:** All non-TODO files in the corpus must
emit byte-compat goldens through the scheduler path. The known-
broken TODO files stay TODO unless Phase 5a happens to fix them.

#### `t/bootstrap/perl-actions-fixup.t`
**Intent:** Verifies Perl::Actions IR shape for statement-level
constructs (return/die, UseDecl import args, expression IR
structure across hash seeds). Walks the IR, checks structural
properties.
**Why MIGRATE:** The intent is "parser produces correct IR
shape". After Phase 6 the parser still produces IR (just MOP-
embedded, not Program-embedded). The assertion patterns
("UseInfo with args=[...]", "MethodInfo body has Return at
position N") translate to assertions over `$mop->classes->{X}
->methods` and `$mop->imports`.
**Migration action:** Replace `parse_source()` returning `$ir`
(a Program) with `parse_source()` returning `$mop`. Replace
helpers `get_all_stmts`, `find_class_in_stmts`, etc. with MOP
accessors. The `$stmt isa Chalk::IR::ClassInfo` checks become
`$cls isa Chalk::MOP::Class`.
**Phase 5a requirement:** None directly — this is parser-shape
testing, not codegen. But the test file's prevalence of
`MethodInfo`/`ClassInfo`/`UseInfo` type-checks means Phase 6's
Info-class deletion is the actual gating event. Could be done
independently of Phase 5a.

#### `t/bootstrap/perl-actions-tier-a.t`
**Intent:** Parses 4 pure-data class `.pm` files and validates
IR structure (which classes are present, where MethodInfo nodes
land, parent-class wiring).
**Why MIGRATE:** Same as `perl-actions-fixup.t` — parser-shape
testing that translates to MOP-shape testing.
**Migration action:** Same as `perl-actions-fixup.t`.
**Phase 5a requirement:** None directly; Phase 6 is the gating
event.

#### `t/bootstrap/perl-actions-tier-b.t`
**Intent:** Same as Tier-A but for 5 files with fields and string
interpolation. Asserts on field presence, `:param`/`:reader`
attribute capture, body item counts.
**Why MIGRATE:** Same as Tier-A.
**Migration action:** Same as Tier-A.
**Phase 5a requirement:** None directly.

#### `t/bootstrap/perl-actions-tier-c.t`
**Intent:** Same as Tier-A/B but for 5 files with runtime method
logic. Asserts on method body composition (Return + helpers).
**Why MIGRATE:** Same as Tier-A.
**Migration action:** Same as Tier-A.
**Phase 5a requirement:** None directly.

### REWRITE

These tests assert on *legacy-path internals* — the cfg_state
hashref shape, `_cfg_lookup` keys, the `emit_from_cfg_state`
dispatcher, the `emit_cfg_*` helper methods, or hand-built
`Chalk::IR::Program` IR for XS/struct-promotion testing. The intent
(e.g. "if/else emits if/else with correctly-extracted body
statements", or "the struct-promotion optimizer rewrites IR
shapes correctly") survives, but the implementation needs to be
re-expressed against new primitives.

#### `t/bootstrap/cfg-statements.t`
**Intent:** A 1444-line omnibus test file with 25+ subtests covering
cfg_state shape (`statements`, `if_node`, `true_proj`, `false_proj`,
`then_stmts`, `else_stmts`, loop fields, postfix-if condition wiring,
loop_jump shortcuts, unless-negation, deep elsif chains, `next
unless`, `last if`, bare `next` keyword vs string literal, shared-
subscript postfix-if). About 20 of the 25 subtests are direct
invocations of `_generate_with_cfg` followed by `like($code, qr/.../)`
assertions on the *Perl source string*.
**Why REWRITE:** The Perl-source-pattern assertions are codegen
behavior the new path must reproduce — those are MIGRATE-flavored.
BUT a substantial fraction (Tests 1, 2, 3, 4, 5-first-half, 20-23,
others) assert on `cfg_state` shape directly (`$state->{then_stmts}`,
`$state->{loop}`, `$state->{loop_jump}` is 'next'/'last') — those are
legacy internals. The test mixes the two regimes inside one file with
the same setup boilerplate.
**New shape:** Split into two files:

1. `cfg-statements-codegen.t` — keeps the `like($code, qr/.../)`
   assertions over generated Perl source. Migrates to
   `generate($mop)` exactly like the MIGRATE entries above.
2. `cfg-statements-schedule.t` — replaces the cfg_state-shape
   assertions with ScheduleMeta-shape assertions. E.g. instead of
   "`$state->{loop_jump}` is 'next'", assert "the If node's
   `schedule_data isa EagerPinning::If` AND `$sd->is_loop_jump`
   returns 'next'". Pattern is already established in
   `scheduler/schedule-data-if-else.t`.

   The 4 sentinel subtests at the top (Tests 1-4, hand-built Context
   contexts with annotations) test the Context+annotations
   *mechanism* directly. They become Schedule::Item shape tests once
   the cfg_state-to-Schedule lift is in place. The hand-built
   contexts can be retired; ScheduleMeta unit tests at
   `t/bootstrap/scheduler/schedule-meta-eagerpinning-*.t` already
   cover the ScheduleMeta data-shape work.

This is the biggest single rewrite in the corpus.

#### `t/bootstrap/cfg-try-catch.t`
**Intent:** Verifies cfg_state carries try_node/catch_var/try_stmts/
catch_stmts; `emit_from_cfg_state` dispatches try/catch; full pipeline
parse-to-emit produces `try { ... } catch ($e) { ... }` source.
**Why REWRITE:** Tests 1, 2, 3 assert directly on cfg_state shape and
on `emit_from_cfg_state`/`emit_cfg_try_catch` methods — both deleted
in Phase 6. Test 4 (full pipeline) is MIGRATE-flavored.
**New shape:** Split.

1. The full-pipeline subtest (Test 4) migrates to `generate($mop)`
   and asserts on the emitted source string (`try {`, `catch ($e) {`).
2. The cfg_state-shape tests get replaced by a check on the IR
   TryCatch node's `schedule_data isa EagerPinning::TryCatch` with
   the expected catch_var, try_stmts, catch_stmts — pattern already
   established in `scheduler/schedule-data-try-catch.t`.
3. The `emit_cfg_try_catch` and `emit_from_cfg_state` method-
   invocation tests **delete entirely**: those methods don't exist
   post-Phase-6.

#### `t/bootstrap/perl-target-cfg-dispatch.t`
**Intent:** Verifies `emit_from_cfg_state` dispatches correctly to
`emit_cfg_if`, `emit_cfg_loop`, `emit_cfg_try_catch` based on
cfg_state shape; also tests that `emit_from_cfg_state` returns undef
for plain (no-CFG) state.
**Why REWRITE:** Tests the legacy `emit_from_cfg_state` dispatcher
directly. That method is deleted in Phase 6. The underlying intent
("when codegen sees an If node it emits an if-block; when codegen
sees a Loop it emits while; etc.") is exactly what
`_emit_from_schedule` is supposed to do.
**New shape:** Replace each subtest with: build a Schedule directly
(using the hand-built Schedule fixture pattern from
`t/bootstrap/scheduler/schedule-shape.t`), feed it to
`_emit_from_schedule($schedule)`, assert on the resulting source.
This becomes a true scheduler-codegen unit test, independent of
parsing.

#### `t/bootstrap/perl-target-cfg.t`
**Intent:** Tests `emit_cfg_if`, `emit_cfg_phi_if`, `emit_cfg_loop`
directly on hand-built IR subgraphs — fine-grained code-emission
unit tests.
**Why REWRITE:** Same as `perl-target-cfg-dispatch.t` — the methods
under test are deleted. The intent (emit-if produces `if (` and
`} else {`; emit-loop produces `while (`; emit-phi-if produces `my $`
+ branch-conditional assignment) is exactly the per-node emission
the new schedule walker performs.
**New shape:** Replace direct `emit_cfg_if($if_node, ...)` calls
with one of:
1. (preferred) Per-Schedule::Item emission unit tests — build a
   single-item Schedule with block_open(if)/...stmt.../block_close,
   call `_emit_from_schedule` (or whatever the per-item dispatch is
   named), assert on source.
2. (acceptable) Direct calls to the new equivalent helper if Phase
   5a exposes one (e.g. `_emit_if_block($schedule_item, $body)`).

Either way the *number of assertions* and the patterns being matched
are unchanged.

#### `t/bootstrap/c-emit-helpers-inheritance.t`
**Intent:** Asserts that Target::C inherits from EmitHelpers and
that ~30 named helper methods (`_escape_c_string`, `_class_slug`,
`_build_cfg_lookup`, `emit_cfg_if`, `emit_cfg_loop`,
`emit_cfg_try_catch`, `emit_from_cfg_state`, etc.) are callable on
a Target::C instance.
**Why REWRITE:** ~6 of the 30 method-existence checks point at
methods deleted in Phase 6 (`_build_cfg_lookup`, `emit_cfg_if`,
`emit_cfg_phi_if`, `emit_cfg_loop`, `emit_cfg_try_catch`,
`emit_from_cfg_state`). The remaining ~24 are still relevant. The
behavioral tests (`_escape_c_string`, `_class_slug`, `_wrap_retval`,
`_needs_eval_fallback`) survive entirely.
**New shape:** Drop the 6 method-existence checks for deleted
methods. If the new schedule-walking emit code has new helper
methods worth gating on, add `ok($target->can('_emit_schedule'))`
or similar. The inheritance assertion and the behavioral tests stay.

#### `t/bootstrap/postfix-loop-phi.t`
**Intent:** Verifies that `EXPR for LIST` and `EXPR while COND`
(postfix forms) create Phi nodes for loop-carried variables, by
inspecting the post-parse scope.
**Why REWRITE:** Uses `$sem_ctx->cfg_state()->{scope}` as the read
path; after Phase 6 cfg_state is deleted.
**New shape:** Walk the MOP method's graph for Phi nodes by name;
the assertion "`$x_binding isa Chalk::IR::Node::Phi`" is unchanged.
This is mostly a mechanical rename: `cfg_state()->{scope}->lookup`
becomes `_collect_phis_by_name($graph)->{'$x'}`. Existing pattern
in `t/bootstrap/mop/build-graph-loop-phi.t` (per ls listing
above) shows the model.

#### `t/bootstrap/scope-threading.t`
**Intent:** Verifies VarDecl populates scope via parse-time
cfg_state propagation — that after `my $x = 42;` the post-parse
scope has `$x` bound.
**Why REWRITE:** Uses `$sem_ctx->cfg_state()->{scope}` as the read
path; after Phase 6 cfg_state is deleted. The "scope is populated
correctly" intent survives.
**New shape:** Pull `$mop = current_mop()` after parse; the test's
real subject is the *Program-level* scope after a top-level
`my $x = 42;`. Post-MOP this is `$mop->for_class('main')` and
inspecting its lexical bindings, or walking a synthesized top-level
"main script" method's `$graph->nodes` for VarDecls. The
`Chalk::Bootstrap::Scope` mechanism is unchanged; only the
*entry point* to read it differs.

#### `t/bootstrap/scope-if-merge.t`
**Intent:** Verifies that if/else with branch assignments to `$x`
produces a Phi node in the post-if scope, and that no Phi is
created when `$x` is unchanged in both branches.
**Why REWRITE:** Same as `scope-threading.t` — uses cfg_state to
read the post-parse scope. Replace with graph-walk for Phi nodes.
**New shape:** Same as `scope-threading.t`. Replace
`$state->{scope}->lookup('$x')` with a graph-walk that finds the
Phi or non-Phi binding for `$x` at the post-if program point. The
"is/isn't a Phi" assertion is unchanged.

#### `t/bootstrap/phi-integration.t`
**Intent:** Integration tests for lazy Phi mechanism on real and
synthetic multi-statement programs — accumulator/string-concat
loops, backedge wiring, nested loops, trailing-statement
limitation (TODO).
**Why REWRITE:** Uses `$sem_ctx->cfg_state()->{scope}->lookup(...)`
in 5 of 6 subtests to read the post-parse Phi binding for variables.
Same cfg_state-as-scope-read pattern as `scope-threading.t`,
`scope-if-merge.t`, `postfix-loop-phi.t`.
**New shape:** Same as the other three: graph-walk for Phi nodes.
The accumulator-loop / backedge-wired assertions are unchanged.

#### `t/bootstrap/semantic-action-scope.t`
**Intent:** Tests cfg_state threading in SemanticAction — that
`one()` has Start-control scope, that `multiply` propagates scope
through complete-annotated Contexts, that `set_cfg_state` allows
actions to update control/scope, that `reset_cache` creates a fresh
singleton.
**Why REWRITE:** Tests `$sa->set_cfg_state(...)` method (line 99)
directly. That method is deleted in Phase 6 along with cfg_state.
The "actions update scope" intent survives via the existing
`update_scope`/`update_annotations` mechanism (covered by
`context-cfg-annotation.t`).
**New shape:** Replace `$sa->set_cfg_state($ctx, {control => ...,
scope => ...})` with the direct-Context-construction idiom (build
a new Context with the desired scope). Most of the test's intent is
already covered by `context-cfg-annotation.t` (which IS a KEEP) —
this test largely duplicates that coverage with a different read
API. Could collapse into `context-cfg-annotation.t` entirely.

#### `t/bootstrap/perl-target-sub-decl.t`
**Intent:** Unit tests for SubDecl emission — package/my/our/state
sub scopes, params, body. Builds a Chalk::IR::Program with a
SubInfo as top_level_sub, calls `$target->generate($program)`,
asserts on emitted source.
**Why REWRITE:** Builds a hand-constructed Program (deleted in
Phase 6) and feeds it to legacy `generate($ir)` (also deleted).
The intent — "a `my sub`/`our sub`/`state sub`/package sub emits
correctly" — survives as: feed a hand-constructed Schedule with
a SubInfo-equivalent item (or, post-Phase-6, a MOP::Sub) and
verify the emitted source.
**New shape:** Hand-construct a MOP::Sub directly (no Program
needed). Call `$target->generate($mop)` where `$mop` contains the
sub. Assert on the per-file HashRef[Str] value. Pattern is
identical to `mop/codegen-hand-constructed-mop.t` but adds the
sub-scope variants (package/my/our/state).

#### `t/bootstrap/struct-promotion/end-to-end.t`
**Intent:** End-to-end struct-promotion: hand-builds a
Program+ClassInfo+MethodInfo, runs `StructPromotion->run`, generates
C, verifies typedefs and IR rewrites.
**Why REWRITE:** Builds Program/ClassInfo/MethodInfo hand-constructed
trees as input to the optimizer. After Phase 6, the optimizer's
input must be a MOP instead. The struct-promotion optimizer's
*function* survives entirely; only the construction shape changes.
**New shape:** Replace `program_ir($class_info)` helper with
`hand_constructed_mop($class)` that builds a MOP::Class with
MOP::Method instances. The schema-analysis and IR-rewrite assertions
are unchanged. The Target::C calls (`set_struct_schemas`,
`generate_typedefs`) are unchanged.

#### `t/bootstrap/struct-promotion/ir-rewriter.t`
**Intent:** Unit tests for the struct-promotion IR rewriter (Pass 2):
HashRefExpr → StructRef, SubscriptExpr → FieldAccess rewrites.
**Why REWRITE:** Same as `struct-promotion/end-to-end.t` — hand-
builds a Program+ClassInfo+MethodInfo as input.
**New shape:** Same as `struct-promotion/end-to-end.t`. Replace
the hand-built Program tree with a hand-built MOP. Test the
rewriter against the new input shape. The rewrite assertions
(StructRef shape, FieldAccess shape) are unchanged.

#### `t/bootstrap/struct-promotion/pipeline-integration.t`
**Intent:** Tests the `StructPromotion->run` entry point and
schema reporting.
**Why REWRITE:** Same as the other struct-promotion tests — hand-
built Program input.
**New shape:** Same as the others.

#### `t/bootstrap/struct-promotion/schema-analyzer.t`
**Intent:** Tests the struct-promotion schema analyzer (Pass 1) —
hash schema detection, key accumulation, escape analysis, C-type
inference.
**Why REWRITE:** Same as the other struct-promotion tests — hand-
built Program input.
**New shape:** Same as the others.

#### `t/bootstrap/xs-athx-no-args.t`
**Intent:** Verifies XS wrapper emits correct `aTHX` calls for
void-param functions; validates `init_statics` filter when class
slug differs from module slug.
**Why REWRITE:** Builds a hand-constructed Program+ClassInfo+
MethodInfo and feeds it to `$target->_generate_c_files($program,
undef, undef)`. The Program type goes away; `_generate_c_files`
signature changes in Phase 7 (XS migration).
**New shape:** Replace hand-built Program with hand-built MOP.
Update `_generate_c_files` call to whatever Phase 7 settles on for
the new signature. The aTHX/init_statics assertions are unchanged.

#### `t/bootstrap/xs-int-specialization.t`
**Intent:** Verifies type-directed operator specialization — Int+Int
arithmetic emits `SvIV`/`newSViv` rather than `SvNV`/`newSVnv`.
**Why REWRITE:** Same shape as `xs-athx-no-args.t` — hand-built
Program+ClassInfo+MethodInfo input.
**New shape:** Same as `xs-athx-no-args.t`. Migrate alongside Phase
7. The specialization assertions are unchanged.

#### `t/bootstrap/xs-isa-inheritance.t`
**Intent:** Verifies XS BOOT block correctly emits `:isa`
inheritance registration; runtime test that compiled subclass
inherits from parent.
**Why REWRITE:** Same shape — hand-built Program with parent class.
**New shape:** Same as `xs-athx-no-args.t`. Migrate alongside Phase 7.

#### `t/bootstrap/xs-polymorphic-dispatch.t`
**Intent:** Unit tests for the polymorphic dispatch map in
Target::C — verifies that `compiled_class_metadata` is used to
build `$_polymorphic_dispatch`.
**Why REWRITE:** Same shape — hand-built Program input.
**New shape:** Same as `xs-athx-no-args.t`. Migrate alongside Phase 7.

### DELETE

These tests guard subject classes or method paths that are
explicitly slated for deletion in Phase 6.

#### `t/bootstrap/ir-program.t`
**Intent:** Unit tests for `Chalk::IR::Program` — construction with
defaults, member accessors, id() content-hash, add_consumer no-op.
**Why DELETE:** `Chalk::IR::Program` is explicitly listed for
deletion in Phase 6 (Section 7 Phase 6, item 6). The type's
construction/accessor/id-method semantics are not covered elsewhere
because the type no longer exists.
**Coverage check:** No replacement is required — the type's only
purpose was to serve as the legacy `generate($ir)` argument. The
MOP replaces it via `$mop->classes()` / `$mop->for_class('main')->
imports()` etc. Coverage that those MOP accessors work correctly
already lives in `t/bootstrap/mop/parse-integration.t` and
`mop/build-graph-*.t`.

#### `t/bootstrap/ir-program-pipeline.t`
**Intent:** Verifies that Actions.pm produces `Chalk::IR::Program`
(not a Constructor:Program node) at top level when parsing UseInfo.pm,
Serialize/JSON.pm, Constant.pm.
**Why DELETE:** The assertion `isa_ok($ir, 'Chalk::IR::Program')`
is structurally impossible after Phase 6 — that type doesn't exist.
The test exists specifically to guard against an *earlier* migration
regression ("Actions stopped producing Constructor:Program and started
producing Chalk::IR::Program"). That migration completed years ago
in repo time; the test is regression-guarding a state that the next
migration removes entirely.
**Coverage check:** `t/bootstrap/mop/parse-integration.t` covers
that parse produces a MOP, which is the post-Phase-6 equivalent
goal. The intent "parser produces a structured top-level result"
is covered there.

#### `t/bootstrap/ir-class-info-pipeline.t`
**Intent:** Verifies that Actions.pm produces `Chalk::IR::ClassInfo`
for class declarations (not a Constructor:ClassDecl), with correct
name/body/fields/methods/parent.
**Why DELETE:** Same as `ir-program-pipeline.t`. `Chalk::IR::
ClassInfo` is explicitly deleted in Phase 6.
**Coverage check:** `t/bootstrap/mop/parse-integration.t` covers
"parser produces a MOP with classes" and per-class introspection
of fields/methods/parent via MOP accessors.

#### `t/bootstrap/ir-method-info-pipeline.t`
**Intent:** Verifies that Actions.pm produces `Chalk::IR::MethodInfo`
for method declarations, with correct name/params/body/return_type
and that each MethodInfo carries a Graph.
**Why DELETE:** Same as above. The "MethodInfo carries Graph"
assertion is the load-bearing thing; that survives as "MOP::Method
carries Graph" in `t/bootstrap/mop/method-implicit-return.t` and
`mop/method-lexical-bindings.t` (KEEP entries above) and
`mop/build-graph-*.t`.
**Coverage check:** Covered by the `mop/` test directory.

#### `t/bootstrap/ir-sub-info-pipeline.t`
**Intent:** Verifies that Actions.pm produces `Chalk::IR::SubInfo`
for package subs, with correct name/params/scope/body.
**Why DELETE:** Same as above. `Chalk::IR::SubInfo` is explicitly
deleted in Phase 6.
**Coverage check:** Sub coverage in the MOP path is via
`t/bootstrap/mop/parse-toplevel-sub.t` and `MOP::Sub` accessors.

#### `t/bootstrap/ir-field-info-pipeline.t`
**Intent:** Verifies that Actions.pm produces `Chalk::IR::FieldInfo`
for field declarations, with correct name/attributes/default_value.
**Why DELETE:** Same as above. `Chalk::IR::FieldInfo` is explicitly
deleted in Phase 6.
**Coverage check:** Field coverage via `MOP::Field` accessors,
exercised throughout `mop/build-graph-*.t`.

#### `t/bootstrap/ir-metadata.t`
**Intent:** Unit tests for all five IR metadata structs (Program,
ClassInfo, MethodInfo, SubInfo, FieldInfo) — construction with
defaults and members, id() content-hash, add_consumer no-op, body
storage.
**Why DELETE:** All five types are deleted in Phase 6. The whole
test goes away with them.
**Coverage check:** No replacement needed; the types don't exist.

#### `t/bootstrap/perl-ir-tier-a.t`
**Intent:** Unit tests for Perl IR Tier-A typed constructors and
CFG nodes — validates Program, UseInfo, ClassInfo, MethodInfo,
Return CFG, Unwind CFG creation. Largely overlaps with
`ir-metadata.t` + `ir-cfg-nodes.t` + `ir-return-cfg-node.t`.
**Why DELETE:** Most assertions are about Program/UseInfo/ClassInfo/
MethodInfo construction — all deleted in Phase 6. The Return/Unwind
CFG-node assertions are duplicated in `ir-return-cfg-node.t` (KEEP).
**Coverage check:** Return/Unwind CFG-node coverage lives in
`t/bootstrap/ir-return-cfg-node.t` and `t/bootstrap/ir-cfg-nodes.t`
(both KEEP). The Info-class construction tests have no MOP
equivalent because Info classes don't exist post-Phase-6.

#### `t/bootstrap/ctrl-thread-prototype.t`
**Intent:** Prototype test for control-flow threading in
`_build_method_graph`. Verifies that body statements (VarDecl,
remove_consumer Call, Assign, add_consumer Call, etc.) are
reachable via `graph->nodes()` after threading.
**Why DELETE:** The file's own ABOUTME says "Prototype test"; the
implementation it guards (`_build_method_graph` threading via
inputs[0] CFG predecessors) shipped as Phase 3d. The prototype's
intent is now covered by `t/bootstrap/mop/ir-completeness.t` (KEEP
entry above) — that file asserts every body item is in the graph
AND reachable from a terminator across the 56-snippet audit
corpus.
**Coverage check:** `t/bootstrap/mop/ir-completeness.t` provides
strictly more comprehensive coverage than this prototype.

#### `t/bootstrap/ir-use-info.t` (provisional — see Q1)
**Intent:** Unit tests for `Chalk::IR::UseInfo` (construction, id
content-addressing, add_consumer no-op).
**Why DELETE:** `Chalk::IR::UseInfo` is explicitly deleted in
Phase 6. Listed twice in this report (KEEP + DELETE) because the
*semantics* it guards (use-decl IR captures name and args) survive
in MOP::Import while the *type* doesn't. Resolution depends on the
Q1 answer.
**Coverage check:** MOP::Import accessors are covered by
`t/bootstrap/mop/parse-integration.t`.

### Helper modules (`t/bootstrap/lib/`)

Three helper modules are load-bearing for the migration. They are
not "tests" in the per-outcome sense but must be migrated for many
of the MIGRATE outcomes above to land.

#### `t/bootstrap/lib/TestPerlHelpers.pm`
**Used by:** `perl-target-perl-tier-c.t`,
`perl-target-perl-tier-d.t` (and possibly more indirectly).
**Migration required:** `parse_and_generate()` currently calls
`_generate_with_cfg($ir, $sa, $sem_ctx)`. Replace with: get the
MOP via `Chalk::Bootstrap::Semiring::SemanticAction::current_mop()`,
call `$perl_target->generate($mop)`, return the appropriate
HashRef[Str] value (likely keyed by the source file's package
path). This helper sits in the critical path of the bulk Tier-D
sweep, so its migration is high-leverage.

#### `t/bootstrap/lib/TestXSHelpers.pm`
**Used by:** Many XS-target tests, none of which are in the
scheduler-migration scope today (XS migration is Phase 7, separate
plan). But TestXSHelpers's `parse_file_ir()` snapshots cfg_state at
parse time (lines 70–83) and feeds it to `$target->_build_cfg_lookup
($sa, $sem_ctx)` in `build_and_load()` (line 103). Both of those
mechanisms disappear in Phase 6.
**Migration required:** Replace cfg_snapshot mechanism with MOP
threading. `build_and_load()` should accept the MOP, not (ir, sa,
ctx). Coordinate with Phase 7 (XS migration) plan — this helper is
the entire surface that connects the XS test set to the legacy
parser shape, and its migration is a prerequisite for the XS test
set joining the new architecture.

#### `t/bootstrap/lib/PrecedenceSpecHelpers.pm`
**Used by:** `t/bootstrap/precedence-spec.t` and any other test
deriving from it.
**Migration required:** `parse_expr()` extracts the parse result and
returns `$vardecl->inputs()->[1]` (the initializer of a synthesized
`my $_ = EXPR;`). That access chain depends on the result being a
`Chalk::IR::Program` with `->other_stmts()`. After Phase 6, the
equivalent path is `$mop->for_class('main')->subs->[0]->graph` or
similar — needs a MOP-aware rewrite. The `parse_expr` API surface
stays the same.

## Cross-cutting notes

### Three different cfg_state-call patterns require different remediation

The legacy-touching tests fall into three sub-patterns:

1. **cfg_state as graph-root finder.** Tests use `$sem_ctx->cfg_state()
   ->{control}` or `{if_node}` or `{loop}` to find a single IR node,
   then walk the graph from there. The cfg_state call is incidental;
   the assertions are graph-shape assertions. Fix: replace cfg_state
   call with `current_mop` + graph traversal. (Affects ~6 KEEP
   entries above plus the 5 `scheduler/schedule-data-*.t` tests.)

2. **cfg_state as scope-read interface.** Tests use `$sem_ctx->
   cfg_state()->{scope}->lookup('$x')` to read the post-parse scope.
   The Scope mechanism survives entirely; only the entry point
   changes. Fix: read from MOP. (Affects `scope-threading.t`,
   `scope-if-merge.t`, `postfix-loop-phi.t`, `phi-integration.t` —
   all REWRITE entries.)

3. **cfg_state as shape-under-test.** Tests assert on the cfg_state
   hashref's specific shape — that it has `then_stmts`,
   `else_stmts`, `loop_jump`, etc. These are real legacy-internal
   tests; their intent (the underlying classification of "this if
   has a then-body of N statements, an else-body of M statements,
   and is/isn't a loop_jump") survives in ScheduleMeta, but the
   entire test mechanic must change. (Affects `cfg-statements.t`
   and `cfg-try-catch.t`.)

### Bootstrap-grammar generate() and legacy Perl-target generate() are different

A large number of test files (~25) call `$target->generate($raw_ir)`
where `$target = Chalk::Bootstrap::BNF::Target::Perl->new()`. This is
**not** the legacy codegen path under migration — it's the BNF
parser bootstrap (emits a grammar module). The legacy codegen path
under migration is `Chalk::Bootstrap::Perl::Target::Perl`. The two
shouldn't be confused. Filtering on `->generate(` alone surfaced
many false positives.

### Several tests assert the existence/absence of specific Target::C or Target::Perl methods.

`c-emit-helpers-inheritance.t` and `mop/codegen-no-backchannel.t`
make `ok($target->can(METHOD))` assertions about the public API.
After Phase 6 deletion, several of those `can` checks need to flip
sign (the previously-required method should no longer exist). This
is mechanical but easy to miss in a grep-and-replace pass.

### The Info-class deletion is a higher-leverage trigger than the cfg_state deletion.

Within the DELETE pool, every entry is justified by Info-class
deletion (not by cfg_state deletion). Within the REWRITE pool, four
of the 16 entries are justified by emit_cfg_* method deletion; the
other 12 by cfg_state deletion or hand-constructed-Program input.
Within the KEEP pool, most "migration action" lines are about
cfg_state-read decoupling. Sequencing-wise, the Info-class deletion
in Phase 6 is the bigger cleanup; the cfg_state-deletion footprint
is wider but shallower.

### Tier-A/B/C/D Perl tests are co-vert tests of the byte-compat gate.

`perl-target-perl-tier-{a,b,c,d}.t` together exercise ~30 of the 31
lib/ .pm files end-to-end through codegen. If `_generate_from_
schedule` matches byte-compat against the 19 mop/codegen-byte-compat.t
goldens **but** diverges on any of these 30 files in ways the test
regex doesn't tolerate, that's a real bug in Phase 5a — not a test
issue. The Tier-D file in particular is the broadest single
regression net.

### scheduler/schedule-data-*.t are EagerPinning gestation tests, not migration targets.

Five tests at `t/bootstrap/scheduler/schedule-data-*.t` already
exercise the new EagerPinning::* ScheduleMeta classes. They use
cfg_state only as an IR-node-finder (pattern 1 above). They're
classified KEEP and become reference tests against which Phase 5a
work can be checked.

### XS tests (4 files) cluster as REWRITE'd together, deferred to Phase 7.

`xs-athx-no-args.t`, `xs-int-specialization.t`, `xs-isa-inheritance.t`,
`xs-polymorphic-dispatch.t` all hand-build a Program with ClassInfo
and feed it to Target::C's `_generate_c_files`. None of them are
inside the scheduler-migration scope. They REWRITE as a batch when
Phase 7 (XS migration) settles its design and the
`_generate_c_files` signature changes. Phase 5b can skip these unless
the user explicitly wants them swept along.

### struct-promotion tests (4 files + 1 KEEP) cluster as REWRITE'd together.

`struct-promotion/end-to-end.t`, `struct-promotion/ir-rewriter.t`,
`struct-promotion/pipeline-integration.t`,
`struct-promotion/schema-analyzer.t` all hand-build a Program tree
as input to the StructPromotion optimizer. They REWRITE as a batch
when the optimizer's input type switches from Program to MOP. The
fifth struct-promotion test, `struct-promotion/perl-lowering.t`,
doesn't use Program — it goes through `Target::Perl::emit_expr`
directly — and is KEEP.

## Open questions for the design

### Q1: How should the `ir-use-info.t` ambiguity be resolved?

`Chalk::IR::UseInfo` is explicitly slated for deletion in Phase 6,
which strictly classifies this test as DELETE. But the underlying
intent ("use-decl IR captures the import line's name and args") is
preserved by `Chalk::MOP::Import`. Should `ir-use-info.t` be:

- (a) DELETEd entirely, with no replacement (the MOP::Import API is
  covered indirectly by `mop/parse-integration.t`); or
- (b) REWRITten to be a `mop-import.t` covering the new type with
  the same level of unit granularity?

Inclination is (a); UseInfo's only consumer was the legacy
`_generate_from_mop` path's synthesis layer, which goes away. The
file is listed under both KEEP (provisional, semantics survive) and
DELETE (provisional, type doesn't survive) headings in this report —
exactly one of those outcomes should remain after the question is
resolved.

### Q2: How does the scheduler design handle `unless` source-form preservation?

`cfg-statements.t` Tests 14, 18 assert that `unless ($x)` emits as
`unless (` (not as `if (!`). The scheduler design's Decision B
explicitly addresses *until* normalization ("until normalizes to
while !cond"), but does not say whether `unless` is normalized to
`if !` or preserved. The existing legacy path preserves `unless`.
Phase 5a needs to either preserve `unless` (and pass the existing
golden) or change the goldens deliberately. Without an explicit
decision, this is a risk.

### Q3: Where do the bare-`next` / bare-`last` keyword vs string-literal tests (cfg-statements.t Tests 22, 24) belong?

The assertion is that inside a loop body, a bare `next;` statement
emits as the literal Perl keyword `next` (rather than as a string
constant `'next'`). This is a parser/IR concern (the `next` should
become a NextStatement IR node, not a Constant string node), not a
codegen concern. But it's currently inside `cfg-statements.t`
because the full-pipeline parse-and-emit is the only way to exercise
it. In the REWRITE split, where does it land?

- If the parser produces a NextStatement node, the codegen-path
  test is "emit a NextStatement → emit `next`" — a per-node emit
  test, lives with the per-Schedule::Item emission tests
  (REWRITE'd from `perl-target-cfg.t`).
- If the parser produces a Constant `'next'`, that's a parser bug;
  the test belongs in `perl-actions-fixup.t` and is checked
  pre-codegen.

Which is the current state? Reading the test isn't sufficient —
it only asserts on the emitted output, not on the IR shape. Need
a Phase 5a probe to clarify.

### Q4: Phi-slot naming convention

Several tests (`cfg-loop-phi.t`, `scope-if-merge.t`,
`postfix-loop-phi.t`, `phi-integration.t`) assert that variables
end up as `Chalk::IR::Node::Phi` instances. The scheduler design's
`EagerPinning::Phi` ScheduleMeta carries `emit_slot` (VarDecl ref)
and `synthetic_name` (fallback string). Section 4 ("Phi → variable
mapping") describes resolution but doesn't pin a *naming convention*
— does the emitted Perl use `$_phi_N` synthetic names, or always
re-resolve to source identifiers? The byte-compat goldens implicitly
encode whichever convention the current codegen uses, and Phase 5a
must match.

### Q5: TestXSHelpers migration sequencing

TestXSHelpers (`t/bootstrap/lib/TestXSHelpers.pm`) snapshots
cfg_state and passes it to `_build_cfg_lookup`. The XS tests it
serves are not in scheduler-migration scope (XS migration is
Phase 7, separate plan). But Phase 6 deletes `_build_cfg_lookup`.
Either:

- Phase 6 must keep `_build_cfg_lookup` on Target::C (the XS
  target) until XS migration completes; or
- The XS tests must migrate to the new MOP-driven path *before*
  Phase 6 ships.

This is a sequencing question that the design doc's Phase 7 entry
doesn't address (Phase 7 says "separate plan").

### Q6: Struct-promotion optimizer input migration timing

Four struct-promotion tests (REWRITE'd above) hand-build Program
trees as optimizer input. The migration to MOP-shaped input is
straightforward, but no current plan document mentions when the
struct-promotion optimizer itself will accept MOP input. Sequencing
question: does the optimizer migrate alongside Phase 6 (so its tests
can migrate too), or is it deferred to its own phase? If deferred,
the four REWRITE tests block in their current shape until that phase
lands.

### Q7: Does `semantic-action-scope.t` duplicate `context-cfg-annotation.t`?

Both files test scope/control propagation through SemanticAction;
both work through Context.annotations. `semantic-action-scope.t`
additionally tests `set_cfg_state` (deleted in Phase 6), but its
other subtests overlap heavily with `context-cfg-annotation.t`. If
the overlap is genuine, `semantic-action-scope.t` could collapse
into `context-cfg-annotation.t` entirely (REWRITE → DELETE) once
set_cfg_state goes away. Needs a head-to-head review by someone
with full context on both tests' history.

## Cross-references

- Scheduler design doc: `docs/plans/2026-05-24-son-scheduler-design.md`
- Exemplar production-path test for MIGRATE shape:
  `t/bootstrap/mop/codegen-byte-compat.t`
- Exemplar scheduler unit tests:
  `t/bootstrap/scheduler/schedule-data-*.t`
- IR completeness reference: `t/bootstrap/mop/ir-completeness.t`
- Helper-module migration prerequisite for Tier-C/D MIGRATE:
  `t/bootstrap/lib/TestPerlHelpers.pm`
- XS sequencing dependency:
  `t/bootstrap/lib/TestXSHelpers.pm`
- Struct-promotion REWRITE batch source:
  `t/bootstrap/struct-promotion/*.t` (4 files + 1 KEEP)
