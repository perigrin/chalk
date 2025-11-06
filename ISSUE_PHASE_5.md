# Complete Phase 5: Context-Aware IR Validation

## Background

PR #158 successfully delivered Phases 1-4 of #139:
- ✅ Phase 1: Source Information Preservation
- ✅ Phase 2: Transformation Chain Tracking
- ✅ Phase 3: Semantic Context Objects
- ✅ Phase 4: Enhanced Error Reporting

Phase 5 was partially implemented with basic parameter validation, but **semantic validation using context information** remains incomplete.

## Problem

The Builder has access to `$context` during IR construction but doesn't use it for semantic validation. Errors are either caught late (during optimization) or silently create invalid IR.

### Current Behavior (Problems)

```perl
# 1. Undefined variable - returns undef silently
my $x = 5;
return $y;  # Should error: $y undefined

# 2. Invalid field access - no validation
my $obj = Point->new(x => 5, y => 10);
return $obj->{z};  # Should error: no field 'z'

# 3. Type mismatch - builds invalid IR
my @arr = (1, 2, 3);
return @arr + 5;  # Should error: can't add array to number
```

### Desired Behavior

Immediate validation with Rust-quality diagnostics:

```
ERROR: Undefined variable '$y'
  --> test.chalk:2:8
  |
2 | return $y;
  |        ^
  |
  hint: Did you forget to declare it with 'my'?
  hint: Did you mean '$x'?
```

## Solution

Implement **context-aware validation** that uses `$context` to validate semantic correctness during IR construction.

### 1. Create ValidationContext Class

`lib/Chalk/IR/ValidationContext.pm`:

```perl
class Chalk::IR::ValidationContext {
    field $context :param :reader;
    field $graph   :param :reader;

    method validate_variable_defined($var_name, $source_info) { ... }
    method validate_class_field($class_name, $field_name, $source_info) { ... }
    method validate_type_operation($op, $left_type, $right_type, $source_info) { ... }
    method validate_control_merge(@control_nodes, $source_info) { ... }
    method find_similar_variables($var_name) { ... }
}
```

### 2. Add Type Inference to Builder

`lib/Chalk/IR/Builder.pm`:

```perl
method _infer_type_from_node($node) {
    return 'Int' if $node->op eq 'Constant' && $node->attributes->{type} eq 'Int';
    return 'Array' if $node->op eq 'ArrayValue';
    return 'Hash' if $node->op eq 'HashValue';
    return 'Object:' . $node->attributes->{class} if $node->op eq 'New';
    # ... etc
}
```

### 3. Update Builder Methods

#### Variable Reads

```perl
method build_load_node($var_name, $source_info = undef) {
    my $validator = Chalk::IR::ValidationContext->new(
        context => $context, graph => $graph
    );
    return $validator->validate_variable_defined($var_name, $source_info);
}
```

#### Arithmetic Operations

```perl
method build_add_node($left_node, $right_node, $source_info = undef) {
    # Existing parameter checks...

    # NEW: Type validation
    my $left_type = $self->_infer_type_from_node($left_node);
    if ($left_type eq 'Array') {
        die Chalk::Error::CompilationError->new(
            message => "Cannot use '+' operator on array",
            source_info => $source_info,
            hints => ["Use array concatenation: (\@a, \@b)"]
        );
    }

    # ... create node
}
```

## Validation Categories

**Priority P0 (Critical)**:
1. Undefined variable detection
2. Type validation for operations
3. Control flow sanity checks

**Priority P1 (High)**:
4. Class field validation
5. Function call arity checking
6. Array/hash operations

**Priority P2 (Medium)**:
7. Loop variable tracking
8. Scope boundary validation
9. Reference target validation

## Acceptance Criteria

### Functionality
- [ ] `ValidationContext` class with validation methods
- [ ] Type inference helpers in Builder
- [ ] All Builder methods accept optional `$source_info`
- [ ] Variable reads validate existence
- [ ] Operations validate type compatibility
- [ ] Field access validates against class definitions
- [ ] Control flow validates merge points

### Error Quality
- [ ] All errors use `CompilationError` class
- [ ] Errors include source location
- [ ] Actionable hints provided
- [ ] "Did you mean?" suggestions for typos

### Testing
- [ ] 50+ tests covering validation categories
- [ ] Error message quality tests
- [ ] All existing tests pass

## Estimated Effort

**2-3 weeks** (10-15 hours):

- **Week 1**: ValidationContext, variable validation, type inference, initial tests
- **Week 2**: Operation validation, class/field validation, control flow
- **Week 3**: Polish, documentation, integration tests

## Success Metrics

Chalk catches these errors **at IR build time** with clear, actionable messages:
- ❌ Undefined variables
- ❌ Invalid field access
- ❌ Type mismatches
- ❌ Wrong function arity
- ❌ Invalid control flow

Error quality matches Rust/TypeScript standards.

## Implementation Notes

- Leverage existing `CompilationError` and `SourceInfo` from Phase 4
- Use existing `$context` in Builder - no architecture changes needed
- Validation is opt-in for backward compatibility (passes optional `$source_info`)
- Start with P0 validations, expand incrementally

## Related

- Issue #139 (parent issue)
- PR #158 (Phases 1-4 implementation)
- `lib/Chalk/IR/Context.pm` - Context implementation
- `lib/Chalk/Error/CompilationError.pm` - Error formatting
