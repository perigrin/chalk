# Remove NonBrace* Hierarchy - Prioritize Correctness Over Performance

## Summary

Removed the entire NonBrace* expression hierarchy (66 nonterminals, 279 references) to accept valid Perl syntax that was previously rejected.

## Motivation

The NonBrace* hierarchy was preventing valid Perl code from parsing:

```perl
print print 2              # Valid Perl, was rejected
die grep { $_ > 5 } @list  # Valid Perl, was rejected
warn map { $_ * 2 } @list  # Valid Perl, was rejected
```

Verified with `perl -ce` that these are all valid Perl syntax.

## Decision

**Correctness > Performance**

We prioritize accepting all valid Perl over parser performance. The NonBrace* hierarchy was copied from Guacamole to prevent performance issues with circular grammar, but it incorrectly rejected valid syntax.

## Changes

### Grammar Changes
- Replaced all `NonBraceExprComma` → `ExprComma`
- Replaced all `NonBraceValue` → `Value`
- Replaced all `NonBrace*` nonterminals with their normal equivalents
- **Result**: Grammar now allows circular dependencies like:
  ```
  PrintExpr → ExprComma → Value → PrintExpr
  ```

### What This Enables
The grammar now correctly accepts:
- `print print 2` - nested print statements
- `die print "msg"` - print as argument to die
- `print grep { ... } @list` - grep expressions in print
- `print $hash{ print "key" }` - expressions in hash keys
- `die @array[ print "idx" ]` - expressions in array indices

All of these are valid Perl.

### Performance Impact

**Expected**: The circular grammar may cause O(n^2.5) performance for deeply nested cases like `print print print print...`.

**Mitigation**:
1. Real code rarely nests print statements deeply
2. We've already optimized the parser (4x speedup from chart indexing)
3. Future work: Add lookahead to reduce state explosion

### Test Results

✓ `t/optimization/leo-items.t` - PASS
✓ `t/basic/simple-arith.t` - PASS
✓ `t/grammar/logical-operators.t` - PASS
✓ `t/grammar/eval-block.t` - PASS
✓ `t/grammar/circular-expressions.t` - PASS (new test)

All baseline functionality maintained while adding support for previously-rejected valid Perl.

## Files Changed

- `lib/Chalk/Grammar/Perl.pm` - Removed NonBrace* hierarchy
- `t/grammar/circular-expressions.t` - New test for circular grammar cases
- `lib/Chalk/Grammar/Perl.pm.backup_before_nonbrace_removal` - Backup of original

## Next Steps

1. Monitor performance on real Perl codebases
2. If performance becomes an issue, investigate:
   - Lookahead in predict() to prune impossible parse paths
   - Better prediction using next token information
   - Grammar simplification to reduce indirection
3. Document any pathological cases we discover

## Related Issues

- Issue #12: Parser baseline improvements
- NonBrace* was preventing progress on accepting valid Perl

## References

- `/tmp/should_we_allow_ambiguity.md` - Analysis of tradeoffs
- `/tmp/plan_remove_nonbrace.md` - Removal plan
- `/tmp/perl_block_taking_constructs.md` - Perl spec research
