# Agentic Code Review: issue-710-context-annotation-helpers

**Date:** 2026-04-12
**Branch:** issue-710-context-annotation-helpers -> pu
**Commit (pre-fix):** d46f8f76
**Commit (post-fix):** 9a9a0008
**Files changed:** 2 | **Lines changed:** +144 / -0 (pre-fix)
**Diff size category:** Small

## Executive Summary

Small additive commit adding two annotation helpers to Earley.pm as
scaffolding for milestone 18. Review dispatched three focused agents
(bug-hunt, alignment, simplify) since surface area was minimal. Two
real findings confirmed and fixed; one agent-flagged redundancy
(matched_text) kept as spec-required.

## Critical Issues

### [C1] predicted hashref stored by reference (aliasing risk)
- **File:** `lib/Chalk/Bootstrap/Earley.pm:134`
- **Bug:** `_make_scan_context` stored `$predicted_at` by reference. The
  parser's `%predicted_at` (Earley.pm:554) is rebuilt per position and
  mutated by `_predict` (Earley.pm:1160). Contexts aliasing the live
  hash would observe post-reification mutations, breaking the comonad
  invariant that annotations are immutable snapshots.
- **Impact:** Would corrupt semiring dispatch in #711 once helpers are
  wired to parser call sites.
- **Fix:** Shallow-copy `{ $predicted_at->%* }` at reification time.
- **Confidence:** High (verified at call sites)
- **Status:** Fixed in 9a9a0008

## Important Issues

### [I1] Context rule field left undef
- **File:** `lib/Chalk/Bootstrap/Earley.pm:127-152`
- **Bug:** Both helpers stuffed rule_name into `annotations` but left
  the Context's dedicated `rule :param` field at its undef default.
- **Impact:** `$ctx->rule()` is consumed in 15+ places (SemanticAction,
  Perl/Actions). When #711/#712 wire these helpers in, all those
  consumers would see undef instead of the rule name.
- **Fix:** Pass `rule => $rule_name` in both constructors.
- **Confidence:** High (verified by grep of consumers)
- **Status:** Fixed in 9a9a0008

## Suggestions

- matched_text duplication between `focus` and `annotations.matched_text`
  was flagged but retained — issue #710's Component Overview explicitly
  lists matched_text as an annotation. Duplication is spec-required.

## Plan Alignment

Issue #710 acceptance criteria fully met:
- **Implemented:** All 4 tasks (scan helper, complete helper,
  hash-consing uniqueness test, regression verification)
- **Not yet implemented:** Semiring interface changes (deferred to
  #711/#712/#713 by design — "No semiring interfaces changed yet")
- **Deviations:** None

## Review Metadata

- **Agents dispatched:** Bug-hunt (combined logic/error/contract/
  concurrency/security), Alignment, Simplify
- **Scope:** 2 changed files + Context.pm + Earley.pm call sites for
  predicted_at (lines 554-1225)
- **Raw findings:** 3 + alignment/simplify notes
- **Verified findings:** 2 Critical/Important + 1 retained-as-Suggestion
- **Filtered out:** 0
- **Steering files consulted:** CLAUDE.md (project), user CLAUDE.md
- **Plan/design docs consulted:** Issue #710 spec, MEMORY.md
  milestone17_status
