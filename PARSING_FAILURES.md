# Parser Baseline Failures - Deep Analysis

## Summary
5 files fail to parse completely. Here are the exact failure points:

## 1. Grammar/Perl.pm - Line 51 (4.9%)
**Issue:** Trailing comma after array element
```perl
[ 'BlockStatement' => ['Block'], 1.0 ],   # Bare blocks
,    # Comments can appear in block contexts
```
**Problem:** Standalone comma on line - likely a syntax error in the grammar file itself
**Fix:** This is actually a bug in the grammar source code (trailing comma without preceding element)

## 2. Parser.pm - Line 150 (32.8%)
**Issue:** Regex substitution operator `s{::}{/}g`
```perl
(my $file = $preprocessor_class) =~ s{::}{/}g;
```
**Problem:** Parser doesn't recognize `s{pattern}{replacement}flags` regex syntax
**Solution:** Need to add regex substitution patterns to grammar

## 3. Heredoc.pm - Line 82 (38.9%)
**Issue:** Hash ref in push statement
```perl
push @heredocs, {
    delimiter => $delimiter,
    ...
```
**Problem:** Grammar may not be properly parsing hash ref as list element
**Solution:** This should already work with current grammar - need to investigate why it fails

## 4. Composite.pm - Line 53 (51.8%)
**Issue:** `+=` compound assignment operator
```perl
$total += $elem->score if $elem->can('score');
```
**Problem:** `+=` is in OpAssign regex but may not match correctly
**Solution:** Verify OpAssign pattern includes `+=`

## 5. SPPF.pm - Line 189 (59.1%)
**Issue:** Method call with arrow chain
```perl
my $result = $composite->multiply($other->composite);
```
**Problem:** This is the arrow-in-parameter bug from issue #59
**Solution:** Already documented; will require grammar restructure

## Priority Order

1. **CRITICAL - Grammar/Perl.pm syntax error**: Fix the trailing comma bug
2. **HIGH - Regex substitution**: Add `s///` and `s{}{}` patterns
3. **MEDIUM - Compound assignment**: Verify `+=` works
4. **LOW - Hash ref in push**: Investigate why existing grammar fails
5. **DEFER - Arrow in parameter**: Already tracked in issue #59
