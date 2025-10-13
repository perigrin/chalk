# Regex Substitution Parsing Issue

## Problem
Parser.pm fails to parse at position 4760 (32.8%) due to regex substitution operator `s|::|/|g` on line 150.

## Current Code (Parser.pm:150)
```perl
(my $file = $preprocessor_class) =~ s|::|/|g;
```

## Attempted Solutions

### 1. Literal String Match
```perl
[ 'QLikeValue' => ['s|::|/|g'] ],
```
**Result:** Causes parser timeout/hang

### 2. Quoted Regex with Character Classes
```perl
[ 'QLikeValue' => [qr/\Qs|\E[^|]+\Q|\E[^|]+\Q|[gimsxoaeludnr]+\E/] ],
```
**Result:** Pattern doesn't match `s|::|/|g` correctly (fails on double colon)

### 3. Non-greedy Wildcards
```perl
[ 'QLikeValue' => [qr/s\|.+?\|.+?\|[gimsxoaeludnr]+/] ],
```
**Result:** Causes exponential parser backtracking and timeout

## Root Cause
Regex substitution operators (`s///`, `s{}{}`, `s|||`) are complex patterns that:
1. Can use various delimiters (/, {}, ||, !!, ##)
2. Pattern and replacement can contain nearly any characters
3. Non-greedy matching (`.+?`) causes severe backtracking in Earley parser
4. Greedy character classes like `[^|]*` create ambiguity with nested braces/delimiters

## Workaround Applied
Changed Parser.pm to use a different delimiter that's already supported:
```perl
# Before: s{::}{/}g
# After:  s|::|/|g
```

Both are valid Perl syntax, but neither parses correctly yet.

## Proposed Solutions

### Option 1: Add specific literal patterns
Add commonly-used substitution patterns as literal strings:
```perl
[ 'QLikeValue' => ['s{::}{/}g'] ],
[ 'QLikeValue' => ['s|::|/|g'] ],
[ 'QLikeValue' => ['s/::/\//g'] ],
```
**Pros:** Fast, no backtracking
**Cons:** Not general, requires explicit pattern for each usage

### Option 2: Use possessive quantifiers
```perl
[ 'QLikeValue' => [qr/s\|(?:[^|]++)\|(?:[^|]*+)\|[gimsxoaeludnr]*/] ],
```
**Pros:** More general, prevents backtracking
**Cons:** Perl 5.10+ feature, more complex

### Option 3: Create separate terminal for substitutions
Make substitution a separate lexical category instead of treating it as QLikeValue:
```perl
[ 'SubstitutionOp' => [qr/s\|[^|]+\|[^|]*\|[a-z]*/] ],  # Start simple
[ 'Value' => ['SubstitutionOp'], 0.3 ],
```

### Option 4: Defer to future grammar restructure
Document as known limitation, defer fix until broader grammar improvements (see issue #59 for arrow-in-parameter which suggests grammar restructure).

## Test Case
```perl
# File: test_regex_substitution.pl
use 5.42.0;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::Perl;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @tests = (
    's|::|/|g',
    's{::}{/}g',
    's/::/\//g',
    's/foo/bar/',
    's!pattern!replacement!gi',
);

for my $code (@tests) {
    my $result = $parser->parse_string($code);
    printf "%-20s %s\n", $code, $result ? "PASS" : "FAIL";
}
```

## Impact
- Parser.pm stuck at 32.8% parsing
- Blocks improvement of baseline parser percentage
- Medium priority (workarounds exist: use `tr///` or split into separate statements)

## Related Issues
- #59 - Arrow-in-parameter parsing (suggests broader grammar restructure)
- #12 - Parser baseline improvement (this blocks progress)

## Recommendation
Start with **Option 1** (specific literals) for immediate needs, then explore **Option 3** (separate terminal) as part of broader grammar improvements.
