# Differential Testing Pattern Analysis

## Overview

Differential testing compares the output of two implementations of the same specification to find bugs. Chalk's `t/interpreter/cek-compiler-validation.t` provides an excellent template for this approach.

**Pattern**: Compare Chalk's CEK interpreter execution against Perl 5.42.0's native execution

**Pass Rate**: 89.7% (35/39 tests) - failures are IR Builder bugs, not CEK bugs

---

## Core Pattern: test_cek_vs_perl()

### Step 1: Compile to IR
```perl
sub compile_chalk {
    my ($code) = @_;

    # Parse Chalk code
    my $builder = Chalk::IR::Builder->new();
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => $grammar,
        env => { ir_builder => $builder }
    );
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $parse_result = $parser->parse_string($code);
    return unless $parse_result;

    # Get IR graph
    my $graph = $builder->graph;

    # Prune to winning parse (handles ambiguous grammars)
    if ($parse_result->can('context')) {
        my $winning_node = $parse_result->context->focus;
        $graph->prune_to_reachable($winning_node->id);
    }

    # Optimize with GVN
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    return $gvn_result->{graph};
}
```

### Step 2: Execute with Reference Implementation
```perl
sub execute_perl {
    my ($code) = @_;

    # Wrap code so 'return' works
    my $wrapped = "use v5.42;\nsub main { $code }\nmy \$result = main();\nprint \$result;\n";

    # Create temp file and execute with Perl 5.42.0
    my $tmpfile = File::Temp->new(SUFFIX => '.pl');
    print $tmpfile $wrapped;
    close $tmpfile;

    my $output = `PLENV_VERSION=5.42.0 plenv exec perl $tmpfile 2>&1`;
    chomp $output;

    # Parse numeric output
    if ($output =~ /^-?\d+(?:\.\d+)?$/) {
        return 0 + $output;  # Convert to number
    }

    return $output;
}
```

### Step 3: Execute with System Under Test
```perl
sub test_cek_vs_perl {
    my ($code, $test_name) = @_;

    # Compile to IR
    my $graph = compile_chalk($code);
    ok($graph, "$test_name: code compiles to IR");
    return unless $graph;

    # Execute with CEK interpreter
    my $cek_result = eval {
        my $cek_interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
        $cek_interp->execute();
    };
    if ($@) {
        fail("$test_name: CEK interpreter failed: $@");
        return;
    }

    # Execute with Perl (reference)
    my $perl_result = execute_perl($code);

    # Compare results
    is($cek_result, $perl_result, "$test_name: CEK matches Perl execution");
}
```

### Step 4: Test Cases
```perl
# Simple cases
test_cek_vs_perl('return 42;', 'Constant return');
test_cek_vs_perl('return 3 + 5;', 'Addition');
test_cek_vs_perl('my $x = 5; return $x + 3;', 'Variable with addition');

# Complex cases with known issues
TODO: {
    local $TODO = "IR Builder generates wrong precedence (issue #XXX)";
    test_cek_vs_perl('return 3 + 5 * 2;', 'Operator precedence');
}
```

---

## Key Design Decisions

### 1. Test Granularity
**Decision**: Each test case is 2 assertions (compilation + execution match)
**Rationale**: Separates compilation failures from execution mismatches
**Benefit**: Clear diagnosis of where failures occur

### 2. Reference Implementation Choice
**Decision**: Use Perl 5.42.0 as ground truth
**Rationale**:
- Chalk targets Perl compatibility
- Native Perl is battle-tested
- Easy to execute side-by-side
**Limitation**: Only tests Perl-compatible features

### 3. Temp File Execution
**Decision**: Write Perl code to temp file rather than eval
**Rationale**:
- Avoids string interpolation issues
- Matches real execution environment
- Easier to debug (can inspect temp file)
**Tradeoff**: Slower than eval, but more reliable

### 4. Code Wrapping Strategy
**Decision**: Wrap test code in `sub main { }` function
**Rationale**:
- Makes `return` statement work correctly
- Creates consistent execution context
- Matches how Chalk will execute code blocks
**Alternative**: Could use `do` blocks, but less flexible

### 5. Output Parsing
**Decision**: Parse stdout for numeric results
**Rationale**:
- Simple protocol
- Works across process boundary
- Easy to extend for other types
**Limitation**: Only handles numeric and string results currently

---

## Pattern Variations for Other Components

### Variation 1: Parser Differential Testing

Compare Chalk parser against perl5 parser (via PPI or Compiler::Parser):

```perl
sub test_parse_vs_perl {
    my ($code, $test_name) = @_;

    # Parse with Chalk
    my $chalk_ast = chalk_parse($code);

    # Parse with PPI
    my $ppi_doc = PPI::Document->new(\$code);

    # Compare AST structures (isomorphism check)
    ok(ast_equivalent($chalk_ast, ppi_to_ast($ppi_doc)),
       "$test_name: Chalk AST matches Perl AST");
}
```

**Use Cases**:
- Validate Chalk parser handles all Perl constructs
- Find Chalk grammar bugs
- Ensure semantic actions produce correct AST

**Challenges**:
- AST representations differ (need adapter)
- PPI includes whitespace/comments, Chalk may not
- Need to define "equivalent" ASTs

### Variation 2: Optimizer Differential Testing

Compare optimized vs unoptimized execution:

```perl
sub test_optimizer_semantics {
    my ($code, $test_name) = @_;

    my $graph = compile_chalk($code);

    # Execute unoptimized
    my $unopt_result = execute_cek($graph);

    # Optimize
    my $opt_graph = optimize($graph);

    # Execute optimized
    my $opt_result = execute_cek($opt_graph);

    # Should produce same result
    is($opt_result, $unopt_result,
       "$test_name: optimization preserves semantics");
}
```

**Use Cases**:
- Validate peephole optimizer correctness
- Validate GVN optimizer correctness
- Find optimization bugs that change behavior

**Benefits**:
- No reference implementation needed (self-differential)
- Tests actual Chalk optimizer
- Catches semantic-breaking optimizations

### Variation 3: Cross-Version Differential Testing

Compare different Chalk versions:

```perl
sub test_backwards_compatibility {
    my ($code, $test_name) = @_;

    # Execute with current version
    my $current_result = execute_chalk_current($code);

    # Execute with v0.1.0
    my $v010_result = execute_chalk_v010($code);

    is($current_result, $v010_result,
       "$test_name: backwards compatible with v0.1.0");
}
```

**Use Cases**:
- Ensure no regressions
- Validate migrations
- Test backwards compatibility

### Variation 4: Type System Differential Testing

Compare inferred types with declared types:

```perl
sub test_type_inference {
    my ($code, $expected_types, $test_name) = @_;

    my $graph = compile_chalk($code);

    # Infer types
    my $inferred = type_inference($graph);

    # Compare with expected
    is_deeply($inferred, $expected_types,
             "$test_name: type inference correct");
}
```

**Use Cases**:
- Validate type inference algorithm
- Find type system bugs
- Ensure soundness

---

## Applicability to Other Chalk Components

### ✅ High Value Targets

1. **Semantic Actions** (parser → IR)
   - Compare against hand-written IR for same code
   - Find semantic action bugs
   - Validate IR builder correctness

2. **Type Checker**
   - Compare inferred types with declared types
   - Validate type soundness
   - Find type inference bugs

3. **Code Generator** (IR → machine code/bytecode)
   - Compare execution results with interpreter
   - Validate codegen correctness
   - Find optimization bugs in codegen

### ⚠️ Medium Value Targets

4. **Grammar** (Chalk vs Perl grammar)
   - Compare parse results with PPI
   - Find grammar bugs
   - Challenge: AST representation mismatch

5. **Preprocessor**
   - Compare preprocessed output with expected
   - Validate heredoc handling
   - Validate macro expansion

### ❌ Low Value Targets

6. **SPPF Construction** (too internal)
7. **Lexer** (covered by parser tests)
8. **Semiring Algebra** (mathematical properties, not differential)

---

## Recommendations for Chalk

### Immediate (Phase 5):

1. **Extend cek-compiler-validation.t**
   - Add more test cases for TODO features
   - Cover all Perl operators
   - Add control flow edge cases

2. **Create optimizer-semantics.t**
   - Self-differential testing (optimized vs unoptimized)
   - Test GVN, peephole, and full pipeline
   - Use variation #2 pattern above

3. **Create semantic-actions-validation.t**
   - Compare generated IR with hand-written IR
   - Validate semantic action correctness
   - Fix IR Builder bugs found in cek-compiler-validation.t

### Medium Term (Phase 6):

4. **Create type-inference-validation.t**
   - Compare inferred vs declared types
   - Validate type soundness
   - Use variation #4 pattern

5. **Create parser-compatibility.t**
   - Compare Chalk parser with PPI
   - Find grammar incompatibilities
   - Use variation #1 pattern

### Long Term (Future):

6. **Create codegen-validation.t** (when codegen implemented)
   - Compare codegen execution with interpreter
   - Find codegen bugs
   - Validate optimization correctness

7. **Create backwards-compat.t** (after v1.0 release)
   - Test across Chalk versions
   - Ensure no regressions
   - Use variation #3 pattern

---

## Template: Generic Differential Test

```perl
#!/usr/bin/env perl
# ABOUTME: Differential testing for <COMPONENT>
# ABOUTME: Compares <SYSTEM_A> against <SYSTEM_B> to find bugs

use 5.42.0;
use Test::More;
use <REQUIRED_MODULES>;

# Helper: Execute with System A (reference)
sub execute_reference {
    my ($input) = @_;
    # ... implementation ...
    return $result;
}

# Helper: Execute with System B (under test)
sub execute_under_test {
    my ($input) = @_;
    # ... implementation ...
    return $result;
}

# Helper: Compare results
sub test_differential {
    my ($input, $test_name) = @_;

    # Execute both systems
    my $ref_result = execute_reference($input);
    my $test_result = execute_under_test($input);

    # Compare
    is($test_result, $ref_result,
       "$test_name: systems agree");
}

# Test cases
test_differential($input1, "Case 1");
test_differential($input2, "Case 2");

# Known issues
TODO: {
    local $TODO = "Known bug in <SYSTEM_B> (issue #XXX)";
    test_differential($input3, "Case 3");
}

done_testing();
```

---

## Lessons from cek-compiler-validation.t

### What Works Well

1. **Clear Documentation**: Extensive header comments explain pass rate and failure causes
2. **Separation of Concerns**: Compilation failures vs execution mismatches
3. **Helper Functions**: Clean abstractions for compile, execute_perl, execute_cek
4. **TODO Blocks**: Document known bugs without failing CI
5. **Diagnostic Info**: Helper to inspect IR graph structure

### What Could Be Improved

1. **Test Organization**: 39 inline tests could be data-driven table
2. **Error Context**: Could capture and compare error messages, not just success/failure
3. **Type Coverage**: Only tests numeric results, not strings/arrays/objects
4. **Performance**: Temp file creation slow, could use IPC::Run for better perf
5. **Coverage Tracking**: Could report which IR node types are tested

### Suggested Enhancements

```perl
# Data-driven test table
my @test_cases = (
    {code => 'return 42;', name => 'Constant', category => 'basic'},
    {code => 'return 3 + 5;', name => 'Addition', category => 'arithmetic'},
    # ... more cases ...
);

for my $test (@test_cases) {
    test_cek_vs_perl($test->{code}, $test->{name});
}

# Coverage tracking
my %node_coverage;
for my $test (@test_cases) {
    my $graph = compile_chalk($test->{code});
    my $types = has_node_types($graph, qw(Add Multiply If Region Phi));
    $node_coverage{$_} ||= 0 for keys %$types;
    $node_coverage{$_} += $types->{$_} for keys %$types;
}

diag("Node type coverage:");
diag("  $_: $node_coverage{$_} tests") for sort keys %node_coverage;
```

---

## Metrics and Success Criteria

### Coverage Metrics

| Metric | Target | Current (cek-compiler-validation.t) | Status |
|--------|--------|-------------------------------------|--------|
| IR Node Types | 100% | ~40% (Add, Multiply, Constant, If, Phi, ...) | ⚠️ |
| Perl Operators | 100% | ~20% (+, -, *, /, <, >) | ⚠️ |
| Control Flow | 100% | ~30% (if, if-else) | ⚠️ |
| Data Types | 100% | ~30% (int, TODO: string, array, hash) | ⚠️ |
| Pass Rate | >95% | 89.7% (35/39) | ⚠️ |

### Success Criteria for Differential Tests

✅ **Passing Test**: Both systems agree on output
❌ **Failing Test**: Systems disagree (bug in one system)
⏸ **TODO Test**: Known bug, documented with issue number
⏭ **Skip Test**: Feature not implemented yet

**Goal**: 95% pass rate (excluding TODOs/Skips)

---

## Conclusion

**Key Insight**: Differential testing is Chalk's most effective bug-finding technique

**Evidence**:
- cek-compiler-validation.t found 4 IR Builder bugs
- Clear separation between CEK bugs (0 found) and IR Builder bugs (4 found)
- 89.7% pass rate validates CEK interpreter is largely correct

**Recommendation for Phase 5**:
1. Extend cek-compiler-validation.t with more cases
2. Create optimizer-semantics.t (self-differential)
3. Create semantic-actions-validation.t (IR builder testing)

**Expected ROI**:
- 10-20 new bugs found
- Clear attribution (which component has the bug)
- Regression prevention for future changes

---

**Status**: Pattern analysis complete
**Next Steps**: Apply pattern to optimizer and semantic actions testing
**Template Location**: See "Generic Differential Test" section above
