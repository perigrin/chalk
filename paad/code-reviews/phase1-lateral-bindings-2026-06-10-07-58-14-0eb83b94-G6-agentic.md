# Agentic Code Review: phase1-lateral-bindings (G6 regex sub-compiler)

**Date:** 2026-06-10 07:58:14
**Branch:** phase1-lateral-bindings -> b1a6dcea (G6 start)
**Commit reviewed:** 5ed97f08 (T0-T4 + qr// + s/// + docs); fixes landed at 0eb83b94
**Files changed:** 7 | **Lines changed:** +1437 / -12 (review diff)
**Diff size category:** Large

## Executive Summary

G6 builds the regex sub-compiler: literal patterns lower to runtime-free LLVM
matchers (slide loop + position-threaded recognizer; greedy quantifiers with
backoff backtracking as runtime loop structure), capture groups as inline SSA
offset pairs (no `%MatchResult` struct per the scope decision), s/// as match +
splice with `$N` replacement segments, and qr// as `Constant(const_type=regex)`
+ the existing `Match` BinOp (no new node class). regex.md R1-R6 all GREEN,
lli==perl, libperl-free; zero regressions (ir/+corpus/ sweep clean; self-host
tier shows only the 5 exact known-baseline failures). Three specialists
(regex-semantics-vs-perl with oracle probes, error-handling, contract/
integration) found **1 LIVE silent-miscompile** (escaped alphanumerics
literalized — lib/ uses `s/\t/`, `\bRETVAL\b`, `/\A...\z/`) plus 8
important-latent semantic/guard gaps and 4 suggestions.

**DISPOSITION (2026-06-10): ALL findings fixed in commit 0eb83b94** (TDD, RED
first), except features explicitly deferred to the fast-follow issue
`019eb073` (alternation, NotMatch, assertion escapes, flags, `\Q\E`, `\G`,
`/g`, non-greedy, backrefs — all die as explicit GAPs).

## Findings (all fixed unless noted)

### LIVE
- **[F1] Escaped alphanumerics silently literal** (conf 95+85, 2 agents):
  `\t`→letter t, `\b`→letter b, `\A`→A, `\xHH`→"xHH". lib/ uses `s/\t/`,
  `\bRETVAL\b`, `/\A-?\d+\z/`, `[^\x20-\x7E]`. **Fixed:** byte-escape table
  (`\t\n\r\f\a\e\0` + `\xHH`) at top level, inside classes, and for range
  endpoints; assertion/unknown alphanumeric escapes die GAP; replacement is a
  cooked-bytes contract (alphanumeric escapes die GAP).

### Important (latent)
- **[F2] `$` anchor strict pos==len** (conf 90): perl's `$` matches before a
  final newline. **Fixed** (recursion base + empty-pattern path, guarded load).
- **[F3] `s/$/X/` spliced at offset 0** (conf 95): empty-anchored pattern
  reported m0s/m0e=0. **Fixed:** effective-end position (len, or len-1 before a
  trailing newline).
- **[F4] match-side flags silently ignored** (conf 90+95, 2 agents): `/i`
  compiled case-sensitive. **Fixed:** one GAP gate in `_compile_regex_pattern`.
- **[F-mid] mid-pattern `^`/`$` literalized** (conf 90, 2 agents): perl
  assertions. **Fixed:** GAP die.
- **[F6] reversed class ranges silently never-match** (conf 95): perl dies at
  compile. **Fixed:** GAP die on lo>hi.
- **[F5] `$10` misparse as `$1."0"`** (conf 85+90, 2 agents). **Fixed:** GAP die
  on multi-digit refs.
- **[F7] trailing `\\$` demoted the anchor** (conf 85, 2 agents): single-char
  lookbehind. **Fixed:** backslash-run parity.
- **[C2] `@rxs_lit_N` missed the method-body symbol prefix** (conf 85): the
  exact I1 bug class. **Fixed** (+ pinned by a two-method s/// lli test).
- **[F8] newline in a Str constant broke the .ll** (pre-existing, Constant
  comment text). **Fixed:** comment sanitized.

### Suggestions (all addressed)
- NotMatch (`!~`) untracked deferral → recorded in `019eb073` + the doc list.
- Stale all-GAP section comments in regex.t → rewritten.
- Match string-rhs die message misattribution → message distinguishes
  "unwired but statically resolvable" from "needs a matcher-fn ABI".

## Cleared by the review (verified clean, notable)
Leftmost-first match landing matches perl (slide + greedy-backoff order);
empty-match splice arithmetic; `\s` definition (incl. `\cK` per modern perl);
`[]]`/`[a-]`/`[-a]` class edge cases; backoff-loop signedness (`c` → -1 with
min=0); `$&` use in the `{n,m}` parser; capture SSA dominance + backtrack
consistency; `_regex_captures` cache-hit consistency + hash-cons sharing
(probed); `:Regex` repr through TypedInvariant + a regex Constant wired as a
data input dies loudly; `@rxs_lit`/`@str_const` shared-index naming;
empty-pattern `'0'` sentinels + `$lbl_pre` phi correctness (probed).

## Review Metadata
- **Agents dispatched:** Regex-semantics-vs-perl (with lli+perl oracle
  probes), Error Handling & Edge Cases, Contract & Integration. (Verification
  was performed by the specialists themselves via runtime probes — every
  semantic finding carries a reproducing perl-vs-G6 example.)
- **Raw findings:** 13 (9 important-or-live + 4 suggestions); **0 rejected**.
- **Verified GREEN after fixes:** llvm-regex-match.t 37/37, llvm-regex-subst.t
  9/9, regex.t 15/15, full ir/+corpus/ sweep clean, self-host tier = the 5
  exact known-baseline failures only.
- **Steering files consulted:** CLAUDE.md (project + global), MEMORY.md.
- **Plan/design docs consulted:** g6_regex_subcompiler memory (the spike
  report + feature ladder), docs/architecture/sea-of-nodes-ir.md.
