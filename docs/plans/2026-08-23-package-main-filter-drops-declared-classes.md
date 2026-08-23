# `package=main` silently drops classes a real program declares

**Date:** 2026-08-23
**Status:** FIXED — perl5-son `9c48f2a` (the `not_package=` filter) and chalk
`5998db7a` (ProgramRunner uses it). Coordinator-verified.

**Outcome, stated plainly: no file moved.** The ring is unchanged at PASS=4
SKIP=10 FAIL=0 across `t/base` + `t/cmd`. What the fix bought is HONEST
BLOCKERS — `t/base/lex.t` and `t/cmd/subval.t`, the two files that declare
packages, now both report "value-context ternary with a branch-guarded element
store not yet lowered" instead of a typing GAP misattributed from their
vanished packages. Two files that were failing for a harness artifact now name
the same real unbuilt feature, which makes it a legible next target.

`Mode2Adapter` deliberately KEEPS `package=main`: it CONSTRUCTS its input
(`package main;` plus one sub), so its package set is known exactly and
inclusion is the tighter filter. The two harnesses differ because their inputs
differ.
**Found by:** perigrin, after the same mistake surfaced twice in one session in
throwaway probes — "I don't think we should filter by package main, that's a
couple times now you've had similar issues."

## The defect

`ProgramRunner::_compile_and_run` (`t/lib/Chalk/CodeGen/Harness/ProgramRunner.pm:133`)
invokes the producer as:

    -MO=SoN,json,package=main

It hands the file over UNMODIFIED — that is its whole contract, stated three
lines above: "shebang intact, no wrap". So the file may declare any packages it
likes, and every one of them is filtered out of the wire before Chalk sees it.

`Mode2Adapter::_lower_case:140` has the identical hardcoded filter.

Measured on a two-package program:

| producer options | `Thing` in wire | classes emitted |
|---|---|---|
| `json,package=main` | **DROPPED** | 0 |
| `json` | PRESENT | 98 |

## Why the filter exists, and why it cannot simply be deleted

98 classes. Without a filter every loaded `SoN::*` internal — the producer's own
`SoN::IR::Node::*` hierarchy, `SoN::FromOptree`, `Chalk`'s dependencies — leaks
into the wire. The filter is not gratuitous; deleting it wholesale trades a
false negative for a flood.

`son-corpus-wide.t:64` already solves this correctly:

    my $pkg_opts = join(',', 'package=main', map { "package=$_" } @$class_names);

It filters to main PLUS every class the case declares, learning the names from
`split_class_source`. `son-e2e.t:71` does the same.

The two harnesses that hardcode bare `package=main` are exactly the two that
have no equivalent source-scan — and `ProgramRunner` is the one that most needs
it, because it consumes arbitrary real files rather than corpus cases whose
shape is known.

## This is LIVE on the Phase-5 target set

Two files in the drain set declare packages:

- **`t/base/lex.t`** — `package Someother;` (:188), `package v10;` (:411), and
  qualified SUB declarations `sub xyz::foo` (:269) and `sub foo::::::bar`
  (:280), plus a call to `v10::foo::test2()` (:411)
- **`t/cmd/subval.t`** — reached via the same runner

Any call into those packages arrives with no resolved callee, and therefore no
return type, and GAPs at `_require_repr` (`lib/Chalk/Target/LLVM.pm:80`) as
"reached LLVM backend with NO representation" — a message that points at
TypeInference when the actual cause is that the callee was never loaded.

That is the same misattribution documented in
`docs/plans/2026-08-23-dispatch-kind-conflates-two-axes.md`: a filter artifact
reading as a typing defect.

## The fix

Give `ProgramRunner` (and `Mode2Adapter`) the same treatment
`son-corpus-wide.t` has: scan the source for declared packages and pass
`package=$_` for each alongside `package=main`.

For `ProgramRunner` the scan must run over the RAW FILE, since it deliberately
does not transform its input.

**A `^\s*package` scan is NOT sufficient, and `lex.t` is the proof.** Two of its
namespaces are never introduced by a `package` statement at all — they are
qualified SUB declarations, `sub xyz::foo` (:269) and `sub foo::::::bar`
(:280). A declaration-scanning fix would find `Someother` and `v10`, miss those
two, and reintroduce the same silent drop for a narrower set. Any scan would
also have to cope with `foo::::::bar`, which is a legal name that no
`[\w:]+`-shaped pattern reads correctly.

**Prefer filtering by EXCLUSION** — drop `SoN::*` and the known internals rather
than enumerating what to keep. It is failure-safe in the right direction: a
namespace the filter does not anticipate stays in the wire, which is noisy,
instead of vanishing, which is silent. That is the whole lesson of this defect.
It is the larger change, and it would alter what every existing corpus case
sees, so it needs its own measurement pass — but an inclusion filter over
arbitrary real files cannot be made correct, only made to miss less.

## Why this matters beyond the bug

Both times this bit during the session it produced a UNIFORM wrong result — all
five call forms failing identically — which read as a finding rather than as an
artifact. A filter that removes the subject of the measurement is invisible
precisely when it does the most damage. The lesson is the same one as the
`goto &sub` probe earlier the same day, where the test scaffolding
(`sub { goto &tgt }->()`) translated the outer sub and never reached the
construct under test: **when every case agrees, suspect the harness before
believing the result.**
