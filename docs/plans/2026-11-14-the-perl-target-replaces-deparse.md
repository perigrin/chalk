# The Perl target replaces Deparse: a Perl functor in T2's model

**Date:** 2026-11-14
**Status:** PLAN. Not started. No code changed.
**Follows:** `2026-11-13-the-loader-only-loads.md` (its step 1 is this plan's step 1).
**Origin:** perigrin, three statements --

> Chalk's Perl target, updated to the current IR, replaces the producer's
> `SoN::Deparse`. [The C and XS backends are not kept alive.]
>
> The Perl target should follow but not be identical to the LLVM target…
> using the Functor model.
>
> the SoN was *built* from Perl so should already capture/map to the
> semantics fairly closely.

Paths: chalk is `/home/perigrin/dev/chalk` (paths below are relative to it).
The producer (B::SoN) is `/home/user/repo`, written `P:` below.

## 1. What was measured (2026-11-14)

| Fact | Measurement |
|---|---|
| Deparse on the pvm corpus | 431 cases: ROUNDTRIP 427, REFUSED 4 (all four the producer's string-eval GAP), DIFFERS 0, EMITS_INVALID_PERL 0. `perl tools/corpus-roundtrip.pl -v`, 1m48s. Floor in `P:t/roundtrip-ratchet.t:52` is 427. |
| Deparse's other gates | chalk lib/ 179 of 179 COMPILES; chalk's suite 482 SAME; perl t/ 11 (`P:t/roundtrip-ratchet.t:55,85,94`). |
| Deparse's size | 9564 lines, 110 methods, about 125 named GAPs. Control and statements: lines 1440-7315. Expressions: lines 7618-9464. |
| Producer tests on Deparse | 359 of 710 test files `use SoN::Deparse` (276 are `t/deparse-*.t`). 44 assert on the emitted text. 29 assert on a GAP's wording. 1 reads `%SoN::Deparse::MEM_MIN_INPUTS`. Three tools use it: `P:tools/corpus-roundtrip.pl:37`, `chalk-lib-roundtrip.pl:12`, `perl-t-roundtrip.pl:27`. |
| The wire's ops | 94 ops the producer names. Deparse names every one but VarDecl (3 of 427 corpus cases hold one, and they round-trip). |
| The old Perl target on a wire graph | `return 2 * $n` dies `Unknown IR node type: Chalk::IR::Node::PadAccess` (`Perl.pm:781`). The program's own Return (an undef Constant) is emitted as `return '';` with eight "uninitialized" warnings (`Perl.pm:1011-1030`). That is a silent wrong emission. |
| Load without Analysis | `Chalk::IR::Serialize::JSON::_deserialize_graph` (`JSON.pm:534`) builds each wire graph alone. Checked on two programs. |

## 2. Where the Perl target sits

### 2.1 A functor beside T2, not the Schedule-driven target

The new target is `Chalk::Target::Perl`, in `lib/Chalk/Target/Perl.pm`, beside
`lib/Chalk/Target/LLVM/T2.pm`. It has T2's three parts:

| Part | T2 (`lib/Chalk/Target/LLVM/T2.pm`) | Perl functor |
|---|---|---|
| Target graph | `T2::Node`: op, type, inputs, attr (`:25-32`) | `Perl::Node`: the same four fields. `op` is a Perl construct. `type` is a Perl shape. |
| Builder | walks T1 forward from Start by control successors (`build :133`, `successors :186`, `walk :197`); `value` memoised per T1 node (`:3323`) | the same walk and the same memo |
| Printer | "chooses nothing: every type is already on the node" (`:3713`) | the same rule. It only prints text, parentheses and indentation. |
| Refusal | `out('...')` names the cause (`:116`); the program falls back to Context.pm (`:100`) | `out('...')` is a named GAP. During the transition the producer falls back to Deparse. At the end there is no fallback. |
| Slices | each slice only adds programs (`:19-22`) | the same. Section 5 is the slice ladder. |

T1 is never mutated. The Perl graph is built fresh.

### 2.2 The functor: objects and arrows

T2 maps a Perl type to a machine representation, and a subtype edge to a
conversion (`docs/plans/2026-09-04-t2-is-a-functor-objects-and-arrows.md`).
The Perl functor maps into Perl itself, so most of it is the identity.

- **Objects.** A T1 value maps to a Perl expression of one **shape**:
  `Scalar`, `Array`, `Hash`, `List`, `Code`, or `Void` (a statement). No
  solver: a Perl scalar already holds an Int, a Num, a Str or undef.
- **Arrows that are the identity.** `Int <: Num <: Str <: Scalar`. Perl
  converts at the operator. So the functor never asks for a stamp to choose a
  representation. The operator carries the meaning: `NumEq` is `==`, `StrEq`
  is `eq`.
- **Arrows that are not.** The shape arrows. `Array -> Scalar` is
  `scalar(@a)`. `List -> Array` is a binding (`my @t = f()`). `Array -> Scalar`
  by reference is `\@a`. A reference back to an aggregate is `@{...}`. These
  are made in one place, `as($node, $shape)`, as T2's `as` (`T2.pm:3687`) makes
  every conversion. Deparse learned this the hard way: "an array keeps its
  sigil through every merge" (`P:docs/memory/MEMORY.md:122`).

### 2.3 Where it shares T2's structure, and where it must differ

Shared: the forward walk; one memoised `value`; `out` by name; slices; a
printer that decides nothing; one graph (sub) at a time.

Different, and why:

1. **Control.** LLVM's target is a CFG, so T2 emits blocks and phis directly.
   Perl has only structured control. The Perl builder must rebuild `if`,
   `while`, `last`, `next` from If/Proj/Region/Loop. This is T2's easiest part
   and the Perl functor's hardest.
2. **A Phi.** T2 prints a phi. Perl has none. A value Phi becomes one `my`
   variable, assigned at the end of each arm that feeds it. A memory Phi
   becomes nothing.
3. **Memory.** T2 orders reads by memory version (`_is_version :865`,
   `_memory_input :884`) against its own globals. In Perl the memory is
   perl's own variables. A memory edge becomes statement order. A read whose
   value is used after a later store is bound to a temporary where it stands.
4. **No runtime.** T2 carries a prelude of runtime functions (`_prelude
   :3991`) and a container metaobject for tie (`:6636`). Perl has its own
   containers, `tie`, `local`, `die`/`eval`, `sort`, regexes. The Perl functor
   emits **no helper subs**. If one seems needed, the wire lacks a fact: fix
   the producer or refuse.
5. **No MOP lowering.** T2 builds a MOP for vtables (`make_mop :1980`). The
   Perl functor prints the wire's `classes` as `class` blocks.
6. **Calls.** T2 resolves targets, inlines, and uses a copy of a sub per
   caller context. Perl calls by name and passes context itself. Inlining is
   done in the backend, so it never shows in the graph. Context copies show
   only in a graph `from_json` made (`JSON.pm:1381`).

### 2.4 Which graph it consumes

The functor takes **a program**: named graphs plus the wire's `classes`,
`phase_blocks` and `data_section`. It does not care which passes ran.

- **The producer's gate feeds it the loaded graph, with no Analysis.**
  Reasons:
  1. It reads no stamp to choose a representation (2.2), so it needs no
     typing.
  2. `from_json` prunes graphs (`JSON.pm:1321`), refuses a BEGIN with effects
     (`:1310`), and adds `f@scalar` copies (`:1381`). Each is an LLVM concern.
     Each would turn a round-trip into a GAP or a duplicate sub.
  3. Deparse's rule is that it shares nothing with the producer
     (`P:lib/SoN/Deparse.pm:23-30`). The same holds here: an oracle that runs
     Analysis first tests the producer and Analysis together, and cannot say
     which is wrong.
- **Later, chalk can feed it the analysed graph.** Then the same tool checks
  that a pass kept the program's meaning. That is a new gate, in section 5,
  step 17. It needs the context copies named (`f__scalar`).

This needs a load-only entry point. That is step 1 of the loader plan.

### 2.5 Which repo owns what

Today the repos reach each other in two ways only:

- The producer reads chalk **at a pinned commit, from a clone, through `git
  archive`** (`P:tools/corpus-llvm-roundtrip.pl:36,45,54-56`; clone from
  `SON_CHALK`, default `~/dev/chalk`). It drives chalk with a small script of
  its own (`P:tools/chalk-lower.pl`).
- Chalk's tests find the producer's `lib/` through `PERL5_SON_LIB` and skip
  without it (`t/bootstrap/ir/t2-a-file-lexical-is-one-variable.t:8-10`).

The plan keeps both and adds nothing new:

1. **Chalk owns the functor and the tool.** `script/chalk-son-perl`: wire
   JSON in (file or stdin), Perl on stdout, exit 0. On a refusal: one line
   `GAP: <cause>` on stdout, exit 1. On a malformed wire: `LOAD: <why>`,
   exit 2.
2. **The producer owns its tests and gates.** One helper,
   `P:tools/lib/ChalkPerl.pm`: `render($data) -> ($perl, $gap)`. It unpacks
   chalk at the pin once per run (cached by commit under the temp dir) and
   runs the tool. The pin is one constant in that file.
3. **The producer's round-trip tests call the helper** where they call
   `SoN::Deparse->new->render($data)` today. The corpus gate
   (`P:tools/corpus-roundtrip.pl`) calls the same helper.
4. **A producer change that needs a functor change is two commits:** chalk
   first, then the producer with the new pin and the new floor.

## 3. The mapping is mostly direct

The producer builds each node from one perl op. `P:lib/SoN/FromOptree/OpMap.pm`
is that table (`add => 'Add'` at `:61`, `seq => 'StrEq'` at `:150`). The
functor is its inverse. For these ops the functor is a table row and nothing
else:

- **Operators** (38 ops): Add Subtract Multiply Divide Modulo Power Negate
  Repeat Concat; the six Num and six Str comparisons, NumCmp, StrCmp; BitAnd
  BitOr BitXor Complement LeftShift RightShift; Not And Or Xor DefinedOr;
  Range. Deparse's whole table is `P:lib/SoN/Deparse.pm:52-63`.
- **Value forms:** Constant, TernaryExpr, Defined, Length, Exists, Delete,
  Ref, RefType, PostfixDeref, Subscript, Slice, ArrayLiteral, HashLiteral,
  IsaOp, Wantarray, EnvRead, BacktickExpr, Chomp, ChompValue, SubDefined.
- **Names:** PadAccess (`my` variable), EntryDef/EntryWrite (package
  variable), FieldAccess (class field), Parameter, ArgsSource (`@_`).
- **Statements:** Print, Assign, Increment, Return, Unwind (`die`), Call.
- **Regex:** Match, RegexMatch, RegexCapture, RegexSubst, Transliterate.

Deparse is not the spec. It is the record of the cases that are **not** a
table row. Those are the real work. Each is listed here with where Deparse
learned it.

| # | Not direct | Why | Deparse's record |
|---|---|---|---|
| N1 | If/Proj/Region to `if`/`elsif`/`else`, `&&`, `||`, `?:` | SoN has edges, Perl has blocks | `_emit_if :5710`, `_short_circuit_join :4766`, `_join_region :6424` |
| N2 | A value Phi | No Perl spelling; becomes a variable assigned per arm | `_join_phis :6145`, `_phi_var :5078` |
| N3 | Loop, loop Phi, `next`/`last`/`redo` as edges, a break that carries values | `foreach` arrives as an index loop over a Phi (measured: `for my $x (@a)` is `Loop` + `Phi` + `Count` + `Subscript`) | `_emit_loop :4039`, `_emit_endless_loop :5389`, `_break_payment :5645` |
| N4 | A return from inside a loop or an arm | An early exit joins a Region at the sub's end | `_is_fn_exit :5687`, four GAPs "a return from inside a loop whose ..." |
| N5 | An effect read as a value | Emitted inline it runs twice (`shift` twice gave 1 for 42); bound once to a temporary | `:1460-1478` |
| N6 | Memory versions | A read must stand before the next store; aggregates rebound get versions | `_latest_store_read :8724`, `_agg_versioned :4902`, `%MEM_MIN_INPUTS :172` |
| N7 | Where `my` goes | SSA has no scopes | `_declare_undeclared :1213` |
| N8 | Closures: MakeCell, CellRead, CellWrite, CellParam, AnonSub, lifted bodies (sort comparators, `s///e`, regex code) | A shared lexical is a cell; a closure is emitted inside its maker | `_emit_cell_declarations :638`, `_closures_for :728`, `_sort_expr :774` |
| N9 | Block eval and its exits | A Region that names its entry; an Unwind inside it; a return inside it | `_emit_eval :5232`, `_eval_return_edge :5153` |
| N10 | `local`: LocalAlias, ElemRestore | The restore is an edge on every way out | `P:docs/memory/MEMORY.md:190` |
| N11 | Subs and signatures | One graph per sub; parameters rebuilt from Parameter/ArgsSource; a Return with two faces or `valueless` | `_signature_for :901`, `:7241-7246` |
| N12 | Classes, packages, phase blocks, `use`, `__DATA__` | Wire metadata, not nodes; PackageMark regions | `_emit_classes :942`, `_place_package_regions :1096`, `_emit_phase_block :1164` |
| N13 | Coerce and Count | Coerce is the producer's note; it is dropped only where the consuming operator converts anyway. Count is `scalar(@a)`. | `:8111-8125` |
| N14 | Context copies (`f@scalar`) | Only in an analysed graph (2.4) | none: Deparse never saw one |
| N15 | Inlined calls | Never in the graph (2.3, item 6). Nothing to do. Named so nobody looks. | none |

The direct rows are about 1850 lines of Deparse. N1-N12 are about 5900. The
functor will be thinner than Deparse, because the walk, the memo and the
shape conversions are each written once. It will not be thin in N1-N6.

## 4. The old Perl target: what is dead, what is reusable

`lib/Chalk/Bootstrap/Perl/Target/Perl.pm` (1704 lines) was written for the
grammar parser's output (`lib/Chalk/Bootstrap/Perl/Actions.pm`). That is a
different dialect of the IR from the wire:

| Old target reads | The wire has |
|---|---|
| a `Chalk::MOP` or a `Chalk::IR::Program` (`Perl.pm:79-91`) | named graphs |
| control from `schedule_data`, set by the parser (`lib/Chalk/IR/Node.pm:83`, `lib/Chalk/IR/Scheduler/EagerPinning.pm:2`) | If/Proj/Region/Loop only; the loader sets no `schedule_data` |
| a variable as a `Constant` with `const_type` `variable` (`Perl.pm:1011`) | PadAccess, EntryDef |
| a BinOp as `inputs = [op, left, right]` (`Perl.pm:1148-1150`; built so at `Actions.pm:2080-2081`) | `inputs = [left, right]` (`lib/Chalk/IR/Node/BinOp.pm:14-15`) |
| VarDecl, ListAssign, CompoundAssign, Interpolate, ExpressionList, TryCatch (`Perl.pm:14-29`) | none of these, except 3 VarDecl cases in 427 |
| no Phi, no memory | Phi in 172 of 427 corpus cases, MemStart in 326 |

Of the 94 wire ops, the old target's source names 23. The other 71 appear nowhere in it.

Dead code, by cause:

1. **The Program path.** `_emit_program` (`:651`), `_generate_with_cfg`
   (`:539`), `_build_cfg_lookup` (`:557`), `emit_cfg_if/loop/try_catch`
   (`:1447-1650`), `emit_from_cfg_state` (`:1571`). No caller in `lib/`
   outside this file and the C target. The comment at `:76-77` says it is
   kept "transitionally for Target::C".
2. **`EmitHelpers.pm` (2502 lines) is not the Perl target's.** Its header
   says "Shared helper methods for C and XS code emitters". Its only user is
   `lib/Chalk/Bootstrap/Perl/Target/C.pm`. It goes with the C and XS
   backends.
3. **Stale names.** `_emit_hash_ref_expr` (`:1306`) and `_emit_array_ref_expr`
   (`:1348`) handle HashLiteral and ArrayLiteral; comments at `:1123,1135`
   still say HashRef/ArrayRef. No `Bootstrap::IR::Node` reference is left in
   `lib/`. `t/bootstrap/perl-target-perl-tier-d.t:43` still lists
   `lib/Chalk/Bootstrap/IR/NodeFactory.pm`, a file that no longer exists.
4. **A silent drop.** `_emit_mop_class` (`:147-185`) emits fields, ADJUST,
   methods and subs. It never reads `class_scope_vars`
   (`lib/Chalk/MOP/Class.pm:48`). A class-level `my %lookup = (...)` vanishes.

Reusable as **spellings only**, copied into the functor's printer when the
slice that needs them lands: single-quote escaping (`:1561`), subscript
formatting (`:1278`), the precedence note on `?:` under a binary operator
(`:1151-1158`), `use`/`no` kept apart (`:123-126`), class ordering by parent
(`:1650`).

The old target is **frozen** from step 2. It gets no fixes. It is deleted in
step 18.

## 5. Order of work

Rules for every step:

- TDD. The named test fails first.
- One perl process at a time, `ulimit -v 4000000`.
- **DIFFERS is 0 at every step.** A case the functor cannot do is a GAP by
  name, and the producer falls back to Deparse for it.
- The parity number is `FUNCTOR ROUNDTRIP` of 431 on the pvm corpus, printed
  by `tools/corpus-roundtrip.pl --via both`. Target: 427, Deparse's number.
- "Bound" below is the count of corpus cases whose ops all lie in the slices
  so far (measured, 427 loadable cases). The real number will be lower until
  the non-direct cases in that slice are done. Record the real number in the
  commit message.

### Phase A: the seams

1. **Chalk: a load-only entry.** `load_program($json)` returns the graphs
   (every one on the wire, none pruned, no context copies), and `classes`,
   `phase_blocks`, `data_section`, `refused`. No Analysis. `from_json` calls
   it and then does what it does now.
   *Test first:* `t/bootstrap/ir/load-program-only-loads.t` -- a wire with an
   unreached module sub keeps it; no key holds `@`; a BEGIN with effects
   loads; every stamp equals the wire's; `from_json`'s result is unchanged.
2. **Chalk: the functor's skeleton, slice 0.** `Perl::Node`, builder, printer,
   `out`. Start, the program's Return, Constant, Print to STDOUT or STDERR.
   Every other op is `out("no rule for $op")`. Plus `script/chalk-son-perl`.
   *Test first:* `t/bootstrap/ir/perl-functor-slice-0.t` -- `print "a\n"`
   prints the same under perl; `print 1 + $x` is refused, and the message
   names `Add` or `PadAccess`.
3. **Producer: the helper and the two-way census.** `tools/lib/ChalkPerl.pm`;
   `tools/corpus-roundtrip.pl --via deparse|chalk|both`. `both` prints
   Deparse's tally, the functor's tally, and the functor's GAPs ranked by
   cause (as `corpus-llvm-roundtrip.pl` ranks `GAP_CAUSE`).
   *Test first:* `P:t/corpus-perl-functor.t` (opt-in, like the ratchet):
   every case lands in one bucket; FUNCTOR DIFFERS is 0; FUNCTOR ROUNDTRIP is
   at least its floor. The first floor is whatever step 2 measures.

### Phase B: the slices

Each slice: a chalk test file `t/bootstrap/ir/perl-functor-<slice>.t` that
compiles small sources with B::SoN, runs the functor's output, and compares
stdout with perl's. It also holds one refusal per GAP the slice adds. Then
the census, then the new floor.

| Step | Slice | Not-direct work | Bound |
|---|---|---|---|
| 4 | Operators and value forms (section 3, first two rows). Coerce by rule N13. | N13 | 30 |
| 5 | Lexicals and package scalars: PadAccess, Assign, EntryDef, EntryWrite, Increment, VarDecl, EnvRead, BacktickExpr, Chomp. | N5, N6 (straight line), N7 | 52 |
| 6 | Builtin calls. | context of a call's arguments | 70 |
| 7 | Subs: one graph each, direct calls, ArgsSource, Parameter, Wantarray, SubDefined. | N11 | 82 |
| 8 | Aggregates: literals, Subscript, Count, Slice, Exists, Delete, PostfixDeref, Ref, RefType. | the shape arrows (2.2), N6 for aggregates | 195 |
| 9 | If, Proj, Region, value Phi. | N1, N2, N4 (arms) | 229 |
| 10 | Loop, loop Phi, ListAppend, loop exits. | N3, N4 (loops) | 321 |
| 11 | Closures and lifted bodies. | N8 | 335 |
| 12 | Regex ops. | counted substitutions, delimiters | 363 |
| 13 | Unwind, block eval, LocalAlias, ElemRestore. | N9, N10 | 403 |
| 14 | Classes, packages, phase blocks, `use`, `__DATA__`: FieldAccess, PackageMark, IsaOp. | N12 | 427 |

Before each slice, read Deparse's record for it (section 3's last column)
and the memory notes it cites. Port the **case**, as a test, not the code.

Step 8 is where the shared graph readers appear twice. T2's `successors`
(`T2.pm:186`), `_memory_input` (`:884`) and `_own_nodes` (`:3207`) read the
graph and know nothing of LLVM. Move them to one module both targets use, as
its own commit, with T2's 72 `t2-*.t` files as the test. Do not copy them.

### Phase C: Deparse retires

15. **The producer's tests through the functor.** `SON_RENDER=chalk` makes
    the test helper use `ChalkPerl`. Count files passing of the 359. Work the
    failures as functor slices. Then:
    - the 44 files that assert on emitted text: each becomes a behaviour
      test, or is deleted with its reason. Text shape is not what the oracle
      checks (`P:docs/memory/bson-emits-ir-perl-is-validation.md`).
    - the 29 that assert on a GAP's wording: reworded to the functor's GAP.
      The refusal itself must still happen.
    - `P:t/deparse-memory-table-matches-producer.t`: its table moves to the
      functor, or the test is deleted if the functor needs no such table.
16. **The other gates through the functor:** chalk lib/ 179 of 179, chalk's
    suite 482 SAME, perl t/ 11. Same floors, `--via chalk`.
17. **The analysed gate (chalk).** The functor over `from_json`'s graphs, on
    the corpus. Context copies named. A DIFFERS here is a pass that changed a
    program. *Test first:* `t/bootstrap/corpus/perl-functor-analysed.t`.
    This step is not needed to delete Deparse. It can wait.
18. **Delete.** Producer: `lib/SoN/Deparse.pm`, the `--via` switch, the
    Deparse lines of `CONTRIBUTING.md`. Chalk:
    `lib/Chalk/Bootstrap/Perl/Target/Perl.pm`, the EagerPinning scheduler and
    its `t/bootstrap/scheduler/` tests, if perigrin agrees (question 3).
    *Test first:* the full producer suite with `SoN::Deparse` absent.

`EmitHelpers.pm`, `Perl/Target/C.pm` and the BNF C/XS targets leave with the
C/XS decision. That is its own change and can land any time.

## 6. The chalk tests that fail today

Run one at a time, 2026-11-14, as the brief gives the command.

| Test | Result | What it tests | Action | Reason |
|---|---|---|---|---|
| `codegen-determinism.t` | 11/11 | the BNF target | keep | not the Perl target |
| `codegen-perl.t` | 53/53 | the BNF target | keep | same |
| `codegen-pipeline.t` | 157/157 | the BNF target | keep | same |
| `codegen-target.t` | 6/6 | the Target base class | keep | same |
| `perl-actions-tier-a.t`, `-b.t`, `-c.t` | 76, 85, 15, all pass | the parser's IR shape | keep | not the target |
| `perl-actions-fixup.t` | dies after 13: `Can't call method "value" on an undefined value` at line 162 | the parser's IR shape | **update** | Stale. It reads Unwind's value at `inputs()->[1]`. It moved to `inputs->[0]` (`lib/Chalk/IR/Node/Unwind.pm:19`). Use `->value`. |
| `codegen-block-list-ops.t` | 8/8 | old target, from source | keep until step 18, then delete | passes; dies with the old target |
| `perl-target-perl-tier-a.t`, `-b.t` | 20/20, 26/26 | old target | keep until step 18, then delete | same |
| `codegen-hash-init.t` | fails 4 and 6 | old target | **replace** | A real silent drop (section 4, item 4). The old target is frozen, so make it refuse: `_emit_mop_class` dies by name when a class has `class_scope_vars`. The test asserts the refusal. |
| `codegen-builtin-hash-arg.t` | fails 4 | the parser | **update: TODO, named** | The emitted text is `'keys' % 'h'`. The parser read `keys %h` as a modulo. That is a parser defect, older than this work (`docs/plans/2026-05-21-phase-7d-handoff.md:90`). Not the target's to fix. |
| `codegen-no-pragma.t` | fails 7 (5 is already TODO) | parser and old target | **update: TODO, named** | `no strict 'refs'` inside a sub body is dropped. Cause not located (Actions or MOP). Name it in the TODO; find it only if the parser path is kept. |
| `perl-target-perl-tier-c.t` | fails 8: generated Context.pm does not compile | old target, one lib file | **delete at step 16** | The chalk-lib gate through the functor covers the same file, by behaviour. |
| `perl-target-perl-tier-d.t` | not finished after 543 s; 9 failures that are not TODO in the first 25 of 197 files | old target, all of lib/ | **delete at step 16** | Its intent is "every lib/ module round-trips". That is the chalk-lib gate (179 of 179 under Deparse). As it stands it cannot finish in ten minutes, so it guards nothing. |

## 7. Risks, and what must refuse by name

The rule: never a silent wrong answer. Each line below is a refusal the
functor must have, with a test that names its cause.

1. **An op with no rule.** `no rule for <op>`. No catch-all that prints
   something.
2. **Control the walk cannot structure:** an If without exactly two indexed
   Projs; a Region whose arms it cannot pair; a control node with more than
   one successor (T2 refuses the same, `T2.pm:214`).
3. **Exits:** a return from inside a loop whose exit carries a value or runs
   a restore; a break whose exit edge is not found. Deparse refuses these by
   name; keep each.
4. **A merge of shapes:** a Phi of an aggregate and a scalar; a sub's exit
   that merges a list with a scalar.
5. **A read that cannot stand before its store:** when statement order cannot
   honour a memory edge and no temporary can hold the value (an alias, an
   element read in a loop after a store).
6. **An effect read twice** must be bound once. If it cannot be bound (it is
   an lvalue, or a list of unknown length in scalar use), refuse.
7. **Coerce.** Dropped only for a (from, to, consumer) the table lists.
   Anything else is refused. Deparse drops every Coerce (`:8125`); do not
   copy that.
8. **Names.** The functor's temporaries must not meet the program's. Refuse a
   program that has a variable with the reserved prefix, or a string eval or
   symbolic reference that could see one.
9. **A lifted body not on the wire:** a sort comparator, an `s///e` body, a
   called sub. Refuse naming it.
10. **Constants:** a Constant kind with no rule (Deparse: "no rule for a
    `$t` Constant"); a string that is not valid UTF-8; a non-finite number;
    a pattern that uses every delimiter.
11. **A Return's faces.** `valueless`, or a scalar face and a list face. Emit
    both readings correctly or refuse.
12. **An analysed graph given by mistake.** A graph name holding `@` is
    refused until step 17.
13. **A hang.** The tool runs under a timeout in every harness. A timeout is
    its own bucket, never a GAP and never a pass
    (`P:docs/memory/MEMORY.md:126`).

Risks to the plan itself:

- **Size.** Deparse reached 427 over about six weeks. The table rows are
  fast. N1-N6 are not. The ladder lets the work stop at any step with
  Deparse still the fallback and nothing wrong.
- **Two renderers for a while.** Until step 18 a new wire feature needs both.
  Rule: Deparse gets a change only for a case that still falls back to it.
- **The oracle sees stdout only** (`P:tools/corpus-roundtrip.pl:25`). A
  functor defect and a producer defect can cancel. Keeping the functor dumb
  (2.4) is the guard. So is the analysed gate, later.
- **A hollow suite.** Half the producer's test files will need a chalk clone.
  If they skip without one, the suite passes while testing nothing. See
  question 2.
- **The pin.** A functor fix lands in chalk, then the producer's pin moves.
  A census read at a stale pin is the wrong number
  (`P:docs/memory/MEMORY.md:161`). The census prints the pin it used.
- **Process cost.** One perl process per render. Chalk's loader starts in
  about 0.05 s (measured). Fine for 431 cases; measure it for the 359 test
  files at step 15.

## 8. Questions for perigrin

1. **Which graph does the producer's gate render: loaded, or analysed?**
   Recommended: loaded, with no Analysis (2.4). The analysed graph becomes a
   second gate later (step 17).
2. **Without a chalk clone, do the producer's round-trip tests fail or
   skip?** Recommended: fail. `SON_CHALK` is already set by
   `P:tools/cloud-setup.sh:88`.
3. **Is the old Schedule-driven target deleted at step 18, or kept for the
   grammar parser's output?** Recommended: deleted. When chalk's parser
   replaces B::SoN it must emit the wire's dialect, and then the functor
   serves it too.
