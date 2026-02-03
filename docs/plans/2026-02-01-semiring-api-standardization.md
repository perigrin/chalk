# Semiring API Standardization

**Status**: 🟡 Draft - Ready for Review
**Branch**: `semiring-optimizations` (from `pu`)
**Created**: 2026-02-01
**Author**: perigrin + Claude

## Overview

Standardize the semiring element API to consistently accept and propagate `EvalContext` across all semirings, enabling future context-aware validation without changing the parser or semiring algebra.

## Motivation

Currently, only Boolean and Semantic semirings have partial `EvalContext` support from the unified comonad prototype. This creates API inconsistency across the semiring layer and prevents future validation improvements that depend on parse context.

Without SPPF (Shared Packed Parse Forest), every semiring element represents an actual parse tree node. Therefore, all semirings should consistently support EvalContext as a standard API feature, even if individual semirings choose not to use the context in their algebra.

## Goals

### In Scope

- Standardize element API: All element classes have `field $context :param :reader = undef`
- Standardize semiring API: All `init_element_from_rule()` methods accept optional `$ctx` parameter
- Standardize terminal handling: All `on_scan()` methods create contexts for scanned terminals
- Identity invariant: All identity elements (`add_id`, `mul_id`) use shared empty context singleton
- Maintain singleton pattern: Identity elements remain shared singletons using shared empty context
- Backward compatibility: Existing code paths continue to work when context not provided

### Out of Scope (Future Work)

- Changing how individual semirings implement their algebra (add/multiply operations)
- Teaching semirings to use context for validation (separate follow-up work)
- Performance optimization beyond maintaining singleton identities
- Changing the Composite semiring's filtering logic
- Modifying the Parser to create contexts (already implemented for Boolean)

### Success Criteria

- All 12 semiring element classes have standardized context field
- All `init_element_from_rule()` methods have consistent signature
- All `on_scan()` methods create contexts for terminals
- Identity elements verified to use shared empty context singleton
- Self-hosting test suite passes: `prove`
- No behavioral changes to parsing (same IR output as before)

## Implementation Strategy

### Approach

Use Boolean semiring as the reference implementation, systematically update each semiring to match its API pattern.

**Why this approach**:
- Boolean already implements the pattern correctly (from unified comonad prototype)
- Proven to work with self-hosting tests
- Clear, minimal example to follow
- Reduces risk of introducing bugs

### Semirings to Update

**Priority Order** (by complexity):

1. **Precedence** - Similar to Boolean (filtering semiring, simple elements)
2. **TypeInference** - More complex (tropical semiring with type lattice)
3. **SemanticValidation** - Moderate complexity (rule-based filtering)
4. **Semantic** - Most complex (IR generation), already partially done
5. **Utility semirings** - Position, AST, FewestChildren, LongestMatch, ChalkIR, ChalkSyntax

**Total semirings**: 12
- Validation/IR: Boolean ✅, Precedence, TypeInference, SemanticValidation, Semantic (partial)
- Composites: ChalkSyntax, ChalkIR, Composite
- Utilities: Position, AST, FewestChildren, LongestMatch

### Update Pattern

For each semiring, follow this pattern:

1. **Add context field** to element class:
   ```perl
   field $context :param :reader = undef;
   ```

2. **Update init_element_from_rule() signature**:
   ```perl
   method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef, $ctx = undef) {
       if (defined($ctx)) {
           return SomeElement->new(..., context => $ctx);
       }
       # Existing logic (return cached identity or create element)
   }
   ```

3. **Update on_scan()** to create contexts (if implemented):
   ```perl
   method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
       if (defined($element->context)) {
           # Create new context for scanned terminal
           my $new_ctx = Chalk::EvalContext->new(...);
           return SomeElement->new(..., context => $new_ctx);
       }
       # Existing logic
   }
   ```

4. **Verify multiply() signature** (no logic changes needed yet):
   ```perl
   method multiply($x, $y) {
       # Elements now have optional context
       # Semiring can use or ignore as needed
   }
   ```

5. **Verify identity elements use shared empty context**:
   ```perl
   # Shared empty context singleton for identity elements
   field $empty_context :reader = Chalk::EvalContext->new(
       focus     => undef,
       children  => [],
       start_pos => 0,
       end_pos   => 0,
       env       => {},
       grammar   => undef,
       rule      => undef,
   );

   field $mul_id :reader = SomeElement->new(..., context => $empty_context);
   field $add_id :reader = SomeElement->new(..., context => $empty_context);
   ```

6. **Run tests** after each update:
   ```bash
   prove  # Self-hosting test suite
   ```

## Technical Specification

### Standard Element API Contract

Every semiring element class must implement:

```perl
class SomeElement :isa(Chalk::Element) {
    # REQUIRED: Context field (may be undef)
    field $context :param :reader = undef;

    # Other fields specific to this semiring
    field $value :param :reader;
    # ...

    # Existing methods unchanged (add, multiply, etc.)
    method add($other, $swap = undef) { ... }
    method multiply($other, $swap = undef) { ... }
}
```

### Standard Semiring API Contract

Every semiring class must implement:

```perl
class SomeSemiring :isa(Chalk::Semiring) {
    # REQUIRED: Shared empty context singleton for identity elements
    field $empty_context :reader = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 0,
        end_pos   => 0,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    # REQUIRED: Identity elements use shared empty context
    field $mul_id :reader = SomeElement->new(..., context => $empty_context);
    field $add_id :reader = SomeElement->new(..., context => $empty_context);

    # REQUIRED: Five-parameter signature (last parameter optional)
    method init_element_from_rule(
        $rule,
        $start_pos = 0,
        $end_pos = 0,
        $matched_value = undef,
        $ctx = undef  # Optional EvalContext
    ) {
        # If context provided, create element with it
        if (defined($ctx)) {
            return SomeElement->new(..., context => $ctx);
        }
        # Otherwise use existing logic (backward compatibility)
        return $mul_id;  # or create new element
    }

    # REQUIRED: on_scan creates contexts for terminals (if implemented)
    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # If element has context, create new context for scanned terminal
        if (defined($element->context)) {
            my $old_ctx = $element->context;
            my $match_length = length($matched_value);

            my $new_ctx = Chalk::EvalContext->new(
                focus     => $matched_value,
                children  => [],  # Terminal has no children
                start_pos => $pos,
                end_pos   => $pos + $match_length,
                env       => $old_ctx->env,
                grammar   => $old_ctx->grammar,
                rule      => $old_ctx->rule,
            );

            return SomeElement->new(..., context => $new_ctx);
        }
        # Otherwise return element unchanged (backward compatibility)
        return $element;
    }

    # multiply() receives elements with contexts (may use or ignore them)
    method multiply($x, $y) {
        # Semiring decides whether to use context
        # For now, most semirings will ignore it
        # Future work: Use context for validation
    }
}
```

### Key Principles

1. **Backward Compatibility**: If `$ctx` is undef, semiring behaves as before
2. **Shared Empty Contexts**: Identity elements use shared singleton empty context for API consistency
3. **Context Propagation**: Parser creates contexts, semirings propagate them through multiply/on_scan
4. **Optional Usage**: Semirings can ignore contexts in their algebra (implementation detail)
5. **Singleton Pattern**: Identity elements remain shared singletons, using shared empty context singleton

### Rationale: Shared Empty Contexts

Identity elements use shared empty context singletons rather than `undef` for:

- **API Consistency**: All elements always have defined contexts
- **Simpler Client Code**: No undef checks needed in multiply/add operations
- **Uniform Semantics**: Empty context vs populated context, but always a context object
- **Performance**: Single shared allocation per semiring (negligible overhead)

This pattern simplifies client code that works with contexts. Instead of checking `defined($element->context)`, clients can safely call `$element->context->children` knowing it will always return a valid (possibly empty) array. The distinction between identity elements and parse-derived elements becomes semantic (empty vs populated context) rather than structural (undef vs object).

### Reference Implementation

See `lib/Chalk/Semiring/Boolean.pm` for the complete reference implementation.

**Key excerpts**:

**Element class** (lines 9-11):
```perl
class Chalk::Semiring::BooleanElement :isa(Chalk::Element) {
    field $value :param :reader;
    field $context :param :reader = undef;  # EvalContext
}
```

**Shared empty context and identity elements** (lines 45-58):
```perl
# Shared empty context singleton for identity elements
field $empty_context :reader = Chalk::EvalContext->new(
    focus     => undef,
    children  => [],
    start_pos => 0,
    end_pos   => 0,
    env       => {},
    grammar   => undef,
    rule      => undef,
);

# Identity elements for Boolean algebra
field $mul_id :reader = Chalk::Semiring::BooleanElement->new(value => 1, context => $empty_context);
field $add_id :reader = Chalk::Semiring::BooleanElement->new(value => 0, context => $empty_context);
```

**init_element_from_rule** (lines 102-112):
```perl
method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef, $ctx = undef) {
    if (defined($ctx)) {
        return Chalk::Semiring::BooleanElement->new(
            value => 1,
            context => $ctx
        );
    }
    # Otherwise return cached mul_id (with shared empty context)
    return $mul_id;
}
```

**on_scan** (lines 69-100):
```perl
method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
    # Reject keywords when they appear as identifiers
    my $is_identifier = defined($pattern_name) && $pattern_name eq 'IDENTIFIER';
    if ($is_identifier && defined($matched_value) && exists $keywords->{$matched_value}) {
        return $add_id;  # Return 0 (invalid parse)
    }

    # If element has context, create new context for scanned terminal
    if (defined($element->context)) {
        my $old_ctx = $element->context;
        my $match_length = length($matched_value // '');

        my $new_ctx = Chalk::EvalContext->new(
            focus     => $matched_value,
            children  => [],  # Terminal has no children
            start_pos => $pos,
            end_pos   => $pos + $match_length,
            env       => $old_ctx->env,
            grammar   => $old_ctx->grammar,
            rule      => $old_ctx->rule,
        );

        # Return new element with updated context
        return Chalk::Semiring::BooleanElement->new(
            value => 1,
            context => $new_ctx
        );
    }

    # Otherwise return element unchanged (no context)
    return $element;
}
```

**multiply** (lines 22-28):
```perl
method multiply( $other, $swap = undef ) {
    # Boolean AND for sequence: both must succeed
    # For Boolean, we prefer to return existing elements when possible
    # to preserve context and match Precedence semiring pattern
    return $self unless $value;  # If self is false, return self (fail fast, preserves context)
    return $other;  # self is true, result is other (preserves other's context)
}
```

Note: The current Boolean implementation uses a simplified multiply that returns existing elements rather than creating new ones. This preserves contexts efficiently. When identity elements have shared empty contexts, this pattern remains valid - the identity's empty context is simply propagated when appropriate.

## Testing Strategy

### Per-Semiring Testing

After updating each semiring:

1. Run full test suite: `prove`
2. Verify no test failures introduced
3. Check that IR output unchanged (behavioral invariant)
4. Optional: Add `DEBUG_CONTEXT=1` flag to verify context creation

### Integration Testing

After all semirings updated:

1. Run full self-hosting test: `prove`
2. Verify all tests pass
3. Compare IR output before/after (should be identical)
4. Check memory usage (contexts add allocation overhead)

### Regression Prevention

- Keep tests passing at every commit
- Each semiring update is a separate commit
- If test fails, rollback and investigate before proceeding

## Implementation Tasks

### Phase 1: Core Validation Semirings ✅ COMPLETE

- [x] **Task 1.1**: Update Precedence semiring ✅
  - Added `field $context :param :reader = undef` to PrecedenceElement
  - Updated `init_element_from_rule()` signature
  - Updated `on_scan()` to create contexts
  - Verified identity elements use shared empty context
  - Tests: 18 tests pass (t/semiring-api-precedence.t)

- [x] **Task 1.2**: Update TypeInference semiring ✅
  - Added `field $context :param :reader = undef` to TypeInferenceElement
  - Updated `init_element_from_rule()` signature
  - Updated `on_scan()` to create contexts
  - Verified identity elements use shared empty context
  - Tests: 16 tests pass (t/semiring-api-typeinference.t)

- [x] **Task 1.3**: Update SemanticValidation semiring ✅
  - Added `field $context :param :reader = undef` to SemanticValidationElement
  - Updated `init_element_from_rule()` signature
  - Added `on_scan()` method
  - Verified identity elements use shared empty context
  - Tests: 16 tests pass (t/semiring-api-semanticvalidation.t)

### Phase 2: IR Generation Semiring ✅ COMPLETE

- [x] **Task 2.1**: Complete Semantic semiring update ✅
  - Verified `field $context` already present
  - Updated `init_element_from_rule()` signature (5th parameter)
  - Verified `on_scan()` already creates contexts
  - Verified identity elements use shared empty context
  - Tests: 17 tests pass (t/semiring-api-semantic.t)

### Phase 3: Composite Semirings ✅ COMPLETE

- [x] **Task 3.1**: Update Composite semiring ✅
  - Verified context propagation to wrapped semirings
  - Updated `init_element_from_rule()` to pass context to children
  - Verified `on_scan()` propagates contexts
  - Tests: 34 tests pass (t/semiring-api-composite.t)

- [x] **Task 3.2**: Verify ChalkSyntax composite ✅
  - Updated delegation to pass context parameter
  - All delegation works correctly

- [x] **Task 3.3**: Verify ChalkIR composite ✅
  - Updated delegation to pass context parameter
  - All delegation works correctly

### Phase 4: Utility Semirings ✅ COMPLETE (using TDD)

- [x] **Task 4.1**: Update Position semiring ✅
  - TDD: Test first, watched fail, implemented, watched pass
  - Tests: 14 tests pass (t/semiring-api-position.t)

- [x] **Task 4.2**: Update AST semiring ✅
  - TDD: Test first, watched fail, implemented, watched pass
  - Tests: 19 tests pass (t/semiring-api-ast.t)

- [x] **Task 4.3**: Update FewestChildren semiring ✅
  - TDD: Test first, watched fail, implemented, watched pass
  - Tests: 14 tests pass (t/semiring-api-fewestchildren.t)

- [x] **Task 4.4**: Update LongestMatch semiring ✅
  - TDD: Test first, watched fail, implemented, watched pass
  - Tests: 14 tests pass (t/semiring-api-longestmatch.t)

### Phase 5: Final Verification 🔄 IN PROGRESS

- [ ] **Task 5.1**: Run full test suite
  - Execute: `prove`
  - Verify: All tests pass
  - Document: Any performance changes observed

- [ ] **Task 5.2**: Verify IR output unchanged
  - Compare IR before/after for sample programs
  - Confirm: Behavioral invariant maintained

- [ ] **Task 5.3**: Update documentation
  - Add semiring API contract to `docs/semiring-architecture.md`
  - Document context field requirement
  - Update prototype findings with production status

**Test Coverage**: 162 tests across 9 test files, all passing

## Future Work

After this API standardization is complete:

1. **Context-Aware Type Validation**: Teach TypeInference to use EvalContext for checking type expectations from rules
2. **Context-Aware Semantic Validation**: Teach SemanticValidation to use EvalContext for enforcing semantic constraints
3. **Performance Optimization**: Profile and optimize context allocation if needed
4. **Grammar Refactoring**: Use standardized context API to support Term → ListExpression → Expression hierarchy for use overload fix

## References

- **Unified Comonad Prototype**: `docs/prototype-unified-comonad-findings.md`
- **Semiring Architecture**: `docs/semiring-architecture.md`
- **Boolean Reference Implementation**: `lib/Chalk/Semiring/Boolean.pm`
- **EvalContext Implementation**: `lib/Chalk/EvalContext.pm`

## Related Issues

- **Issue #562**: Multi-operator use overload parsing (blocked on this work)
- **Grammar refactoring**: Requires context API for proper validation
