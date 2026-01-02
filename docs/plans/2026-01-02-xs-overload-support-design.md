# XS Overload Support Design

**Date:** 2026-01-02
**Status:** Design
**Goal:** Enable compilation of lib/ files (Parser, Grammar, Token, etc.) to XS to address 3-hour test suite runtime

## Problem Statement

The Chalk test suite takes ~3 hours to run, primarily due to parser performance. Parser infrastructure files (Parser.pm, Grammar.pm, Token.pm, Base.pm) are the bottleneck - every test parses code multiple times.

All four core parser files use `use overload` for operator overloading:
- **Token.pm** (45 lines): Overloads `""`, `eq`, `ne`, `cmp` for string operations
- **Parser.pm** (871 lines): Uses overload for internal operations
- **Grammar.pm** (233 lines): Uses overload for grammar operations
- **Base.pm** (71 lines): Base class with overload support

**Current blocker**: XS code generation doesn't support Perl's `use overload` pragma.

**Solution chosen**: Implement XS overload support using the `OVERLOAD:` directive (as documented in "Learning XS - Overloading" article).

## Architecture Overview

The implementation extends the compilation pipeline at three points:

### 1. Grammar Phase
Parse `use overload` statements and extract operator-to-method mappings:

```perl
use overload
    '""'  => 'value',
    'eq'  => '_string_eq',
    'ne'  => '_string_ne',
    'cmp' => '_string_cmp';
```

Becomes: `{operators => {'""' => 'value', 'eq' => '_string_eq', ...}, fallback => TRUE}`

### 2. IR/Metadata Phase
Store overload mappings in ClassDef nodes. Since overload applies class-wide, attach metadata to ClassDef IR nodes.

### 3. XS Generation Phase
When emitting XSUBs for overloaded methods, add `OVERLOAD:` directive and `...` parameter:

```c
SV* value(SV* self, ...)
OVERLOAD: ""
CODE:
    SV* tmp_0 = ObjectFIELDS(self)[0];
    RETVAL = tmp_0;
OUTPUT:
    RETVAL
```

**Key insight**: We don't parse Perl's magic system - we recognize `use overload`, map operators to methods, and emit `OVERLOAD:` directives. The Perl runtime handles the rest.

## Component Details

### Component 1: Grammar Support

Add to `grammar/chalk.bnf`:

```bnf
UseStatement -> 'use' WS_OPT 'overload' WS_OPT OverloadSpec
OverloadSpec -> OverloadPair
OverloadSpec -> OverloadPair WS_OPT ',' WS_OPT OverloadSpec
OverloadPair -> String WS_OPT '=>' WS_OPT String
OverloadPair -> String WS_OPT '=>' WS_OPT 'undef'
OverloadPair -> String WS_OPT '=>' WS_OPT MethodName
```

### Component 2: Semantic Action Enhancement

Modify `lib/Chalk/Grammar/Chalk/Rule/UseStatement.pm` to detect and process `use overload`:

```perl
method evaluate($context) {
    my $module_name = $self->_extract_module_name($context);

    if ($module_name eq 'overload') {
        # Extract operator => method mappings from context
        my %mappings;
        my $has_fallback = 0;

        # Parse pairs: '""' => 'value', 'eq' => '_string_eq', etc.
        # Extract fallback => 1 if present

        return {
            type => 'overload_directive',
            mappings => \%mappings,
            fallback => $has_fallback,
        };
    }

    # ... existing use statement handling
}
```

### Component 3: ClassDef Integration

Modify `lib/Chalk/Grammar/Chalk/Rule/ClassDeclaration.pm` to collect overload directives:

```perl
method evaluate($context) {
    # ... existing field/method extraction ...

    # Collect overload directives from class body
    my %overload_map;
    for my $stmt (@class_body_statements) {
        if (ref($stmt) eq 'HASH' && $stmt->{type} eq 'overload_directive') {
            %overload_map = (%overload_map, $stmt->{mappings}->%*);
        }
    }

    # Create ClassDef with overload mappings
    return Chalk::IR::Node::ClassDef->new(
        class_name   => $class_name,
        fields       => \@field_nodes,
        methods      => \@method_nodes,
        overload_mappings => \%overload_map,  # NEW FIELD
    );
}
```

**ClassDef IR Node Extension**:
```perl
class Chalk::IR::Node::ClassDef {
    # ... existing fields ...
    field $overload_mappings :param = {};  # operator => method_name map
}
```

### Component 4: XS Visitor Enhancement

Modify `lib/Chalk/Target/XS.pm` to handle overload mappings:

```perl
method visit_ClassDef($node) {
    my $class_name = $node->class_name;
    my $overload_map = $node->overload_mappings // {};
    my @xsubs;

    # Generate XSUBs for methods
    for my $method ($node->methods->@*) {
        my $method_name = $method->name;
        my $xsub = $self->visit_FunctionDef($method);

        # Check if this method implements an overloaded operator
        for my $op (keys %$overload_map) {
            if ($overload_map->{$op} eq $method_name) {
                # Add OVERLOAD directive to XSUB
                $xsub->set_overload_operator($op);
                last;
            }
        }

        push @xsubs, $xsub;
    }

    # Add FALLBACK directive if specified
    if ($overload_map->{fallback}) {
        push @xsubs, $self->_generate_fallback_xsub();
    }

    return $self->_emit_module_code($class_name, \@xsubs);
}

method _generate_fallback_xsub() {
    # Generate: FALLBACK: TRUE
    return Chalk::Target::XS::AST::Directive->new(
        type => 'FALLBACK',
        value => 'TRUE',
    );
}
```

### Component 5: XSUB AST Extension

Extend `lib/Chalk/Target/XS/AST/XSUB.pm` to support overload directives:

```perl
class Chalk::Target::XS::AST::XSUB {
    field $name :param;
    field $params :param;
    field $body :param;
    field $return_type :param;
    field $overload_op :param = undef;  # e.g., '""', 'eq', '+'

    method set_overload_operator($op) {
        $overload_op = $op;
    }

    method emit() {
        my $code = "$return_type\n$name(SV* self";

        # Add ... for overloaded operators (they receive extra params)
        if (defined $overload_op) {
            $code .= ", ...";
        } else {
            # Regular params
            $code .= ", " . join(", ", @$params) if @$params;
        }
        $code .= ")\n";

        # Add OVERLOAD directive
        if (defined $overload_op) {
            $code .= "OVERLOAD: $overload_op\n";
        }

        $code .= "CODE:\n";
        $code .= $body->emit();
        $code .= "OUTPUT:\n    RETVAL\n";

        return $code;
    }
}
```

## Edge Cases

### 1. Comparison Operators

Comparison operators (`eq`, `ne`, `==`, `!=`, `cmp`, etc.) must return `&PL_sv_yes` or `&PL_sv_no`:

```perl
method _is_comparison_operator($op) {
    return $op =~ /^(eq|ne|==|!=|<|>|<=|>=|cmp|<=>)$/;
}

method visit_comparison_method($method, $op) {
    if ($self->_is_comparison_operator($op)) {
        # Modify return statements to use &PL_sv_yes / &PL_sv_no
        # instead of plain boolean values
        $method->set_return_convention('perl_boolean');
    }
}
```

### 2. Missing Method Definition

If `use overload '""' => 'to_string'` but no `to_string` method exists:
- Emit a compilation warning
- Skip the OVERLOAD directive
- Document limitation in generated code comments

```perl
# In visit_ClassDef
for my $op (keys %$overload_map) {
    my $method_name = $overload_map->{$op};
    unless ($self->_has_method($node, $method_name)) {
        warn "Overload operator '$op' references missing method '$method_name'";
        next;
    }
    # ... generate overload ...
}
```

### 3. Multiple `use overload` Statements

Merge multiple overload directives in the same class:

```perl
# First: use overload '""' => 'value';
# Second: use overload 'eq' => '_string_eq';
# Result: {'""' => 'value', 'eq' => '_string_eq'}
```

ClassDeclaration collects all overload directives and merges them.

## Testing Strategy

### 1. Grammar Tests (`t/grammar/use-overload.t`)

Test parsing of `use overload` statements:

```perl
# Test basic overload
my $code = q{
    use overload
        '""' => 'value',
        'eq' => '_string_eq';
};
# Verify: parses successfully, extracts mappings

# Test with fallback
my $code2 = q{
    use overload
        '+' => 'add',
        fallback => 1;
};
# Verify: fallback flag set

# Test multiple statements
my $code3 = q{
    use overload '""' => 'to_string';
    use overload 'eq' => 'equals';
};
# Verify: both operators captured
```

### 2. XS Generation Tests (`t/target/xs-overload.t`)

Test XS code generation for overloaded classes:

```perl
my $code = q{
    class Token {
        field $value :param;

        method value() { return $value; }
        method _string_eq($other) { return $value eq $other; }

        use overload
            '""'  => 'value',
            'eq'  => '_string_eq';
    }
};

my $xs = generate_xs($code);

# Verify OVERLOAD directives present
like($xs, qr/OVERLOAD: ""/, 'Has stringification overload');
like($xs, qr/OVERLOAD: eq/, 'Has eq overload');

# Verify ... in signatures
like($xs, qr/value\(SV\* self, \.\.\.\)/, 'Overloaded method has ... params');

# Verify comparison operators return proper values
like($xs, qr/PL_sv_yes|PL_sv_no/, 'Comparison uses Perl boolean values');
```

### 3. E2E Compilation Test (`t/target/xs-compile-token.t`)

Compile actual Token.pm and test runtime behavior:

```perl
# Compile Token.pm to XS
my $xs_code = compile_file('lib/Chalk/Grammar/Token.pm');

# Write to temp directory and build
my $tempdir = tempdir(CLEANUP => 1);
write_xs_files($tempdir, 'Chalk::Grammar::Token', $xs_code);
compile_xs_module($tempdir);

# Load compiled module
require "$tempdir/blib/lib/Chalk/Grammar/Token.pm";

# Test stringification
my $token = Chalk::Grammar::Token->new(value => 'hello');
is("$token", 'hello', 'Stringification works');

# Test comparison
ok($token eq 'hello', 'eq operator works');
ok(!($token eq 'world'), 'eq comparison correct');
ok($token ne 'world', 'ne operator works');

# Test cmp
is($token cmp 'hello', 0, 'cmp returns 0 for equal');
ok(($token cmp 'abc') > 0, 'cmp works for greater than');
```

### 4. Performance Benchmark

Measure speedup from compiling parser infrastructure:

```perl
# Benchmark script: bench/parser-performance.pl

# Before: Pure Perl parser
my $start = time;
run_test_subset('t/grammar/*.t');
my $perl_time = time - $start;

# After: Compiled Parser/Grammar/Token
load_compiled_modules();
$start = time;
run_test_subset('t/grammar/*.t');
my $xs_time = time - $start;

my $speedup = $perl_time / $xs_time;
say "Perl time: ${perl_time}s";
say "XS time: ${xs_time}s";
say "Speedup: ${speedup}x";
```

Target: >2x speedup on grammar tests, >1.5x speedup on full suite.

## Implementation Plan

### Phase 1: Grammar & Parsing
1. Add `use overload` grammar rules to chalk.bnf
2. Implement UseStatement semantic action for overload
3. Test: `t/grammar/use-overload.t` (parsing only)

### Phase 2: IR Integration
1. Add `overload_mappings` field to ClassDef IR node
2. Modify ClassDeclaration to collect overload directives
3. Test: Verify ClassDef includes mappings

### Phase 3: XS Generation
1. Extend XSUB AST to support OVERLOAD directive
2. Implement visit_ClassDef overload handling
3. Add comparison operator special case handling
4. Test: `t/target/xs-overload.t` (XS generation)

### Phase 4: E2E Testing
1. Compile Token.pm to XS
2. Load and test compiled module
3. Verify all overloaded operators work
4. Test: `t/target/xs-compile-token.t`

### Phase 5: Full Parser Compilation
1. Compile Parser.pm, Grammar.pm, Base.pm
2. Run test suite with compiled modules
3. Measure and document performance improvement
4. Fix any issues discovered

## Success Criteria

- ✅ All lib/ files with `use overload` can compile to XS
- ✅ Compiled modules pass existing tests
- ✅ Overloaded operators work identically to pure Perl
- ✅ Test suite runtime reduced by >30% (from 3 hours to <2 hours)
- ✅ No behavioral differences between Perl and XS versions

## Related Issues

- #520: Self-hosting - compile lib/ to XS
- Related to parser performance optimization
- Unblocks compilation of 13 lib/ files using overload

## References

- "Learning XS - Overloading" blog post (June 2025): OVERLOAD directive usage
- perlxs documentation: xsubpp and OVERLOAD directives
- Token.pm: Canonical example (45 lines, 4 overloaded operators)
