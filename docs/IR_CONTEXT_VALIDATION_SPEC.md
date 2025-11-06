# Phase 5: Context-Aware IR Validation at Build Time

## Context

PR #158 successfully delivered Phases 1-4 of Issue #139:
- ✅ Phase 1: Source Information Preservation (`SourceInfo` class)
- ✅ Phase 2: Transformation Chain Tracking (`TransformRecord`)
- ✅ Phase 3: Semantic Context Objects (`Semantic::Scope`, `Semantic::Context`)
- ✅ Phase 4: Enhanced Error Reporting (`CompilationError` with Rust-style formatting)

**What's Missing**: Phase 5 currently only includes basic parameter validation (checking for undefined/null parameters). The original intent was **semantic validation using context information at IR construction time**.

## Objective

Implement **context-aware validation** that uses the Builder's `$context` to catch semantic errors immediately during IR construction, not in post-hoc validation passes. This provides:

1. **Earlier error detection** - Fail at the point of error, not later
2. **Better error messages** - Full context enables specific, actionable hints
3. **Type safety** - Catch type mismatches before execution
4. **Scope correctness** - Validate variable/field references exist
5. **Rust-quality diagnostics** - Leveraging the SourceInfo/CompilationError infrastructure

## Problem Examples

### Current Behavior (Silent Failures)

```perl
# Example 1: Undefined variable - returns undef silently
my $x = 5;
return $y;  # $y undefined - build_load_node() returns undef

# Example 2: Invalid field access - no validation
my $obj = Point->new(x => 5, y => 10);
return $obj->{z};  # Field 'z' doesn't exist - not caught

# Example 3: Type mismatch - not validated
my @arr = (1, 2, 3);
return @arr + 5;  # Adding array to number - builds invalid IR

# Example 4: Wrong arity - no validation
sub foo($a, $b) { return $a + $b; }
foo(1, 2, 3);  # Too many arguments - not caught at build time
```

### Desired Behavior (Immediate Validation)

```
ERROR: Undefined variable '$y'
  --> test.chalk:2:8
  |
1 | my $x = 5;
2 | return $y;
  |        ^
  |
  hint: Did you forget to declare it with 'my'?
  hint: Did you mean '$x'?

ERROR: Class 'Point' has no field '$z'
  --> test.chalk:2:15
  |
2 | return $obj->{z};
  |               ^
  |
  hint: Valid fields: $x, $y
  hint: Check for typos in the field name
```

## Implementation Plan

### 1. Create ValidationContext Class

**File**: `lib/Chalk/IR/ValidationContext.pm`

Wrapper around `$context` providing validation methods:

```perl
class Chalk::IR::ValidationContext {
    field $context :param :reader;
    field $graph   :param :reader;

    # Variable validation
    method validate_variable_defined($var_name, $source_info) {
        my $label = "lexical:$var_name";
        my $node = $context->($label);

        unless (defined $node) {
            my $similar = $self->find_similar_variables($var_name);
            die Chalk::Error::CompilationError->new(
                message => "Undefined variable '\$$var_name'",
                source_info => $source_info,
                hints => [
                    $similar ? "Did you mean: $similar" : (),
                    "Declare the variable with 'my \$$var_name = ...' first"
                ]
            );
        }

        return $node;
    }

    # Class field validation
    method validate_class_field($class_name, $field_name, $source_info) { ... }

    # Type operation validation
    method validate_type_operation($op, $left_type, $right_type, $source_info) { ... }

    # Control flow validation
    method validate_control_merge(@control_nodes, $source_info) { ... }

    # Function signature validation
    method validate_call_arity($func_name, $arg_count, $source_info) { ... }

    # Helper: Find similar variable names for "did you mean?"
    method find_similar_variables($var_name) { ... }

    # Helper: List all variables in current scope
    method list_available_variables() { ... }
}
```

### 2. Add Type Inference Helpers to Builder

**File**: `lib/Chalk/IR/Builder.pm`

```perl
# Infer type from IR node
method _infer_type_from_node($node) {
    return undef unless defined $node;

    given ($node->op) {
        when ('Constant') {
            return $node->attributes->{type};  # 'Int', 'Str', etc.
        }
        when ('ArrayValue') { return 'Array'; }
        when ('HashValue')  { return 'Hash'; }
        when ('New') {
            return 'Object:' . $node->attributes->{class};
        }
        when ('Add', 'Subtract', 'Multiply', 'Divide') {
            return 'Num';  # Arithmetic operations return numbers
        }
        when ('GT', 'LT', 'EQ', 'NE', 'GE', 'LE') {
            return 'Bool';  # Comparisons return boolean
        }
        default {
            # For complex cases, look up in context if available
            return $self->_lookup_type_in_context($node);
        }
    }
}

# Infer class name from object node
method _infer_class_from_node($node) {
    return undef unless defined $node;

    if ($node->op eq 'New') {
        return $node->attributes->{class};
    }

    # Try to trace back through variable assignments
    return $self->_trace_class_through_context($node);
}
```

### 3. Update Builder Methods with Validation

#### Variable Reads (lib/Chalk/IR/Builder.pm:218-240)

**Before**:
```perl
method build_load_node($var_name) {
    my $node = $context->("lexical:$var_name");
    return $node;  # Can return undef!
}
```

**After**:
```perl
method build_load_node($var_name, $source_info = undef) {
    my $validator = Chalk::IR::ValidationContext->new(
        context => $context,
        graph => $graph
    );

    my $node = $validator->validate_variable_defined($var_name, $source_info);
    return $node;
}
```

#### Arithmetic Operations (lib/Chalk/IR/Builder.pm:167-189)

**Add validation after parameter checks**:
```perl
method build_add_node($left_node, $right_node, $source_info = undef) {
    # Existing parameter validation
    die "build_add_node: left_node is undefined" unless defined($left_node);
    die "build_add_node: right_node is undefined" unless defined($right_node);
    die "build_add_node: left_node is not an IR node" unless ref($left_node) =~ /^Chalk::IR::Node/;
    die "build_add_node: right_node is not an IR node" unless ref($right_node) =~ /^Chalk::IR::Node/;

    # NEW: Context-aware type validation
    my $left_type = $self->_infer_type_from_node($left_node);
    my $right_type = $self->_infer_type_from_node($right_node);

    if ($left_type && $left_type eq 'Array') {
        die Chalk::Error::CompilationError->new(
            message => "Cannot use '+' operator on array",
            source_info => $source_info,
            hints => [
                "Use array concatenation: (\@a, \@b)",
                "Or access elements: \$a[0] + \$b[0]"
            ]
        );
    }

    if ($right_type && $right_type eq 'Array') {
        die Chalk::Error::CompilationError->new(
            message => "Cannot use '+' operator on array",
            source_info => $source_info,
            hints => [
                "Use array concatenation: (\@a, \@b)",
                "Or access elements: \$a[0] + \$b[0]"
            ]
        );
    }

    # ... rest of method unchanged
}
```

**Apply similar pattern to**: `build_multiply_node`, `build_sub_node`, `build_divide_node`

#### Field Access (lib/Chalk/IR/Builder.pm:610-626)

```perl
method build_field_access_node($object_node, $field_name, $source_info = undef) {
    my $validator = Chalk::IR::ValidationContext->new(
        context => $context,
        graph => $graph
    );

    # Infer class and validate field exists
    my $class_name = $self->_infer_class_from_node($object_node);

    if (defined $class_name) {
        $validator->validate_class_field($class_name, $field_name, $source_info);
    }

    # ... rest of method unchanged
}
```

#### Region/Control Flow (lib/Chalk/IR/Builder.pm:~350-400)

```perl
method build_region_node($incoming_controls, $source_info = undef) {
    my $validator = Chalk::IR::ValidationContext->new(
        context => $context,
        graph => $graph
    );

    # Validate control flow merge points
    $validator->validate_control_merge(@$incoming_controls, $source_info);

    # ... rest of method unchanged
}
```

### 4. Validation Categories to Implement

Priority order:

**P0 (Critical)**:
1. ✅ Undefined variable detection in `build_load_node()`
2. ✅ Type validation for arithmetic operations
3. ✅ Control flow sanity checks (Region, Phi)

**P1 (High)**:
4. ✅ Class field validation
5. ✅ Function call arity checking
6. ✅ Array/hash type operations

**P2 (Medium)**:
7. ✅ Loop variable modification tracking
8. ✅ Scope boundary validation
9. ✅ Reference target validation

### 5. Testing Strategy

**File**: `t/ir/context-validation.t`

```perl
# Test 1: Undefined variable detection
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path => 'test.chalk',
        start_line => 5, start_col => 10,
        end_line => 5, end_col => 12,
        start_pos => 50, end_pos => 52
    );

    eval {
        my $node = $builder->build_load_node('undefined_var', $source_info);
    };

    like($@, qr/Undefined variable/, 'Detects undefined variable');
    like($@, qr/test\.chalk:5:10/, 'Includes source location');
    like($@, qr/hint:/, 'Provides recovery hints');
}

# Test 2: Type validation for operations
{
    my $builder = Chalk::IR::Builder->new();
    $builder->build_start_node();

    my $array = $builder->build_array_value_node([]);
    my $num = $builder->build_constant_node(5);

    eval {
        my $result = $builder->build_add_node($array, $num, $source_info);
    };

    like($@, qr/Cannot use.*operator.*array/i, 'Rejects array in arithmetic');
}

# Test 3: Class field validation
# Test 4: Control flow validation
# Test 5: Function arity validation
# ... etc
```

**Additional test files**:
- `t/ir/validation-context.t` - ValidationContext class tests
- `t/ir/type-inference.t` - Type inference helper tests
- `t/error/validation-errors.t` - Error message quality tests

## Acceptance Criteria

### Functionality

- [ ] `ValidationContext` class with all validation methods
- [ ] Type inference helpers in Builder
- [ ] All Builder methods pass `$source_info` parameter
- [ ] Variable reads validate existence before use
- [ ] Arithmetic operations validate type compatibility
- [ ] Field access validates against class definitions
- [ ] Control flow nodes validate merge points
- [ ] Function calls validate arity (when signature available)

### Error Quality

- [ ] All validation errors use `CompilationError` class
- [ ] Errors include exact source location via `SourceInfo`
- [ ] Errors provide actionable hints for recovery
- [ ] "Did you mean?" suggestions for typos
- [ ] Clear distinction between user errors and internal bugs

### Testing

- [ ] 50+ tests covering all validation categories
- [ ] Tests verify error messages include source locations
- [ ] Tests verify hints are provided
- [ ] Integration tests with semantic actions
- [ ] All existing tests still pass

### Documentation

- [ ] Update `docs/IR_BUILDER.md` with validation architecture
- [ ] Document when to use validation vs assertions
- [ ] Examples of adding validation to new node types
- [ ] Update issue #139 as complete

## Estimated Effort

**2-3 weeks** (10-15 hours as originally estimated for Phase 5):

- **Week 1** (4-5 hours):
  - ValidationContext infrastructure
  - Basic variable validation
  - Type inference helpers
  - Initial tests (20+ tests)

- **Week 2** (3-4 hours):
  - Arithmetic/comparison type validation
  - Class/field validation
  - Control flow validation
  - Expand tests (30+ tests)

- **Week 3** (3-4 hours):
  - Function call validation
  - Loop variable tracking
  - Polish error messages
  - Documentation
  - Final integration tests (50+ total)

## Success Metrics

When complete, Chalk will catch these errors **at IR build time**:

```perl
# Before: Silent failure or runtime error
# After: Clear compile-time error with source location and hints

❌ Undefined variables
❌ Invalid field access
❌ Type mismatches
❌ Wrong function arity
❌ Invalid control flow merges
❌ Array/hash type errors
```

Error messages will match Rust/TypeScript quality standards with exact source locations and actionable recovery hints.

## References

- Issue #139: IR Enhancement Implementation
- PR #158: Phases 1-4 implementation
- `lib/Chalk/IR/Context.pm` - Context-as-closure implementation
- `lib/Chalk/Error/CompilationError.pm` - Error formatting
- `lib/Chalk/IR/SourceInfo.pm` - Source location tracking

## Notes

This completes the original vision of #139: using the rich context information during IR construction to provide immediate, helpful feedback. The infrastructure from Phases 1-4 makes this possible without retrofitting.
