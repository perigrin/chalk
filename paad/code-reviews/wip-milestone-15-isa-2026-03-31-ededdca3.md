# Agentic Code Review: wip/milestone-15-isa

**Date:** 2026-03-31
**Branch:** wip/milestone-15-isa -> pu
**Commit:** ededdca3686252cc306291cec1a91312e292d0ea
**Files changed:** 14 | **Lines changed:** +3404 / -33
**Diff size category:** Large

## Executive Summary

Milestone 15 delivers six features: XS :isa inheritance, Ruby Slippers error
recovery, integer specialization, type bitsets, generic polymorphic dispatch,
and DFA static table emission. The implementation is architecturally sound
with thorough test coverage (521+ tests across 6 test files). Two confirmed
bugs require fixing before merge: a C operator precedence error in integer
specialization and a crash in EOF Ruby Slippers recovery. Three defense-in-depth
issues (SvROK guard, string escaping, gv_stashpvn escaping) should also be
addressed.

## Critical Issues

### [C1] `_extract_int_val` missing parentheses causes C precedence corruption
- **File:** `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:2447`
- **Bug:** `_extract_int_val` returns raw captured group without parentheses.
  For `sv_2mortal(newSViv(SvIV(pos) + 1))`, returns `SvIV(pos) + 1`.
  When spliced into `newSViv($l_val * $r_val)`, C evaluates as
  `SvIV(pos) + (1 * SvIV(r))` instead of `(SvIV(pos) + 1) * SvIV(r)`.
- **Impact:** Silent arithmetic corruption in chained operations with
  mixed precedence (+/- feeding into *).
- **Suggested fix:** Wrap in parentheses: `return "($1)";`
- **Confidence:** High
- **Found by:** Error Handling (98), Logic (70)

### [C2] `_complete()` crashes with undef `$agenda` during EOF Ruby Slippers
- **File:** `lib/Chalk/Bootstrap/Earley.pm:944-946`
- **Bug:** EOF recovery calls `$self->_complete(..., undef)` passing undef
  for the `$agenda` parameter. Inside `_complete`, `push $agenda->@*, [...]`
  crashes with "Can't use an undefined value as an ARRAY reference" when
  a completion produces a genuinely new item.
- **Impact:** Latent crash on any grammar where EOF recovery triggers a
  completion creating a new (non-merging) chart entry. Current tests pass
  because their simple grammars always merge.
- **Suggested fix:** Pass a local arrayref instead of undef:
  `my @virt_new; $self->_complete(..., \@virt_new);`
  Then process `@virt_new` for further completions.
- **Confidence:** High
- **Found by:** Error Handling (95)

## Important Issues

### [I1] No `SvROK` guard before `SvRV` in polymorphic dispatch
- **File:** `lib/Chalk/Bootstrap/Perl/Target/C.pm:613`
- **Bug:** Generated C does `SvSTASH(SvRV(invocant))` without checking
  `SvROK` first. If invocant is not a reference (undef, plain scalar),
  `SvRV` dereferences invalid memory and segfaults.
- **Impact:** Segfault on non-reference invocant. Project MEMORY.md
  documents this exact pattern as a known hazard.
- **Suggested fix:** Add `SvROK` guard, fall through to `call_method`
  if not a reference.
- **Confidence:** High
- **Found by:** Error Handling (85), Security (68)

### [I2] `_c_string` helper in BNF/Target/C.pm missing control character escaping
- **File:** `lib/Chalk/Bootstrap/BNF/Target/C.pm:19-23`
- **Bug:** Only escapes `\` and `"`. Does not handle `\n`, `\t`, `\r`,
  `\0`, or non-printable bytes. Sibling implementations in EmitHelpers.pm
  and BNF/Target/XS.pm handle all of these.
- **Impact:** Grammar pattern containing raw newline would produce
  invalid C string literal (compilation error).
- **Suggested fix:** Add `\n`, `\t`, `\r`, `\0` escapes and a catch-all
  for non-printable bytes.
- **Confidence:** High
- **Found by:** Security (82), Contract (75), Error Handling (60)

### [I3] `gv_stashpvn` class name not C-string-escaped in polymorphic dispatch
- **File:** `lib/Chalk/Bootstrap/Perl/Target/C.pm:1728`
- **Bug:** Class name interpolated directly into C string literal without
  `_escape_c_string()`. Inconsistent with line 1942 which does escape.
- **Impact:** Class name with backslash or quote would produce invalid C.
- **Suggested fix:** Use `$self->_escape_c_string($class_name)`.
- **Confidence:** Medium
- **Found by:** Security (78), Error Handling (65)

## Suggestions

- `$l_int || $r_int` condition (EmitHelpers.pm:1642) should arguably be `&&` to avoid truncating float operands via `SvIV`. Low practical risk in current codebase but semantically incorrect. (Security 75, Contract 75)
- `_is_int_expr` first regex pattern (EmitHelpers.pm:2434) is unanchored — could false-positive on compound expressions. Consider anchoring or removing (second pattern covers practical cases). (Logic 70, Contract 60)
- Terminal/completion map emission methods (BNF/Target/C.pm:180-349) are near-identical 80-line blocks. Extract a parameterized helper. (Contract 70)
- BNF/Target/C.pm:611 uses `s` flag on delimiter regex; Perl and XS targets don't. Remove `s` for consistency. (Contract 80)
- Comment says "7 CoreItemIndex arrays" but 8 are emitted (BNF/Target/C.pm:119). (Logic 95)
- Type bitset propagation comment says "iterate until stable" but does a single pass (TypeLibrary.pm:70). (Logic 90)

## Review Metadata

- **Agents dispatched:** Logic & Correctness, Error Handling & Edge Cases, Contract & Integration, Security
- **Scope:** 14 changed files + callers/callees one level deep
- **Raw findings:** 18 (across 4 specialists)
- **Verified findings:** 12 (after deduplication and verification)
- **Filtered out:** 6 (low confidence, duplicates, non-actionable)
- **Steering files consulted:** CLAUDE.md, .claude/CLAUDE.md
- **Plan/design docs consulted:** docs/plans/2026-03-31-polymorphic-dispatch-design.md, docs/plans/2026-03-31-dfa-static-tables-design.md
