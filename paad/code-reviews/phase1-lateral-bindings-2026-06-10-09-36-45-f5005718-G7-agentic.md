# Agentic Code Review: phase1-lateral-bindings (G7 host interface + magic-var edges)

**Date:** 2026-06-10 09:36:45
**Branch:** phase1-lateral-bindings -> 9188549a (G7 start)
**Commit reviewed:** b66e76ee; fixes landed at f5005718
**Files changed:** 9 | **Lines changed:** +666 (review diff)
**Diff size category:** Medium

## Executive Summary

G7 core (census-grounded scope: lib/ uses 96 `$N` reads + 28 `%ENV` reads;
zero `@ARGV`/`$0`/`$!`/`open`): two new documented nodes — `RegexCapture(match, n)`
(a zero-copy `{ptr,len}` view via the G6 `_regex_captures` contract) and
`EnvRead(key)` (host C `getenv`) — plus the new `host.md` corpus topic (H1-H3
GREEN, lli==perl). One combined-lens reviewer with runtime probes found **4
findings, all latent** (no in-tree producer triggers them yet), two of which
were probe-confirmed broken-on-first-producer. **All 4 fixed** in f5005718
(TDD; the method-body case was RED with undeclared `@getenv` + duplicate
symbols). Zero regressions: full ir/+corpus/ sweep clean; self-host tier =
the 5 exact known-baseline failures.

## Findings (all FIXED in f5005718)

- **[1] Method-body EnvRead emitted undeclared `@getenv`** (conf 95, latent,
  probe-confirmed): `_need_getenv` missing from the F6 flag-propagation list +
  no post-class re-emit. Fixed (list + the memcmp-pattern re-emit;
  `_strlen_declared` threaded across all three strlen declare sites).
- **[2] EnvRead globals lacked the method symbol prefix** (conf 95, latent,
  probe-confirmed): two method bodies both emitted `@env_key_0` — the exact
  `@rxs_lit`/`@str_const` bug class. Fixed (class/method prefix); pinned by a
  two-method lli test covering [1]+[2].
- **[3] Concat's `len_b+1` rhs copy assumed a NUL after the rhs** (conf 85,
  latent invariant violation, zero observable misbehavior — every current Str
  consumer is length-bounded): wrong for a zero-copy RegexCapture view (the
  byte past the view is the next subject byte). Fixed: copy exactly `len_b`,
  store the NUL explicitly.
- **[4] Missing repr guards** (conf 70, suggestion): RegexCapture/EnvRead now
  die GAP on a non-Str repr annotation.

## Cleared (probe-verified)
Cross-context capture caching (method-body RegexCapture runs clean); the
zero-copy view through the `Str:%.*s` length-path epilogue (mid-subject
captures print exactly len bytes; no strcpy/strcat anywhere in the backend);
prologue ordering for main-graph `_need_getenv`; the strlen double-declare
guard (main-graph EnvRead + class registry = exactly one declare); host.md H1's
unguarded `$1` (lowers fine; failed-match sentinel = crash-free empty view,
documented divergence); TypedInvariant unaffected (new ops unlisted =
unchecked); getenv-lifetime + same-key hash-consing sound (no env writes
modelled); GAP guards (out-of-range `$N`, non-match input) covered.

## Review Metadata
- **Agents dispatched:** 1 combined Logic/Contract/Edge-case reviewer with
  lli+perl runtime probes (the diff is two nodes + two lowering subs — a full
  panel was not warranted; every finding carries probe evidence).
- **Raw findings:** 4; **rejected:** 0; **fixed:** 4.
- **Verified GREEN after fixes:** llvm-regex-capture.t 5/5, llvm-env-read.t
  4/4, llvm-regex-{match,subst}.t 37/37+9/9, host.t 9/9, strings.t (Concat)
  clean, full ir/+corpus/ sweep clean.
- **Plan/docs consulted:** docs/architecture/runtime-free-boundary.md (the G7
  spec), sea-of-nodes-ir.md, the G6 memory ($N contract).
