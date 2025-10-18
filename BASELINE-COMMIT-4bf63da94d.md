# Test Baseline Report: Commit 4bf63da94d

**Commit:** 4bf63da94d - "Replace Chalk::Preprocessor::Heredoc with HeredocV2 throughout codebase"
**Date:** 2025-10-17
**Branch:** fix-issue-12-parser-baseline
**Purpose:** Establish baseline test results BEFORE grammar reduction changes (commit 4b09b7bfa9)

---

## Executive Summary

This baseline was established to compare test results before and after the grammar pruning work in commit 4b09b7bfa9 ("WIP: pruning the grammar").

### Overall Test Results

| Category | Total | Pass | Fail | Pass Rate | Status |
|----------|-------|------|------|-----------|--------|
| Baseline Parser - perl-tests/base/ | 9 | 9 | 0 | 100% | ✅ PASS |
| Baseline Parser - t/ files | 52 | 21 | 31 | 40.4% | ⚠️ PARTIAL |
| Baseline Parser - lib/ files | 11 | 3 | - | - | ⏱️ TIMEOUT |
| Parser Infrastructure | 10 | 6 | 4 | 60% | ⚠️ PARTIAL |
| Grammar Tests | 16 | 15 | 1 | 93.8% | ✅ MOSTLY PASS |
| Syntax-Specific Tests | 12 | 12 | 0 | 100% | ✅ PASS |
| Self-Hosting | 1 | 1 | 0 | 100% | ✅ PASS |
| Performance (num.t bisect) | 7 | 5 | 2 | 71.4% | ⚠️ PARTIAL |

---

## Detailed Test Results

### 1. Baseline Parser Tests

#### 1.1 perl-tests/base/ (100% Success) ✅

All 9 core Perl test files parse successfully:

1. ✅ cond.t - parsed successfully
2. ✅ if.t - parsed successfully
3. ✅ lex.t - parsed successfully
4. ✅ num.t - parsed successfully
5. ✅ pat.t - parsed successfully
6. ✅ rs.t - parsed successfully
7. ✅ term.t - parsed successfully
8. ✅ translate.t - parsed successfully
9. ✅ while.t - parsed successfully

**Success rate: 100.0%**

#### 1.2 t/ Test Files (40.4% Success) ⚠️

**Passing (21 files):**
- array-length-syntax.t
- bare-regex-statement.t
- c-style-for-loop.t
- eval-string-vs-block.t
- grammar/begin-block.t
- grammar/caret-variables-braces.t
- grammar/circular-expressions.t
- grammar/eval-block.t
- grammar/logical-operators.t
- grammar/open-expressions.t
- grammar/special-variables.t
- grammar/statement-modifiers-core.t
- heredoc-backslash-quoted.t
- multiline-strings.t
- numeric-expressions.t
- performance-bisect.t
- quote-in-comment.t
- quote-operators-alt-delimiters.t
- quote-operators-multiline.t
- substitution-operator.t
- unless-else-parsing.t

**Failing (31 files):**

Most failures are in parser infrastructure tests, which are expected as they test the parser itself:

- basic/01-simple.t (32.8% parsed)
- basic/empty-args.t (11.3% parsed)
- basic/simple-arith.t (32.6% parsed)
- basic/zero-token-fix.t (18.4% parsed)
- cli/app-options.t (12.3% parsed)
- grammar/chalk-complete-grammar.t (3.4% parsed)
- grammar/guacamole-nullable.t (4.3% parsed)
- grammar/guacamole-patterns.t (3.8% parsed)
- grammar/lexeme-support.t (18.3% parsed)
- grammar/modern-perl-syntax.t (5.6% parsed)
- grammar/quote-operators.t (8.4% parsed)
- grammar/statement-modifiers.t (31.7% parsed)
- grammar/zero-length-matches.t (8.1% parsed)
- integration/rs-patterns.t (39.6% parsed)
- optimization/leo-items.t (25.6% parsed)
- parser/02-parser-grammars.t (4.9% parsed)
- parser/ambiguous-baseline.t (7.8% parsed)
- parser/augmented.t (22.6% parsed)
- parser/aycock-horspool-left-recursion.t (3.1% parsed)
- parser/boolean-semiring.t (4.9% parsed)
- parser/generalized.t (23.0% parsed)
- parser/position-semiring.t (8.2% parsed)
- parser/sppf-position.t (4.4% parsed)
- parser/sppf-viterbi.t (6.3% parsed)
- parser/with-preprocessor.t (10.5% parsed)
- preprocessor/heredoc.t (3.6% parsed)
- self-hosting.t (37.6% parsed)
- semiring/composite.t (3.9% parsed)
- semiring/sppf.t (4.4% parsed)
- semiring/viterbi.t (6.2% parsed)
- validation/perl-test-files.t (49.0% parsed)

**Note:** These are "baseline" tests that check if files parse, not functional tests. Many of these files contain complex parser infrastructure code that may not be fully parseable yet.

#### 1.3 lib/ Files (Partial - Timeout) ⏱️

Testing 11 .pm files in lib/:

**Passing (3 files before timeout):**
1. ✅ Chalk.pm - parsed successfully
2. ✅ Chalk/Base.pm - parsed successfully
3. ✅ Chalk/Grammar.pm - parsed successfully

**Timeout:** Test timed out after 10 minutes while parsing lib/Chalk/Grammar/Perl.pm (reached position 59626 of 59633 = 100.0% but didn't complete)

The test appears to hang on the largest file (Chalk/Grammar/Perl.pm), likely due to the complexity of parsing a large grammar definition.

---

### 2. Parser Infrastructure Tests (t/parser/*.t)

**Results:** 10 tests, 6 pass, 4 fail (60% pass rate)

#### Passing Tests (6):
1. ✅ t/parser/02-parser-grammars.t - 56ms
2. ✅ t/parser/ambiguous-baseline.t - 43ms
3. ✅ t/parser/augmented.t - 38ms
4. ✅ t/parser/aycock-horspool-left-recursion.t - 44ms
5. ✅ t/parser/generalized.t - 38ms
6. ✅ t/parser/sppf-viterbi.t - 42ms

#### Failing Tests (4):

**t/parser/boolean-semiring.t** (3 failures, exit code 3)
- Failed tests: 2-4
- Issues:
  - Can't call method "value" on undefined value
  - Can't locate object method "new" via package "Chalk::Semiring::SPPFViterbiSemiring"
  - Parse failures at position 0 (0.0%)

**t/parser/position-semiring.t** (1 failure, exit code 1)
- Failed test: 5 - "Position semiring with simple grammar - complete parse"
- Issue: Can't call method "start_pos" on undefined value
- Parse stopped at position 0 of 2 (0.0%)

**t/parser/sppf-position.t** (7 failures, exit code 7)
- Failed tests: 1-6, 8
- Issues:
  - Can't call method "sppf_node" on undefined value (multiple occurrences)
  - Odd name/value argument for subroutine 'Chalk::Grammar::build_grammar'
  - Parse failures at position 0 (0.0%)

**t/parser/with-preprocessor.t** (1 failure, exit code 1)
- Failed test: 4 - "Parse multiple heredocs with preprocessing"
- Parse stopped at position 34 of 64 (53.1%)

---

### 3. Grammar Tests (t/grammar/*.t)

**Results:** 16 tests, 15 pass, 1 fail (93.8% pass rate)

#### Passing Tests (15):

1. ✅ t/grammar/begin-block.t - 2038ms
2. ✅ t/grammar/chalk-complete-grammar.t - 63ms (with partial parsing warnings)
3. ✅ t/grammar/circular-expressions.t - 1168ms
4. ✅ t/grammar/eval-block.t - 1878ms
5. ✅ t/grammar/guacamole-nullable.t - 45ms
6. ✅ t/grammar/guacamole-patterns.t - 52ms
7. ✅ t/grammar/lexeme-support.t - 38ms
8. ✅ t/grammar/logical-operators.t - 1813ms
9. ✅ t/grammar/modern-perl-syntax.t - 41ms
10. ✅ t/grammar/open-expressions.t - 2655ms
11. ✅ t/grammar/quote-operators.t - 40ms
12. ✅ t/grammar/special-variables.t - 740ms
13. ✅ t/grammar/statement-modifiers-core.t - 635ms
14. ✅ t/grammar/statement-modifiers.t - 1428ms
15. ✅ t/grammar/zero-length-matches.t - 39ms

#### Failing Tests (1):

**t/grammar/caret-variables-braces.t** (1 failure, exit code 1)
- Failed test: 8 - "caret variables with subscripts"
- Failed parsing:
  - `${^TEST[0]}` - stopped at 7 of 11 (63.6%)
  - `${ ^TEST [1] }` - stopped at 9 of 14 (64.3%)
  - `${^TEST{foo}}` - stopped at 7 of 13 (53.8%)
  - `${ ^TEST {bar} }` - stopped at 9 of 16 (56.2%)

---

### 4. Syntax-Specific Tests (t/*.t standalone tests)

**Results:** 12 tests, 12 pass, 0 fail (100% pass rate) ✅

All syntax tests pass:

1. ✅ t/array-length-syntax.t - 249ms
2. ✅ t/bare-regex-statement.t - 620ms
3. ✅ t/c-style-for-loop.t - 745ms
4. ✅ t/eval-string-vs-block.t - 662ms
5. ✅ t/heredoc-backslash-quoted.t - 281ms
6. ✅ t/multiline-strings.t - 224ms
7. ✅ t/numeric-expressions.t - 2299ms
8. ✅ t/quote-in-comment.t - 630ms
9. ✅ t/quote-operators-alt-delimiters.t - 474ms
10. ✅ t/quote-operators-multiline.t - 319ms
11. ✅ t/substitution-operator.t - 295ms
12. ✅ t/unless-else-parsing.t - 19046ms (slow but passes)

**Total time:** 26 wallclock seconds

---

### 5. Self-Hosting Test

**Results:** 1 test, 1 pass (100% pass rate) ✅

**t/self-hosting.t** - PASS
- Successfully parsed Chalk source file (24,724 characters)
- Found 'class' declarations ✅
- Found 'Element' class ✅
- Found 'use' declarations ✅
- Found 'field' declarations ✅
- Found 'method' declarations ✅
- Chalk successfully parses itself with lexemes ✅

---

### 6. Performance Test (t/performance-bisect.t)

**Results:** 7 tests, 5 pass, 2 fail (71.4% pass rate)

Tests incremental parsing of num.t (224 lines total):

**Passing:**
1. ✅ First 10 lines - 0.29s
2. ✅ First 25 lines - 1.31s
3. ✅ First 50 lines - 3.06s
4. ✅ First 75 lines - 5.11s
5. ✅ First 100 lines - 8.14s

**Failing:**
6. ❌ First 150 lines - 12.51s (too slow, threshold: 10s)
7. ❌ First 200 lines - timeout after 15s

**Analysis:** Performance degrades significantly between 100 and 150 lines, indicating a potential exponential parsing complexity issue.

---

## Known Issues

### Critical Issues

1. **lib/ baseline test timeout** - Cannot complete parsing all lib files within 10 minutes
   - Stuck at Chalk/Grammar/Perl.pm (100% position but incomplete)

2. **Parser infrastructure test failures** - Several semiring-based tests fail
   - Undefined method calls on parse results
   - Missing SPPFViterbiSemiring class

3. **Performance degradation** - num.t parsing becomes exponentially slow after ~100 lines
   - Suggests potential ambiguity or inefficient grammar rules

### Minor Issues

1. **Caret variable subscripts** - Cannot parse `${^VAR[...]}` or `${^VAR{...}}` syntax
2. **Wide character warnings** - Multiple tests show "Wide character in warn" messages
3. **Experimental warnings** - "defer is experimental" warnings in some tests

---

## Test Timing Summary

### Fast Tests (< 1s)
- Most parser infrastructure tests: 38-56ms
- Most grammar meta-tests: 38-63ms
- Basic syntax tests: 224-745ms

### Medium Tests (1-3s)
- grammar/circular-expressions.t: 1168ms
- grammar/logical-operators.t: 1813ms
- grammar/eval-block.t: 1878ms
- numeric-expressions.t: 2299ms
- grammar/begin-block.t: 2038ms
- grammar/open-expressions.t: 2655ms

### Slow Tests (> 3s)
- unless-else-parsing.t: 19046ms (19s)
- performance-bisect.t: Variable (0.3s to 15s+ depending on line count)

### Timeout Tests
- baseline-parser-lib.t: > 10 minutes (600s timeout)
- Full test suite (prove t/): > 10 minutes

---

## Comparison to Previous Runs

This is the baseline for commit 4bf63da94d. The next step is to run the same tests on commit 4b09b7bfa9 (grammar pruning) and compare:

### Key Metrics to Compare:
1. Parser infrastructure test pass rate (currently 60%)
2. Grammar test pass rate (currently 93.8%)
3. Syntax test pass rate (currently 100%)
4. Self-hosting test status (currently PASS)
5. Performance test results (currently 71.4% pass)
6. lib/ baseline timeout behavior

---

## Recommendations

1. **Before grammar changes:** The current state shows stable syntax parsing and self-hosting
2. **Watch for regressions:** Any decrease in pass rates or increase in timeouts after grammar pruning
3. **Performance impact:** Track if grammar simplification improves num.t parsing performance
4. **Infrastructure tests:** The 4 failing parser tests may be pre-existing issues unrelated to grammar changes

---

## Test Execution Environment

- **Platform:** macOS Darwin 25.0.0
- **Perl:** 5.42.0 (via plenv)
- **Working directory:** /Users/perigrin/dev/chalk
- **Branch:** fix-issue-12-parser-baseline
- **Date:** 2025-10-17
- **Test command:** `plenv exec prove -Ilib t/`
- **Timeout:** 600s (10 minutes) for individual long-running tests

---

## Appendix: Full Test File List

### All test files in t/:
```
t/array-length-syntax.t
t/bare-regex-statement.t
t/baseline-parser-lib.t
t/baseline-parser-perl-tests-base.t
t/baseline-parser-t.t
t/c-style-for-loop.t
t/eval-string-vs-block.t
t/heredoc-backslash-quoted.t
t/multiline-strings.t
t/numeric-expressions.t
t/performance-bisect.t
t/quote-in-comment.t
t/quote-operators-alt-delimiters.t
t/quote-operators-multiline.t
t/self-hosting.t
t/substitution-operator.t
t/unless-else-parsing.t
```

### All test files in t/parser/:
```
t/parser/02-parser-grammars.t
t/parser/ambiguous-baseline.t
t/parser/augmented.t
t/parser/aycock-horspool-left-recursion.t
t/parser/boolean-semiring.t
t/parser/generalized.t
t/parser/position-semiring.t
t/parser/sppf-position.t
t/parser/sppf-viterbi.t
t/parser/with-preprocessor.t
```

### All test files in t/grammar/:
```
t/grammar/begin-block.t
t/grammar/caret-variables-braces.t
t/grammar/chalk-complete-grammar.t
t/grammar/circular-expressions.t
t/grammar/eval-block.t
t/grammar/guacamole-nullable.t
t/grammar/guacamole-patterns.t
t/grammar/lexeme-support.t
t/grammar/logical-operators.t
t/grammar/modern-perl-syntax.t
t/grammar/open-expressions.t
t/grammar/quote-operators.t
t/grammar/special-variables.t
t/grammar/statement-modifiers-core.t
t/grammar/statement-modifiers.t
t/grammar/zero-length-matches.t
```

---

**End of Baseline Report**
