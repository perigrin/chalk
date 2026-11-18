# Test::Chalk measured again, and what each chalk test loads

**Date:** 2026-11-17
**Status:** MEASUREMENT. No lib code changed.
**Head:** chalk 9e56dcf4 (bson/llvm-corpus); B::SoN from /home/user/repo/lib.
**Env, every run:** `ulimit -v 4000000; HOME=/home/runner PERL5_SON_LIB=/home/user/repo/lib LLI=/usr/bin/lli`, at most 4 heavy processes.
**Follows:** `plan-test-chalk.md` (memory), measurement item 5 of 2026-11-11.
**Data:** `2026-11-17-test-imports-summary.tsv` (one row per test), the run
AFTER the migration below (901 tests). The before run (900 tests) is that file
at 0db4c6b2. The full table, one row per test x module (151,765 rows after,
194,696 before; 46 MB), is not committed: `tools/test-imports/run.sh OUTDIR`
rebuilds it, with the summary, in OUTDIR.

## Headline

| | 11-11 | 11-17 |
|---|---|---|
| easy-tier files (same selector) | 279 | 288 |
| SAME | 1 | **2** |
| DIFFERS | 0 | **0** |
| REFUSED | 70 | **281** |
| TIMEOUT (240 s) | 208 | **5** |

- **TIMEOUT is no longer the compile cost.** All 5 are one B::SoN hang (below),
  not slow translation. Every one is stuck in the same loop; given 1500 s, none
  finished.
- **Almost every file now reaches T2, and T2 refuses.** 192 of the 281 refusals
  are one cause: "a scalar deref where a reference T2 does not make may reach it".
- **SAME:** `t/bootstrap/mop/parse-class-use.t` (2 tests) and
  `t/bootstrap/optimizer/pass-contract.t` (6 tests). Both print real TAP under
  perl; neither is a skip_all.
- **DIFFERS: none**, so there is no wrong answer to reproduce.

## Part B: the swap, on today's head

### Method

- **Selector:** the one in `measure-easy.pl`. A file that says `use Test::More`
  and none of the hard-tier names (use_ok require_ok like unlike is_deeply cmp_ok
  skip todo todo_skip eq_array eq_hash eq_set TODO can_ok isa_ok new_ok explain
  subtest). It finds 288 files today. 51 differ from the 11-11 list (new files,
  and files that gained or lost a hard-tier name).
- **The swap:** as `swap-one.pl` does it. A temp copy with `use Test::More`
  changed to `use Test::Chalk` and `use lib 't/lib';` prepended. Nothing in t/
  was changed.
- **The compare:** TapDiff's `compare` split into timed stages, with one 240 s
  budget per file as on 11-11:
  1. perl runs the copy;
  2. B::SoN writes the wire (`-MO=-q,SoN,json`);
  3. chalk links and loads the wire, then T2 lowers it;
  4. lli runs the result.

  The verdict logic and messages are TapDiff's, copied. A check on two known
  files gave the same verdict and reason from `swap-one.pl` and from the split
  driver: pass-contract.t SAME, and t2-a-hash-in-scalar-context-counts-its-keys.t
  REFUSED "a list assignment to an array or hash".
- **Denominator:** 288 files in, 288 verdict rows out.

### Refusal ranking (281)

| n | cause |
|---:|---|
| 192 | T2: a scalar deref where a reference T2 does not make may reach it |
| 36 | T2: a list assignment to an array or hash |
| 15 | B::SoN GAP: a string eval of code made at run time, with a lexical in scope |
| 12 | T2: method X has a parameter past its declared ones (Chalk::MOP's declare_class and kin) |
| 6 | T2: Phi |
| 4 | T2: Call builtin refaddr |
| 3 | load: a sub the program calls is refused in its module (2: s/// on a target that is not a named scalar, in Target::Perl::_emit_interpolated_string; 1: a consumed ternary arm stores an element, in TypeInference::_complete_type) |
| 2 | B::SoN INTERNAL ERROR "Stack underflow" (SoN/FromOptree/StackSim.pm:29), masked as a skip: File::Find::Follow_SymLink (style-postfix-deref.t); main::__PROGRAM__ (t2-a-used-module-s-sub-is-called.t) |
| 2 | swap artifact: the copy cannot find lib/ (the test relies on `prove -l`): ir-cfg-patterns.t, semantic-action-scope.t |
| 2 | T2: sub ... has no Return (_emit_interpolated_string; _complete_type) |
| 1 each | B::SoN GAP: nested closure's grandparent capture (ambiguity-synthetic.t); B::SoN GAP: an anon sub built once per loop pass (t2-never-mutates-the-graph.t); B::SoN GAP: s///ge on a non-scalar subject (t2-runtime-strings-are-sized.t); T2: can() may hand back a sub not loaded (semiring-precedence.t); T2: a read through a reference across a method call (phi-backedge.t); T2: a read through a reference across a push (padaccess-identity.t); T2: a reference to what is not an array (earley-nullable-prediction.t) |

Notes on the table:

- **Top 5:** scalar deref 192; list assignment to an array or hash 36; string
  eval with a lexical 15; method parameter past its declared ones 12; Phi 6.
- **The scalar-deref refusal comes from what a test calls, not what it loads.**
  A probe that loads Chalk::IR::NodeFactory (113 chalk modules) and calls
  nothing is SAME (`use Test::Chalk; use Chalk::IR::NodeFactory; ok(1);
  done_testing();`). Unreached subs are pruned, so the check fires on code
  the test reaches.
- **Three refusals are swap artifacts, not chalk.** perl itself fails on the
  swapped copy:
  - two cannot find lib/ without `-Ilib`;
  - `ambiguity-synthetic.t` calls `Test::More->builder`, which Test::Chalk does not provide.

  `ambiguity-synthetic.t` is counted under its B::SoN GAP above.
- **Two producer INTERNAL ERRORs are bugs**, not GAPs. B::SoN says so itself
  ("fix or convert to a clean GAP"). The t2-a-used-module one shows up as a
  "Name ... used only once" warning, because TapDiff reports the first line
  of stderr.

**Against 11-11** (refusals 70): scalar deref 32 -> 192; string eval 16 -> 15;
method parameter 5 -> 12. The rise is files that used to TIMEOUT and now reach T2.

### TIMEOUT (5): a B::SoN hang, with a two-line reproduction

The five files are `ir-node-unify-control-in.t`, `ir/coerce-num-str-non-finite.t`,
`ir/listappend-loads.t`, `ir/son-return-repr-seam.t` and `shape-rooted-match.t`.

- **How far each got:** all five were still in stage 2, B::SoN, at 239 s, and
  again at 1500 s. None reached chalk.
- **What the hang looks like:** RSS stays flat at about 44 MB with 100% CPU.
  That is a spin, not translation work.
- **Where it is stuck:** a SIGALRM stack dump puts all five in the same place.

```
B::SoN::_required_files(B::CV=...) called at lib/B/SoN.pm line 83
B::SoN::_followed_modules() called at lib/B/SoN.pm line 286
```

**Why only these five:** they are exactly the easy-tier files that load
Chalk::IR::Analysis at compile time. Analysis.pm line 355 says
`require Math::BigInt`, Math::BigInt loads Math::BigInt::Calc, and Calc's
`BEGIN` holds `for ($MAX_EXP_F = 1 ; ; $MAX_EXP_F++) { ... last if ... }`.

**The bug:** `_required_files` walks a BEGIN CV's ops by `op_next` from
`START`, with no visited set. A loop without a condition makes that chain a
cycle, so the walk never ends.

**Minimal reproduction:** B::SoN never returns on this program; perl prints `ok`:

```perl
BEGIN { my $i = 0; while (1) { last if $i++ > 2 } }
print "ok\n";
```

The same shape as a C-style `for (...; ; ...)` hangs too; `$i++ while $i < 3`
does not. `use Math::BigInt;` and `use Math::BigInt::Calc;` alone each hang;
`use Math::BigInt::Lib;` does not.

### Time per stage (283 files that got past B::SoN, 4-wide)

| stage | median | p90 | max |
|---|---:|---:|---:|
| B::SoN | 20.9 s | 48.8 s | 189.7 s |
| chalk load (link + from_json, incl. compiling chalk) | 7.2 s | 9.1 s | 27.8 s |
| T2 lowering | 0.5 s | 0.7 s | 8.7 s |
| wire size | 3.1 MB | 4.3 MB | 17.6 MB |

Split by what the test loads at compile time under perl:

| | n | B::SoN median / p90 / max | wire median |
|---|---:|---|---:|
| fewer than 100 chalk modules | 240 | 20.6 / 23.2 / 35.1 s | 3.1 MB |
| 100 or more chalk modules | 43 | 83.8 / 172.0 / 189.7 s | 7.9 MB |

Compile cost is still real for the big ones (up to 190 s of a 240 s budget),
but it no longer decides the verdict.

## Part A: what every test loads

### Method

- **The run:** every `.t` under t/ (900 files), under perl as the suite runs
  them: `perl -Ilib -It/lib`, cwd the worktree, the env above.
- **The dumper:** `tools/test-imports/INCdump.pm`, loaded with `-M`. It loads no modules
  of its own, and it records:
  - every `require`, through `${^HOOK}{require__before}`: who required it, the
    file and line, the phase, and whether this was the first load;
  - `%INC` at `INIT`, which is what compile time loaded and what B::SoN follows;
  - `%INC` at `END`, which adds run-time requires;
  - `@DynaLoader::dl_modules`, the modules whose `.so` was loaded.
- **class:** `chalk` (lib/Chalk), `harness` (t/lib, t/bootstrap/lib, other t/
  files), `core` (privlib/archlib), `site`, or `xs` (a `.so` was loaded for
  that package; `xs` takes precedence, and `loc` keeps the location).
  `site` and `producer` (B::SoN's lib) never occur.
  - Scalar::Util is classed `core`: its XS lives in List::Util's `.so`.
- **phase:** `compile` (in `%INC` at INIT) or `run` (at END only).
- **under_test:** `yes` when a chalk lib module or anything a chalk lib module
  requires reaches it, through any require edge, first load or not. `no` is an
  artifact. `unknown` is reached only from a string eval (Math::BigInt::Calc,
  which Math::BigInt loads with `eval "require ..."`, and what Calc loads).
  - **CORRECTED 2026-11-18 (Part D).** The first run credited a `use parent`
    load to `parent.pm`, the file that ran the `require`. Chalk::Target::LLVM
    says `use parent` (LLVM.pm:11), so parent.pm was `yes`, and so was
    everything parent.pm ever loaded in that test -- File::Temp's
    IO::Seekable, IO::Handle and Symbol among them, though no lib/ file
    requires them. INCdump now skips parent.pm and base.pm frames to the real
    caller (`t/docs/test-imports-incdump.t`), both trees were measured again,
    and the artifact numbers in Parts A and C are superseded by Part D.
- **Results:**
  - 899 of 900 completed inside 2400 s; t/grammar-conformance.t is covered in
    the next bullet.
  - All "not ok" lines are `# TODO`.
  - t/bootstrap/corpus/mode2-extractor.t bails out: it needs ~/dev/perl5,
    which the verify excludes. Its INIT data is still recorded.
  - Six files skip_all: they need ~/dev/perl5 or CHALK_BENCHMARK, or
    cross-load-son-json.t, which looks only at ~/dev/perl5-son and ignores
    PERL5_SON_LIB.
  - t/grammar-conformance.t: hit the 2400 s limit 4-wide (430 of 434 ok).
    Rerun alone, it passed 434/434 in 2145 s; its row is from that rerun.
- **Paths in the TSV:** core paths are written `$privlib/` and `$archlib/`.
  The file is 46 MB.

### Size per test (all 900)

Module counts include pragmas. Lines are source lines of the loaded files.

| per test | median | p90 | max |
|---|---:|---:|---:|
| modules loaded (END) | 246 | 248 | 306 |
| modules at compile time (INIT; what B::SoN follows) | 78 | 239 | 290 |
| source lines, all loaded | 88,168 | 88,613 | 103,644 |
| source lines at compile time | 34,980 | 82,150 | 98,445 |
| chalk modules | 152 | 160 | 167 |
| chalk lines | 29,652 | 30,003 | 32,340 |
| chalk modules at compile time | 2 | 160 | 167 |
| chalk lines at compile time | 404 | 29,159 | 32,340 |
| XS-backed modules | 9 | 9 | 12 |
| harness (t/) modules | 1 | 2 | 7 |
| artifact modules (not reached from chalk lib) | 53 | 74 | 137 |
| artifact lines | 21,594 | 29,022 | 51,200 |

- **Compile time is bimodal.** 393 of 900 tests load 100 or more modules at
  compile time, and 374 load 100 or more chalk modules then. Most of the rest
  load chalk only at run time: 340 test files say `require
  Chalk::CodeGen::Pipeline;` after their skip checks. Under perl a test
  touches almost all of chalk either way (median 152 of 217 lib modules).
  B::SoN sees the compile-time half.
- **The largest:**
  - most modules: `t/bootstrap/mop-has-default-validation.t` (306);
  - most chalk lines: `t/bootstrap/codegen-harness/target-hierarchy.t` (167 modules, 32,340 lines).
- **For scale:** chalk's lib is 217 `.pm` files and 53,053 lines. Tests load
  204 of them in all.
- **The easy tier (288 files):**
  - median 247 modules and 88,519 lines in all;
  - at compile time, median 78 modules and 34,980 lines;
  - chalk at compile time: median 0, p90 117, max 164.

### The common core

Nearly every test (90% or more, 810 of 900) loads 64 modules. 61 of them are
not chalk:

- **45 Test::Builder/Test2 modules**, all from `use Test::More;`.
  - That line loads 55 modules (median), of which 48 (17,183 lines) nothing
    in chalk needs.
- **19 core modules and pragmas:** Carp, Config, Exporter, List::Util (XS),
  Scalar::Util, Time::HiRes (XS), XSLoader, mro (XS), overloading, strict,
  warnings, warnings::register, utf8, feature, experimental, version,
  version::regex, lib.
  - Most of these come in first through `use Test::More;` (Test2::Util,
    Test::Builder).
  - experimental and version come in through `use experimental` in
    lib/Chalk/MOP.pm.
- **1 chalk module:** Chalk::IR::Node.

At 85% or more (765 of 900), **113 chalk modules (5,576 lines)** join. They are
**exactly the Chalk::IR::NodeFactory closure**: the factory and its node classes.

Which single `use` line pulls in a big subtree (median over the tests that
have the line; modules include the module itself):

| line in the test | tests | modules | chalk modules | chalk lines |
|---|---:|---:|---:|---:|
| `use Test::More;` | 841 | 55 | 0 | 0 |
| `use Test2::V0;` | 58 | 112 | 0 | 0 |
| `require Chalk::CodeGen::Pipeline;` / `use` | 352 | 165 | 151 | 29,975 |
| `use TestPipeline ...;` (t/bootstrap/lib) | 97 | 167 | 160 | 18,987 |
| `use Chalk::CodeGen::Harness::TapDiff` / `require` | 60 | 167 | 151 | 29,975 |
| `use Chalk::CodeGen::Harness::MdtestCorpus;` | 23 | 189 | 152 | 30,129 |
| `use Chalk::CodeGen::Harness;` | 23 | 171 | 138 | 9,207 |
| `use Chalk::IR::Serialize::JSON ...;` | 69 | 134 | 124 | 12,090 |
| `use Chalk::Bootstrap::Semiring::SemanticAction;` | 50 | 117 | 117 | 6,688 |
| `use Chalk::IR::NodeFactory;` | 90 | 118 | 113 | 5,576 |
| `use Chalk::Target::LLVM;` | 64 | 39 | 29 | 23,179 |
| `use File::Temp qw(tempfile);` | 491 | 20 | 1 | 28 |
| `use Chalk::MOP;` | 66 | 13 | 8 | 539 |

- **Wherever it comes in from, Chalk::IR::NodeFactory brings 113 modules**
  (median over the 785 tests that load it): 113 chalk modules, 5,576 lines.
- **Chalk::IR::Serialize::JSON brings 130, and Chalk::CodeGen::Pipeline 165.**
  These are the three subtrees a per-module cache would share across files.

### Artifacts: loaded only because of the harness or the test environment

An artifact is a module that no chalk lib module reaches. These are grouped by
the line in the test that brings them in, with the median count of artifact
modules and lines over the tests that have the line:

| line that brings them in | tests | artifact modules | artifact lines |
|---|---:|---:|---:|
| `use Test::More;` | 842 | 48 | 17,183 |
| `use lib 'lib', 't/lib';` (lib.pm) | 880 | 1 | 213 |
| `use File::Temp qw(tempfile);` (File::Temp, Errno, Carp::Heavy; its other 17 modules chalk lib reaches too) | 491 | 3 | 4,034 |
| `require Chalk::CodeGen::Pipeline;` (the t/lib module itself) | 352 | 1 | 164 |
| `use TestPipeline ...;` | 98 | 1 | 310 |
| `require Chalk::CodeGen::Harness::TapDiff;` | 60 | 2 | 258 |
| `use Test2::V0;` | 58 | 103 | 29,259 |
| `use Chalk::CodeGen::Harness::Rooted ...;` | 32 | 1 | 111 |
| `use Chalk::CodeGen::Harness;` | 23 | 28 | 22,178 |
| `use Chalk::CodeGen::Harness::MdtestCorpus;` | 23 | 8 | 7,220 |
| `use TestPerlHelpers ...;` | 4 | 22 | 13,154 |
| `use_ok('Chalk::CodeGen::Harness::GapMap');` | 4 | 28 | 22,761 |
| `use Chalk::CodeGen::Harness::RunUnderPerl;` | 3 | 23 | 15,168 |

- **The swap removes the largest artifact.** `use Test::More` is 48 modules
  and 17 k lines in 842 tests, and Test::Chalk is one module.
- **The next largest is `use Test2::V0`:** 103 modules and 29 k lines, in 58
  files the swap does not touch.
- **Four t/lib harness modules also load an artifact tree of their own:**
  Harness, GapMap, RunUnderPerl and TestPerlHelpers, 22-28 modules and 13-23 k
  lines each.
  - The largest pieces are t/lib's HandGraphs (5,146 lines), File::Temp
    (3,721), JSON::PP (3,142), overload, File::Path, Fcntl, Cwd, IO::Handle and
    IPC::Open3.
  - The per-test rows have the detail.

## Part C: the artifacts, after the migration (branch test-chalk-migrate)

Every `.t` under t/, and the two t/bootstrap/lib helpers that loaded
Test::More, now `use Test::Chalk` unless listed under "Kept" below. Test::Chalk
gained what the suite calls, each red first in
`t/bootstrap/test-chalk-under-perl.t` (Test::More's stdout, stderr and exit
status under perl are the oracle); the T2 probes in
`t/bootstrap/ir/test-chalk-gives-test-more-s-tap.t` still pass, with two more
(a subtest's plan, `$TODO`) SAME through T2.

### Test::Chalk gained

| function | why the suite needs it |
|---|---|
| `use_ok`, `require_ok` | 15 files, 29 calls; one `require_ok` |
| `explain` | 61 files (`diag explain $r` on a failure) |
| `$TODO`, read as the caller's package's | 29 files; `local $TODO` replaces an exported alias, so it is read by name |
| `$Test::Builder::Level` | PrecedenceSpecHelpers' `isa_with_shape`: without it a TODO block around the helper is ignored |
| Test::More's prototypes (`ok ($;$)` ...) | `ok((grep {...} @ids), ...)` is the count, not the first match (earley-inline-opt.t) |
| `is_deeply` of an object | walked as what it is underneath, as Test::More's `_type` (earley-chart-reachability.t) |
| a subtest's plan checked | a subtest running other than it planned failed under Test::More and passed silently here |

### Migrated

| | files |
|---|---:|
| `use Test::More` -> `use Test::Chalk` | 823 `.t` + 2 helper `.pm` |
| `use Test2::V0` -> `use Test::Chalk` | 49 |
| new (`test-chalk-under-perl.t`) | 1 |
| kept on Test::More | 19 |
| kept on Test2::V0 | 9 |

The edit was scripted: the framework line swapped, t/lib put in `@INC` before
it (a `use lib` line moved up or widened). By hand:

- `comonad-threading.t`: `use Test::More tests => 16` -> `plan tests => 16`.
- Five corpus files: `binmode Test::More->builder->output ...` -> `binmode
  STDOUT/STDERR`.
- `fork-test-helper.t`: the child sends TAP to the file by reopening STDOUT and
  STDERR, not through `->builder`. `->current_test` becomes `$Test::Chalk::COUNT`.
- Test2::V0 files:
  - `skip_all "x"` -> `plan skip_all => "x"`.
  - One `todo 'why' => sub {...}` -> `TODO: { local $TODO = 'why'; ... }`.
  - 41 `is($ref, [...] / {...})` -> `is_deeply`: Test2's `is` compares a reference
    deeply. Found by wrapping `main::is` at run time and logging each call
    whose expected value is a reference. An `is` of two `class` objects is
    identity under both, and was left alone.
- `PrecedenceSpecHelpers.pm`: `Test::More::pass/fail/diag` -> `Test::Chalk::`.

The migration also turned up a lib bug. `Chalk::IR::Node::remove_consumer`
called `Scalar::Util::refaddr`, but Node.pm never loaded Scalar::Util; it
worked only because Test::More did. It now calls the builtin `refaddr` that
`use 5.42.0` imports, as the rest of Node.pm does.

### Kept, and what Test::Chalk lacks for them

- **`plan skip_all` inside a subtest** skips that subtest under Test::More. In
  Test::Chalk it ends the program. Adding it needs the subtest's code run in
  an eval, or a `last` out of `plan`:
  - T2 refuses a `last` that leaves its sub. That would refuse `plan` for
    every program.
  - Under T2, a package variable the code ref writes is read stale after
    `eval { $code->(); 1 }`, so the subtest probe DIFFERS.

  Repro: `our $C; sub inc { $C = $C + 1 } sub st { my ($code) = @_; $C = 0;
  my $ran = eval { $code->(); 1 }; print $C + 0, "\n" } st(sub { inc(); inc() });`
  perl prints 2; T2 prints 0.

  So these stay on Test::More:
  - benchmark/parse-performance.t
  - filter-composite-audit.t
  - transform/entry-normalization.t
  - mop/mop-carries-the-graph-registry.t
  - in ir/: a-flattening-input-is-not-one-element, a-list-stamped-literal-is-an-array,
    a-recursive-call-contributes-bottom, builtin-join-lowers-a-static-list,
    builtin-keys-lowers-in-insertion-order, builtin-sort-orders-an-array,
    call-at-the-abi-unbox-at-the-node, callsite-seeding-narrows-and-joins,
    callsite-want-picks-the-reading, ctor-arg-inference-joins,
    direct-call-args-join-all-callsites, element-repr-joins-stores,
    resolve-direct-calls-reads-the-edge, son-loop-backedge,
    sort-fold-signature-survives-the-loader

  Two Test2::V0 files are kept for the same reason:
  - ir/loader-reproduces-the-wire.t
  - ir/field-default-carries-the-field-type.t (which also calls `dies`)

  son-loop-backedge.t shows what this hides. Its "lowering failed" subtest
  logs `not ok 1 - lower() does not die`, then skip_alls, so it reports ok:
  T2 says "a loop condition that is not one value".
- **Test2-only functions** Test::Chalk does not have (Test::More has none of them):
  - codegen-harness/extract-wrap.t: `ref_ok`, `isa_ok($x, [classes])`
  - codegen-harness/comparator.t: `ref_ok`
  - codegen-harness/oracle-neg.t: `dies`, `ref_ok`, `isa_ok($x, [classes])`
  - codegen-harness/oracle.t: `ref_ok`, `isa_ok($x, [classes])`
  - ir/method-return-type-from-wire.t: `dies`, `lives`
  - ir/typed-invariant-takes-a-graph.t: `dies`
  - mop-has-default-validation.t: `dies`

### The other artifacts

| artifact | removed from | kept in | why kept |
|---|---:|---:|---|
| `use Test::More` (48 modules) | 823 + 2 `.pm` | 19 | skip_all in a subtest (above) |
| `use Test2::V0` (103 modules) | 49 | 9 | Test2-only functions, or skip_all in a subtest (above) |
| `use File::Temp` (3 artifact modules) | 1 (llvm-an-inlined-callee-has-its-own-variables.t) | every other file that has it | each one calls tempfile/tempdir/tmpnam: the test writes its probe program to a file |
| `use lib 'lib', 't/lib'` (lib.pm, 213 lines) | 0 | all | a test must run as `perl -Ilib t/x.t` and under TapDiff/B::SoN with no `-I`; Test::Chalk lives in t/lib. 16 files that had no t/lib gained `use lib 't/lib'` |
| `use Chalk::CodeGen::Harness` | 1 (corpus-single-source.t: reads Harness.pm as text) | 22 | each calls `Chalk::CodeGen::Harness->run_entry` |
| GapMap (`use_ok`/`use`) | 0 | 5 | it is the module under test (gap-map*.t), or tier2.t calls `->generate` |
| RunUnderPerl | 0 | 4 | each calls extract_snippet/wrap_program/run_program/capture |
| TestPerlHelpers | 0 | 4 | each calls setup_perl_grammar/parse_and_generate/eval_module |

### Before and after (every `.t`, under perl, method of Part A)

| per test | before median | p90 | max | after median | p90 | max |
|---|---:|---:|---:|---:|---:|---:|
| modules loaded (END) | 246 | 248 | 306 | 200 | 202 | 306 |
| modules at compile time (INIT) | 78 | 239 | 290 | 32 | 192 | 259 |
| source lines, all loaded | 88,168 | 88,613 | 103,644 | 71,704 | 72,149 | 103,645 |
| source lines at compile time | 34,980 | 82,150 | 98,445 | 18,515 | 66,540 | 87,676 |
| artifact modules | 53 | 74 | 137 | 7 | 12 | 137 |
| artifact lines | 21,594 | 29,022 | 51,200 | 5,129 | 8,151 | 50,411 |
| XS-backed modules | 9 | 9 | 12 | 7 | 7 | 10 |

| totals over all tests | before (900) | after (901) |
|---|---:|---:|
| test x module rows | 194,696 | 151,765 |
| of them at compile time | 123,640 | 80,784 |

The max rows that did not move are the kept Test2::V0 files
(mop-has-default-validation.t, extract-wrap.t). Test::Chalk itself is one
harness module of 607 lines in 873 tests.

### Suite

The run was `prove -j2 -Ilib -It/lib` over every `.t` except
mode2-extractor.t, grammar-conformance.t and chalk-recognizes-its-own-source.t.

- Result: 898 files, 14,170 tests, PASS.
- The two long files ran alone under perl, through the Part A runner:
  - grammar-conformance.t: 434/434, exit 0, 2083 s.
  - chalk-recognizes-its-own-source.t: 275/275, exit 0, 992 s.

## Part D: the artifacts, measured again with the `use parent` fix (2026-11-18)

Both trees, with the corrected INCdump (Part A, "under_test"):
- **before:** 9e56dcf4, Test::More, every `.t` but mode2-extractor.t (899);
- **after:** this commit's tree, every `.t` but mode2-extractor.t (901).

Every test gave a row (899 and 901). t2-census-cases.t exited 1 under the
4-wide runner in both; it passes in the suite (it is load-sensitive).
`2026-11-17-test-imports-summary.tsv` is the after run;
`2026-11-17-test-imports-summary-before.tsv` is the before run.

### Before and after

| per test | before median | p90 | max | after median | p90 | max |
|---|---:|---:|---:|---:|---:|---:|
| modules loaded (END) | 246 | 248 | 306 | 200 | 202 | 306 |
| modules at compile time (INIT) | 78 | 239 | 290 | 31 | 192 | 259 |
| source lines, all loaded | 88,168 | 88,613 | 103,644 | 71,701 | 72,145 | 103,639 |
| source lines at compile time | 34,980 | 82,150 | 98,445 | 18,216 | 66,538 | 87,673 |
| artifact modules | 58 | 70 | 137 | 12 | 16 | 137 |
| artifact lines | 22,671 | 29,022 | 51,200 | 6,204 | 9,223 | 50,408 |
| XS-backed modules | 9 | 9 | 12 | 7 | 7 | 10 |

| totals over all tests | before (899) | after (901) |
|---|---:|---:|
| test x module rows | 194,607 | 151,688 |
| of them at compile time | 123,560 | 80,409 |

The first run said 53 -> 7 artifact modules (median). It missed File::Temp's
chain (IO::Handle, IO::Seekable, Symbol, SelectSaver, Errno, Carp::Heavy), in
both trees.

### Every artifact line: removed, or kept and why

Grouped by the line in the test that brings it in (`tools/test-imports/by-line.pl`
over the full table). Lines in 3 or more tests after, then everything removed.

| line | tests before -> after | artifact modules | decision |
|---|---|---:|---|
| `use Test::More;` | 840 -> 19 | 48 | removed (Part C); 19 kept: skip_all in a subtest |
| `use Test2::V0;` | 58 -> 9 | 102 | removed (Part C); 9 kept: Test2-only functions or skip_all in a subtest |
| `use Test::Chalk;` | 0 -> 873 | 1 | kept: the test framework, one module of 607 lines |
| `use lib 'lib', 't/lib';` and kin (lib.pm, Config) | all | 1-2 | kept: a test runs as `perl -Ilib t/x.t` and under TapDiff/B::SoN with no `-I`, and Test::Chalk lives in t/lib |
| `use File::Temp qw(tempfile);` / `require File::Temp;` / `qw(tempdir)` | 464 / 15 / 8 | 8-17 | kept: each calls tempfile, tempdir or tmpnam -- the test writes its probe program and the `.ll` to files for B::SoN and lli. Its chain (IO::Handle, IO::Seekable, Symbol, SelectSaver, Errno, Carp::Heavy) goes when a test hands text to a subprocess without a file, or when chalk compiles globs (task: globs as metaclass objects) |
| `require Chalk::CodeGen::Pipeline;` / `use` | 352 | 1 | kept: the t/lib driver each one calls (`->run_detail`) |
| `use TestPipeline ...;` | 97 | 1 | kept: each calls the functions it imports |
| `require Chalk::CodeGen::Harness::TapDiff;` | 60 | 2 | kept: each calls `TapDiff->compare` |
| `use Chalk::CodeGen::Harness::Rooted ...;` | 32 | 1 | kept: each calls `rooted` |
| `use Chalk::CodeGen::Harness;` | 22 | 28 | kept: each calls `->run_entry` |
| `use Chalk::CodeGen::Harness::MdtestCorpus;` | 22 | 13 | kept: each calls `->run_case`/`->run_file` |
| `use utf8;` | 816 files -> 300 | 2 | removed from 516 files with no byte above 0x7F (header line only; never inside a program a test builds, nor in fixtures); kept in the 300 whose source has non-ASCII text |
| `use PrecedenceSpecHelpers ...;` | 6 | 2 | kept: each calls `parse_expr`/`isa_with_shape` |
| `require Chalk::CodeGen::Harness::T2Case;` | 5 | 3 | kept: each calls it |
| Comparator, HandGraphs, ProgramRunner, LLVMDriver, RunUnderPerl, GapMap, TestPerlHelpers, TestXSHelpers, the worklists, BehaviorRecord, Deviation, Mode2Adapter, HarvestPin, Tier2, Phase5LibCoverage, ReturnNodePerlDriver | 1-29 each | 1-28 | kept where the test calls it (checked against each module's subs and exports) |
| `use Chalk::CodeGen::Harness::LLVMDriver;` in corpus/host.t, regex.t, subs.t, ir/llvm-mop-classes.t, llvm-mop-registry.t | 5 | 10 | removed: never called (MdtestCorpus loads it where it is used) |
| `use Chalk::CodeGen::Harness::Mode2Extractor;` in corpus/mode2-adapter.t | 1 | 1 | removed: never called |
| `use Scalar::Util qw(blessed refaddr reftype weaken)` | 93 files | 0-2 | removed: `use 5.42.0` imports these four as builtins, lexically, ahead of the package import. `looks_like_number` is not a builtin in 5.42.0, so RunUnderPerl and Comparator keep it (they compare chalk's values with perl's) |
| `use Scalar::Util qw(looks_like_number)` in the two programs RunUnderPerl writes | 2 | 0 | removed: never called there |
| `use JSON::PP;` in ir/emitted-ir-is-well-typed.t, llvm-a-print-is-maybe-boolean.t, element-repr-joins-stores.t, mop/mop-carries-the-graph-registry.t | 4 | 2 | removed: never called (they read the wire with Chalk::IR::Serialize::JSON) |
| `use JSON::PP;` elsewhere (26 tests) | 26 | 2 | kept: each decodes or encodes JSON with it |
| `use Time::HiRes qw(time)` | 4 | 1 | kept: each times a parse |
| `use File::Find` | 6 | 1-9 | kept: each walks lib/ with `find` |
| `use Digest::SHA qw(sha1_hex)` | 1 | 6 | kept: leo-graph-equivalence.t hashes contexts |
| `use Pod::Functions` | 2 | 1 | kept: the oracle for perl's builtin list (t2-no-builtin-lists.t, a-builtin-call-answers-perl-facts.t) |
| `use File::Basename qw(basename)` | 1 | 1 | kept: called |
| `binmode STDOUT, ':encoding(UTF-8)'` (PerlIO::encoding) | 4 | 2 | kept: those tests print non-ASCII TAP |

### Verified

- chalk suite, every `.t` but mode2-extractor.t: 901 files, 0 failures.
- corpus gate: gate-green 222, t2-gate-green 222.
- chalk lib is unchanged since the last census (ROUNDTRIP 426, DIFFERS 0,
  LLI_FAIL 0), probe run (no new WRONG) and producer suite (clean).

## Reproduce

Part A is `tools/test-imports/run.sh OUTDIR` (INCdump.pm, analyze.pl; dist.pl
prints median/p90/max from a summary). The Part B scripts, swapm.pl and
stage2.pl, were not committed.

- **Part A:** for each test, run
  `INCDUMP_OUT=x.inc perl -Ilib -It/lib -I<dir> -MINCdump t/....t`.
  The dumper sets `${^HOOK}{require__before}`, and writes `%INC` from an
  `INIT` block and an `END` block.
- **Part B:** run `swap-one.pl`, which is TapDiff on the swapped copy, or use
  the split driver to get times per stage.
