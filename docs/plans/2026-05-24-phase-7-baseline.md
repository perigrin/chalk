# Phase 7 Pre-Change Test Baseline

**Date:** 2026-05-24
**Branch:** `fixup-audit-baseline` at `357e565f`
**Purpose:** Document pre-Phase-7 test state so post-change regressions are distinguishable from pre-existing failures.

## Green (must stay green through Phase 7)

| Test | Result |
|---|---|
| t/bootstrap/mop/codegen-byte-compat.t | 19/19 |
| t/bootstrap/c-emit-helpers-inheritance.t | 54/54 |
| t/bootstrap/bnf-target-c.t | 178/178 |
| t/bootstrap/c-end-to-end.t | SKIP (chalk.so not built) |
| t/bootstrap/c-data-model-classes.t | 39/39 (38-39 skipped) |
| t/bootstrap/c-build-pipeline.t | 13/13 |
| t/bootstrap/c-runtime-loader.t | 4/4 |
| t/bootstrap/c-boolean-integration.t | 8/8 |
| t/bootstrap/c-build-script.t | SKIP (chalk.so not built) |
| t/bootstrap/xs-build.t | 63/63 |
| t/bootstrap/xs-ast.t | 69/69 |
| t/bootstrap/xs-athx-no-args.t | 7/7 |
| t/bootstrap/xs-isa-inheritance.t | 10/10 |

## Pre-existing failures (Phase 7 must NOT make worse)

| Test | Result | Notes |
|---|---|---|
| t/bootstrap/xs-target-c-smoke.t | Bail out (Build failed, SvTRUE) | C compile error on `SvTRUE`; pre-existing |
| t/bootstrap/c-target-boolean.t | 13/49 failures | C output not matching expectations |
| t/bootstrap/c-direct-cross-class.t | 3/31 failures | (CHALK_SLOW_TESTS=1 not set) |
| t/bootstrap/c-self-call-optimization.t | 4/11 failures | |
| t/bootstrap/c-xs-wrapper-gen.t | Bail (copy chalk.h failed) | chalk.so not built |
| t/bootstrap/c-target-multi-class.t | (timed out backgrounded) | |
| t/bootstrap/c-type-aware-dispatch.t | (timed out backgrounded) | |
| t/bootstrap/xs-int-specialization.t | 4/6 failures | newSVnv not matching |
| t/bootstrap/xs-polymorphic-dispatch.t | 1/60 failure | Component 4 real FilterComposite.pm pipeline |
| t/bootstrap/xs-earley-behavioral.t | (background, suspect failures) | |
| t/bootstrap/xs-earley-full-semiring.t | (background, suspect failures) | |
| t/bootstrap/xs-sub-recursion.t | 1/3 failure | C compile error in typeinferenceactions.c |
| t/bootstrap/xs-pm-parse.t | (background) | |
| t/bootstrap/xs-field-access-runtime.t | 1/9 failure | interpolated string with field variable |
| t/bootstrap/xs-build-perl.t | Bail at 217 (Cannot read Start.pm) | path issue |

## Interpretation

Many C/XS tests depend on `chalk.so` being built via `script/build-chalk-so-generated`. That build is gated by the `generate_c_files` mystery (audit §1e). Tests that compile their own .c files in isolation (xs-build.t, xs-ast.t, etc.) pass; tests that exercise full classes (xs-int-specialization.t, c-target-boolean.t) have substantive failures unrelated to migration mechanics.

Phase 7a should preserve all green tests and not change the pass/fail count of any red tests.
