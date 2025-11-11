# Property-Based Testing Evaluation for Chalk

## Executive Summary

**Recommendation**: Property-based testing would provide significant value for Chalk, particularly for parser, IR optimizer, and interpreter components. However, implementation should be **deferred to Phase 5** due to:
- Current test suite quality is already high (93% from audit)
- Requires additional dependencies (Test::LectroTest or similar)
- Better as targeted enhancement after core functionality stabilizes
- Would benefit from dedicated focus rather than rushed Phase 4 addition

**Priority**: Medium (valuable but not urgent)

---

## What is Property-Based Testing?

Instead of writing specific test cases, property-based testing:
1. Defines **properties** that should always hold (invariants)
2. Generates **random inputs** to test those properties
3. Automatically finds **edge cases** that break the properties
4. **Shrinks failing cases** to minimal reproducible examples

### Example: Parser Property
**Property**: "Any valid syntax that parses should round-trip correctly"
```perl
# Traditional test
ok($parser->parse("1 + 2"), "parses 1 + 2");
ok($parser->parse("(a * b) + c"), "parses (a * b) + c");

# Property-based test (conceptual)
property "valid syntax round-trips" => sub {
    my $expr = generate_valid_expression();  # Random valid syntax
    my $ast = $parser->parse($expr);
    my $reconstructed = $ast->to_string();
    my $ast2 = $parser->parse($reconstructed);
    is_deeply($ast, $ast2, "round-trip preserves AST");
};
```

---

## Perl Property-Based Testing Options

### 1. Test::LectroTest (Mature, Unmaintained)
**Status**: Last updated 2005, still works with modern Perl
**Pros**: Battle-tested, good documentation
**Cons**: No active maintenance, may have compatibility issues

### 2. Test::QuickCheck (Port of Haskell QuickCheck)
**Status**: Available on CPAN, sporadically maintained
**Pros**: Familiar API for Haskell developers
**Cons**: Less Perl-idiomatic, limited examples

### 3. Roll Our Own (Lightweight)
**Status**: Custom implementation
**Pros**: Tailored to Chalk's needs, no external deps beyond Test::More
**Cons**: Requires development time, less feature-complete

**Recommendation**: Start with **Test::LectroTest** for evaluation, consider custom solution if needed.

---

## Chalk Components: Property-Based Testing Opportunities

### HIGH VALUE: Parser/Grammar

#### Properties to Test

1. **Round-Trip Property**
   - Property: `parse(unparse(ast)) == ast`
   - Benefit: Catches parser/unparsing inconsistencies
   - Generator: Valid Chalk syntax
   - Effort: High (need syntax generator)

2. **Ambiguity Detection**
   - Property: `parse(input)` returns exactly one parse tree OR correctly reports ambiguity
   - Benefit: Ensures grammar determinism
   - Generator: Random token sequences
   - Effort: Medium

3. **Error Recovery**
   - Property: Parser never crashes on invalid input
   - Benefit: Robustness against malformed code
   - Generator: Random/malformed syntax
   - Effort: Low (already generating invalid syntax)

**Priority**: HIGH
**Estimated ROI**: Very High - would catch grammar inconsistencies

---

### HIGH VALUE: IR Optimizer

#### Properties to Test

1. **Semantic Preservation**
   - Property: `execute(optimize(graph)) == execute(graph)`
   - Benefit: Ensures optimizations don't change program behavior
   - Generator: Random IR graphs
   - Effort: Medium (need IR generator)

2. **Idempotence**
   - Property: `optimize(optimize(graph)) == optimize(graph)`
   - Benefit: Ensures optimizer reaches fixpoint
   - Generator: Random IR graphs
   - Effort: Low (reuse IR generator)

3. **Peephole Correctness**
   - Property: `peephole(node)` produces equivalent or better node
   - Benefit: Validates individual optimization rules
   - Generator: Random IR nodes
   - Effort: Low

**Priority**: HIGH
**Estimated ROI**: Very High - critical for correctness

**Example**:
```perl
# Peephole idempotence
property "peephole is idempotent" => sub {
    my $graph = generate_ir_graph();
    my $opt1 = peephole_optimize($graph);
    my $opt2 = peephole_optimize($opt1);
    is_deeply($opt1, $opt2, "second optimization doesn't change result");
};
```

---

### MEDIUM VALUE: Interpreter

#### Properties to Test

1. **Determinism**
   - Property: `execute(graph)` always returns same result for same graph
   - Benefit: Ensures no hidden state/randomness
   - Generator: Deterministic IR graphs
   - Effort: Low

2. **Memory Safety**
   - Property: Heap operations never access invalid addresses
   - Benefit: Catches memory corruption bugs
   - Generator: Random heap allocation patterns
   - Effort: Medium

3. **Type Safety**
   - Property: Operations on typed values don't violate type constraints
   - Benefit: Validates type system enforcement
   - Generator: Typed IR graphs
   - Effort: High (need type-aware generator)

**Priority**: MEDIUM
**Estimated ROI**: Medium - most bugs caught by unit tests

---

### LOW VALUE: Semantic Actions

#### Properties to Test

1. **Action Composability**
   - Property: Combining semantic actions produces valid semantics
   - Benefit: Validates semantic algebra
   - Generator: Random action combinations
   - Effort: High (complex domain)

**Priority**: LOW
**Estimated ROI**: Low - semantic actions are well-tested

---

## Implementation Roadmap

### Phase 1: Infrastructure (2-4 hours)
1. Add Test::LectroTest dependency
2. Create generator utilities:
   - `Chalk::Test::Gen::Expr` - Random valid expressions
   - `Chalk::Test::Gen::IR` - Random IR graphs
3. Write example property test for simple component
4. Document property-testing patterns

### Phase 2: Parser Properties (4-6 hours)
1. Implement round-trip property for expressions
2. Implement ambiguity detection property
3. Implement error recovery property
4. Run on CI with reduced iterations for speed

### Phase 3: Optimizer Properties (4-6 hours)
1. Implement semantic preservation property
2. Implement idempotence property
3. Implement peephole correctness properties
4. Create differential testing against known-good optimizations

### Phase 4: Interpreter Properties (2-3 hours)
1. Implement determinism property
2. Implement memory safety property
3. Document limitations and future work

**Total Effort**: 12-19 hours
**Expected Bugs Found**: 3-10 real issues (based on property-testing literature)

---

## Specific Recommendations for Chalk

### 1. Start with Optimizer Testing
**Rationale**:
- Most critical for correctness
- Smaller state space than parser
- Clear properties (semantic preservation, idempotence)
- Existing differential test pattern in cek-compiler-validation.t

**First Property Test**:
```perl
# t/property/optimizer-semantic-preservation.t
use Test::LectroTest;
use Chalk::IR::Graph;
use Chalk::Interpreter::CEKDataflow;
use Chalk::Optimizer::Peephole;

property "peephole preserves semantics",
    graph => IRGraph(max_nodes => 10),
    sub {
        my $graph = shift;

        my $original_result = execute($graph);
        my $optimized = peephole_optimize(clone($graph));
        my $optimized_result = execute($optimized);

        $original_result == $optimized_result;
    };
```

### 2. Create Lightweight Generators
Don't try to generate all possible IR graphs - start with constrained generators:
- Arithmetic-only graphs (constants + Add/Mul/Sub/Div)
- No control flow initially
- Bounded depth/size

### 3. Use Existing Test Infrastructure
Leverage `Test::Chalk::Grammar` and existing test helpers.

### 4. Document Properties as Specifications
Property tests serve dual purpose:
- Tests that find bugs
- Executable specifications of system invariants

---

## Risks and Limitations

### Risks

1. **False Positives**: Generated cases may violate implicit assumptions
   - **Mitigation**: Careful generator constraints

2. **Slow Tests**: Property tests with many iterations slow CI
   - **Mitigation**: Reduce iterations in CI, full runs nightly

3. **Complex Generators**: IR/AST generators are non-trivial
   - **Mitigation**: Start simple, incrementally add complexity

4. **Dependency Concerns**: Test::LectroTest unmaintained
   - **Mitigation**: Plan migration path to custom solution

### Limitations

1. **Not a Replacement**: Property tests complement, don't replace unit tests
2. **Grammar Complexity**: Chalk grammar too complex for naive generation
3. **Debugging**: Random failures harder to debug than unit test failures
4. **Coverage Gaps**: Properties must be carefully chosen to be meaningful

---

## Decision Matrix

| Component | Value | Effort | ROI | Priority | Recommendation |
|-----------|-------|--------|-----|----------|----------------|
| Parser Round-Trip | High | High | Medium | P2 | Defer to Phase 5 |
| Parser Robustness | High | Low | High | P1 | **Start Here** (if doing) |
| Optimizer Semantics | High | Medium | High | P1 | **Start Here** |
| Optimizer Idempotence | High | Low | High | P1 | **Start Here** |
| Interpreter Determinism | Medium | Low | Medium | P2 | Phase 5 |
| Interpreter Memory | Medium | Medium | Low | P3 | Future |
| Type System | Low | High | Low | P4 | Not worth it |

---

## Conclusion

**For Phase 4**: Document this evaluation, defer implementation

**For Phase 5** (Future Sprint):
1. Add Test::LectroTest dependency
2. Implement 3 high-priority properties:
   - Optimizer semantic preservation
   - Optimizer idempotence
   - Parser robustness (never crash)
3. Create IR graph generator (arithmetic only)
4. Run property tests nightly (not every commit)
5. Document findings and expand incrementally

**Expected Outcome**:
- 5-10 new bugs discovered
- Better understanding of system invariants
- Executable specifications for critical properties
- Foundation for future property-based testing

**Alternative**: If property-based testing feels premature, focus Phase 5 on:
- Completing remaining minimal test expansions
- Adding more negative tests to grammar
- Differential testing between interpreter and compiled code

---

**Status**: Evaluation complete, ready for discussion
**Next Steps**: Review with team, prioritize for Phase 5
**Dependencies**: None for evaluation, Test::LectroTest for implementation
