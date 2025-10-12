# Multi-line String Literal Investigation

## Summary
Multi-line string literals ARE working correctly in the Chalk parser. The issue preventing lex.t from parsing completely is NOT related to multi-line string parsing.

## Findings

### Multi-line Strings Work Correctly
Confirmed that the grammar's QuotedString regex correctly matches multi-line strings:
- Tested eval 'while (0) { ... }' spanning multiple lines - WORKS
- Character class [^'\\] includes newlines by default in Perl
- Lines 1-26 of lex.t parse successfully (includes the multi-line eval string)

### Actual Parsing Progress
- Lines 1-21: PASS (before multi-line eval)
- Lines 1-22: FAIL (incomplete multi-line string - expected)
- Lines 1-26: PASS (complete multi-line string)  
- Lines 1-44: PASS
- Lines 1-45: FAIL (nested heredoc issue)
- Full file: FAIL (nested heredoc issue)

### Root Cause of lex.t Failure
Line 45 contains a heredoc inside eval that contains nested heredocs.
The Chalk::Preprocessor::Heredoc converts the outer heredoc but leaves the inner heredocs unchanged.
The grammar doesn't support heredocs directly, so these nested heredocs cause parsing to fail.

## Changes Made
1. Updated check_base_tests.pl to use Chalk::Preprocessor::Heredoc
   - This ensures consistency with the test harness

## Next Steps (if needed)
To make lex.t parse completely, one of these approaches is needed:
1. Enhance the heredoc preprocessor to recursively process nested heredocs
2. Add heredoc support directly to the grammar
3. Mark nested heredocs as a known limitation

The multi-line string parsing is working correctly and requires no fixes.
