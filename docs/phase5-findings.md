# Phase 5: BNF Parser Equivalence Testing - Findings

## Overview
Created comparison tests between the old regex-based BNF parser (`parse_bnf_string()`) and the new semantic actions parser (`parse_with_semantic_actions()`).

## Test Results Summary

### What Works (Equivalent Output)
- ✅ Simple single-rule grammars
- ✅ Multiple rules for same nonterminal
- ✅ Empty productions (epsilon rules)
- ✅ Mixed terminals and nonterminals
- ✅ Full-line comments
- ✅ Both parsers successfully parse `grammar/bnf.bnf`

### Known Limitations

#### 1. Inline Comments Not Supported
**Status**: Documented as TODO test

**Problem**: The hand-coded BNF grammar defines Comment as a full line (`['Line', ['Comment', "\n"]]`), but doesn't handle inline comments after grammar rules.

**Example**:
```bnf
Foo -> 'bar'  # this comment causes parsing to fail
```

**Old Parser Behavior**: Strips comments with regex before parsing (works)
**New Parser Behavior**: Fails to parse (PARSING_STOPPED at ~45%)

**Impact**: Medium - bnf.bnf doesn't use inline comments, so self-hosting works

#### 2. Pattern Reference Expansion
**Status**: Architectural difference requiring semantic action enhancements

**Problem**: The two parsers handle pattern definitions differently:

**Old Parser Approach**:
1. Pre-process: Extract all `%NAME% = /regex/` definitions
2. Build pattern table
3. Parse grammar rules, expanding `%NAME%` references to regex objects
4. Result: Grammar rules contain Regexp objects

**New Parser Approach**:
1. Parse everything in one pass (patterns and rules together)
2. PatternDef lines are parsed but NOT registered
3. PatternRef elements (`%NAME%`) remain as literal strings
4. Result: Grammar rules contain pattern reference strings, not Regexp objects

**Example from grammar/bnf.bnf**:
```bnf
%TERMINAL_CONTENT% = /(?:[^'\\]|\\.)*/u
Terminal -> '\'' %TERMINAL_CONTENT% '\''
```

Old parser produces:
```perl
['Terminal', ["'", qr/(?:[^'\\]|\\.)*/, "'"]]
```

New parser produces:
```perl
['Terminal', ["'", "'", "'", "'"]]  # Just the single quotes
```

**Why This Happens**: Semantic actions need to:
1. Register patterns in a symbol table during PatternDef.evaluate()
2. Look up and expand references during PatternRef.evaluate()
3. Pass the symbol table through the eval context environment

**Impact**: High - pattern references are used extensively in grammar/perl.bnf

## Architecture Insights

### Strength of Semantic Actions Approach
- ✅ Pure parsing - no pre-processing regex hacks
- ✅ Builds Grammar objects during parsing (deforestation)
- ✅ Extensible through evaluate() methods
- ✅ Self-hosting capable (can parse bnf.bnf)

### Current Gaps
- ❌ Pattern reference expansion requires symbol table management
- ❌ Inline comment handling needs grammar extension
- ❌ Not yet feature-complete with regex parser

## Recommendations for Phase 6

### Priority 1: Pattern Reference Support
Add symbol table to semantic evaluation:
1. Extend EvalContext with pattern_table in env
2. Implement PatternDef.evaluate() to register patterns
3. Implement PatternRef.evaluate() to expand to Regexp objects
4. Test with grammar/bnf.bnf pattern definitions

### Priority 2: Inline Comment Support
Extend BNF grammar to handle inline comments:
1. Add optional Comment to GrammarRule production
2. Update semantic actions to ignore comment content
3. Test with inline comment examples

### Priority 3: Full perl.bnf Support
Once patterns work, test on grammar/perl.bnf:
1. Identify additional missing features
2. Extend grammar and semantic actions as needed
3. Achieve full compatibility

## Test File
`t/bnf-parser-equivalence.t` - 78 tests, 7 failures (all pattern-related)

## Success Criteria for Phase 6
- [ ] Pattern references work (7 failing tests pass)
- [ ] Inline comments work (1 TODO test passes)
- [ ] grammar/perl.bnf parses successfully (currently fails at 8%)
- [ ] All grammars produce equivalent output (modulo pattern expansion)
