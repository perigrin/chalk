# Test::Chalk measured again, and what each chalk test loads

**Date:** 2026-11-17
**Status:** MEASUREMENT. No lib code changed.
**Head:** chalk 9e56dcf4 (bson/llvm-corpus); B::SoN from /home/user/repo/lib.
**Env, every run:** `ulimit -v 4000000; HOME=/home/runner PERL5_SON_LIB=/home/user/repo/lib LLI=/usr/bin/lli`, at most 4 heavy processes.
**Follows:** `plan-test-chalk.md` (memory), measurement item 5 of 2026-11-11.
**Data:** `2026-11-17-test-imports.tsv` (one row per test x module, 194,696 rows),
`2026-11-17-test-imports-summary.tsv` (one row per test, 900 rows).

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
- **The dumper:** a scratch `INCdump.pm`, loaded with `-M`. It loads no modules
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

## Reproduce

The scratch scripts were not committed: INCdump.pm, analyze.pl, swapm.pl, stage2.pl.

- **Part A:** for each test, run
  `INCDUMP_OUT=x.inc perl -Ilib -It/lib -I<dir> -MINCdump t/....t`.
  The dumper sets `${^HOOK}{require__before}`, and writes `%INC` from an
  `INIT` block and an `END` block.
- **Part B:** run `swap-one.pl`, which is TapDiff on the swapped copy, or use
  the split driver to get times per stage.
