# Plan: Remove ExpressionList from Grammar

**Date**: 2026-01-29
**Status**: Planning
**Related**: `docs/perl-expression-semantics.md`, `docs/plans/2026-01-29-expression-context-understanding.md`

## Status Update (2026-01-30)

**Architectural discovery completed**: Prototype validates unified EvalContext comonad architecture.

See `docs/prototype-unified-comonad-findings.md` for complete analysis.

**Key finding**: Parser should create EvalContext and pass to all semirings, eliminating the need for on_complete() metadata passing and cross-semiring peeking.

**Next step**: Decide whether to adopt unified architecture before proceeding with ExpressionList removal.

## Goal

Remove the `ExpressionList` grammar construct entirely and replace it with `Expression` + type-based context (list vs scalar).

## Rationale

From `docs/perl-expression-semantics.md`:

> **Perl does not have an "ExpressionList" construct.** Instead, Perl has:
> - **Expressions** (singular)
> - **Context** (scalar vs list)
> - The **comma operator** which evaluates to a list in list context

**Current problem**: ExpressionList creates parse ambiguities because:
1. Comma can be a separator (in ExpressionList) OR an operator (in Expression)
2. Fat-comma `=>` can be part of ExpressionList structure OR part of an Expression
3. Multiple valid parse trees exist for the same input

**Solution**: Model Perl's actual semantics where comma and fat-comma are **operators** within Expression, and **context** (determined by TypeInference) controls interpretation.

## Current Grammar Usage

ExpressionList is used in 17 places (from `grammar/chalk.bnf`):

### 1. Statement Level
- Line 102: `Statement -> ExpressionList`

### 2. Control Flow
- Line 162: `ReturnStatement -> 'return' WS_OPT '(' WS_OPT ExpressionList WS_OPT ')'`

### 3. Use Statement (PRIMARY FOCUS)
- Line 179: `UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT ExpressionList`

### 4. Parenthesized Expressions
- Line 268: `Expression -> '(' WS_OPT ExpressionList WS_OPT ')'`

### 5. Function and Method Calls (6 uses)
- Line 359: `FunctionCall -> Identifier '(' WS_OPT ExpressionList WS_OPT ')'`
- Line 362: `FunctionCall -> QualifiedIdentifier WS_OPT '->' MethodName WS_OPT '(' WS_OPT ExpressionList WS_OPT ')'`
- Line 364: `FunctionCall -> Variable '->' '(' WS_OPT ExpressionList WS_OPT ')'`
- Line 371: `MethodCall -> Expression WS_OPT '->' WS_OPT MethodName '(' WS_OPT ExpressionList WS_OPT ')'`
- Line 376: `MethodCall -> Expression WS_OPT '->' WS_OPT QualifiedIdentifier '(' WS_OPT ExpressionList WS_OPT ')'`
- Line 464: `Variable -> Variable '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'`

### 6. Reference Constructors
- Line 400: `ReferenceConstructor -> '[' WS_OPT ExpressionList WS_OPT ']'`
- Line 402: `ReferenceConstructor -> '{' WS_OPT ExpressionList WS_OPT '}'`

### 7. ExpressionList Definition (10 rules, lines 344-353)
These will be deleted entirely.

## Replacement Strategy

### Phase 1: Add Comma Operators to Expression

Add comma and fat-comma as binary operators in Expression:

```bnf
# Comma operator (lowest precedence, left-associative)
CommaOp -> Expression WS_OPT ',' WS_OPT Expression
CommaOp -> Expression WS_OPT '=>' WS_OPT Expression  # Fat comma
CommaOp -> %BAREWORD_ANY% WS_OPT '=>' WS_OPT Expression  # Bareword auto-quote

Expression -> CommaOp
```

**Critical**: These must have LOWEST precedence (lower than assignment).

**Perl precedence** (from `perldoc perlop`):
```
Assignment:    =, +=, -=, etc. (right-associative)
Comma:         ,  (left-associative)  ← LOWEST
```

### Phase 2: Replace ExpressionList Uses

For each location using ExpressionList, replace with appropriate construct:

#### Statement Level (Line 102)
```bnf
# OLD
Statement -> ExpressionList

# NEW
Statement -> Expression
```

**Type context**: Top-level statement expressions are in void context.

#### Return Statement (Line 162)
```bnf
# OLD
ReturnStatement -> 'return' WS_OPT '(' WS_OPT ExpressionList WS_OPT ')'

# NEW
ReturnStatement -> 'return' WS_OPT '(' WS_OPT Expression WS_OPT ')'
ReturnStatement -> 'return' WS_OPT Expression
ReturnStatement -> 'return'
```

**Type context**: Expression in list context (return can return multiple values).

#### Use Statement (Line 179)
```bnf
# OLD
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT ExpressionList

# NEW (simplified - see perldoc -f use)
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT Expression
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT String WS_OPT Expression  # use Module VERSION LIST
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT String  # use Module VERSION
UseStatement -> 'use' WS_OPT QualifiedIdentifier  # use Module
UseStatement -> 'use' WS_OPT String  # use VERSION
```

**Type context**: Expression in list context.

**Note**: String for VERSION must be literal (not general expression).

#### Parenthesized Expression (Line 268)
```bnf
# OLD
Expression -> '(' WS_OPT ExpressionList WS_OPT ')'

# NEW - Two interpretations:
Expression -> '(' WS_OPT Expression WS_OPT ')'  # Precedence grouping OR list constructor

# Alternative if we need to distinguish:
Expression -> '(' WS_OPT ')'  # Empty list
Expression -> '(' WS_OPT Expression WS_OPT ')'  # Parenthesized expression or list
```

**Type context**: Depends on usage - TypeInference determines if this is:
- Scalar context: `($x)` - precedence grouping, evaluates to $x
- List context: `($x, $y)` - list constructor, evaluates to list

#### Function Calls (6 locations)
```bnf
# OLD
FunctionCall -> Identifier '(' WS_OPT ExpressionList WS_OPT ')'

# NEW
FunctionCall -> Identifier '(' WS_OPT Expression WS_OPT ')'
FunctionCall -> Identifier '(' WS_OPT ')'  # Empty arg list
```

**Type context**: Arguments in list context.

**Apply same pattern** to all 6 function/method call rules.

#### Reference Constructors (2 locations)
```bnf
# OLD
ReferenceConstructor -> '[' WS_OPT ExpressionList WS_OPT ']'
ReferenceConstructor -> '{' WS_OPT ExpressionList WS_OPT '}'

# NEW
ReferenceConstructor -> '[' WS_OPT Expression WS_OPT ']'
ReferenceConstructor -> '[' WS_OPT ']'  # Empty array
ReferenceConstructor -> '{' WS_OPT Expression WS_OPT '}'
ReferenceConstructor -> '{' WS_OPT '}'  # Empty hash
```

**Type context**: Expression in list context.

### Phase 3: Delete ExpressionList Definition

Remove lines 344-353 entirely:
- All 10 ExpressionList production rules
- These become redundant once CommaOp is part of Expression

### Phase 4: Precedence Configuration

Update `lib/Chalk/Semiring/Precedence.pm` to recognize comma operators:

```perl
# Add to operator precedence table
my %PRECEDENCE = (
    # ... existing operators ...

    # Comma operators (LOWEST precedence)
    ','  => { level => 1, assoc => 'left' },
    '=>' => { level => 1, assoc => 'left' },  # Fat comma = comma
);
```

**Critical**: Comma must be lower precedence than assignment (which is typically level 2).

### Phase 5: TypeInference Implementation

Add `infer_type()` methods to grammar rules that impose list context:

#### UseStatement
```perl
# In lib/Chalk/Grammar/Chalk/Rule/UseStatement.pm
method infer_type($semiring, $element) {
    # The Expression argument to 'use' is always in list context
    my @children = $element->children->@*;

    # Find Expression child (after module name and optional version)
    for my $i (0 .. $#children) {
        my $child = $children[$i];
        if ($child->isa('Chalk::Semiring::TypeInference::Element')
            && $this_is_expression_argument($child)) {

            # Mark this Expression as being in list context
            $children[$i] = $child->with_container_context('list');
        }
    }

    return $semiring->create_element(
        type_obj => $element->type_obj,
        children => \@children,
    );
}
```

**Similar implementation needed for**:
- FunctionCall (arguments in list context)
- MethodCall (arguments in list context)
- ReturnStatement (expression in list context)
- ReferenceConstructor (array/hash contents in list context)

#### CommaOp
```perl
# In lib/Chalk/Grammar/Chalk/Rule/CommaOp.pm (NEW FILE)
method infer_type($semiring, $element) {
    my $context = $element->container_context // 'void';

    if ($context eq 'list') {
        # In list context, comma produces List type
        return $semiring->create_element(
            type_obj => $semiring->type_system->get_type('List'),
            children => $element->children,
            container_context => $context,
        );
    } else {
        # In scalar/void context, comma produces type of last operand
        my @children = $element->children->@*;
        my $last_child = $children[-1];

        return $semiring->create_element(
            type_obj => $last_child->type_obj,
            children => \@children,
            container_context => $context,
        );
    }
}
```

### Phase 6: TypeInference.add() Enhancement

**Current issue** (from agent investigation): `container_context` exists but is never used for disambiguation.

**Fix**: Update `TypeInference.add()` to filter based on expected context:

```perl
# In lib/Chalk/Semiring/TypeInference.pm
method add($other, $swap = undef) {
    # ... existing type join logic ...

    # If we have container context expectations, prefer compatible types
    my $self_context = $self->container_context;
    my $other_context = $other->container_context;

    if ($self_context && $other_context && $self_context ne $other_context) {
        # Contexts differ - this shouldn't happen if inference is correct
        # But if it does, this is how we'd disambiguate
        warn "Context mismatch: self=$self_context, other=$other_context";
    }

    # Type compatibility check
    if ($self_context && $self_context eq 'list') {
        # In list context, prefer List type over Scalar
        my $self_is_list = $self->type_obj->is_subtype_of('List');
        my $other_is_list = $other->type_obj->is_subtype_of('List');

        return $self if $self_is_list && !$other_is_list;
        return $other if $other_is_list && !$self_is_list;
    }

    # ... rest of existing logic ...
}
```

## Implementation Order

1. **Add CommaOp to grammar** (Phase 1)
   - Add comma operators to Expression
   - Configure precedence in Precedence.pm
   - Test: Ensure comma expressions parse

2. **Replace UseStatement** (Phase 2 - partial)
   - Change UseStatement to use Expression
   - Add UseStatement.infer_type() (Phase 5)
   - Test: `use overload '+' => 'add', '-' => 'sub'` parses unambiguously

3. **Replace other uses incrementally** (Phase 2 - rest)
   - FunctionCall
   - ReturnStatement
   - ReferenceConstructor
   - Parenthesized expressions
   - Statement-level expressions
   - Test each change individually

4. **Delete ExpressionList** (Phase 3)
   - Remove all ExpressionList grammar rules
   - Test: Full test suite passes

5. **Enhance TypeInference.add()** (Phase 6)
   - Add container_context filtering
   - Test: Ambiguities resolved correctly

## Testing Strategy

### Unit Tests

Create `t/grammar/comma-operator.t`:
```perl
# Test comma as operator in different contexts
parse_ok("1, 2, 3", "Comma operator in void context");
parse_ok("my @x = (1, 2, 3)", "Comma in list context");
parse_ok("my $x = (1, 2, 3)", "Comma in scalar context (returns 3)");
```

Create `t/grammar/use-expression.t`:
```perl
# Test use statements with Expression
parse_ok("use overload '+' => 'add';", "Single fat-comma pair");
parse_ok("use overload '+' => 'add', '-' => 'sub';", "Multiple pairs");
parse_ok("use Module 'arg1', 'arg2';", "Multiple arguments");
parse_ok("use Module;", "No arguments");
```

### Progressive Testing

From `docs/semiring-architecture.md`:
```perl
# Test each layer independently
$parser->parse($input, semiring => 'Boolean');       # Layer 1
$parser->parse($input, semiring => 'Precedence');    # Layer 2
$parser->parse($input, semiring => 'ChalkSyntax');   # Layer 3
$parser->parse($input, semiring => 'ChalkIR');       # Layer 4
```

Find which layer fails → that's where the bug is.

### Self-Hosting Test

**Critical**: The full test is `perl -Ilib t/self-hosting.t`

**Expected result**: All 279 lib/ files parse without ambiguity.

**Specific test case**: CompilationError.pm must parse without TypeInference disagreement.

## Success Criteria

- [ ] Comma and fat-comma are Expression operators with correct precedence
- [ ] ExpressionList completely removed from grammar
- [ ] All 17 uses of ExpressionList replaced with Expression
- [ ] TypeInference correctly sets container_context for list-context constructs
- [ ] TypeInference.add() filters based on container_context when needed
- [ ] Self-hosting test passes (279/279 files)
- [ ] No ambiguity errors in sequential filtering
- [ ] CompilationError.pm parses successfully
- [ ] Parser performance acceptable (no 30+ second timeouts)

## Risks and Mitigations

### Risk: Comma precedence conflicts

**Mitigation**: Set comma to lowest precedence (level 1), below assignment (level 2).

### Risk: Breaking existing code

**Mitigation**: Incremental replacement, test each grammar change individually.

### Risk: TypeInference ambiguities

**Mitigation**: Progressive testing to isolate which layer fails.

### Risk: Performance regression

**Mitigation**: Measure parse time before and after. Simpler grammar should be FASTER.

## Related Documentation

- `docs/perl-expression-semantics.md` - Why Expression is correct, ExpressionList is wrong
- `docs/semiring-architecture.md` - Sequential filtering, progressive testing
- `docs/plans/2026-01-29-expression-context-understanding.md` - Understanding investigation
- `perldoc perlop` - Perl operator precedence
- `perldoc -f use` - Use statement specification

## Architectural Discovery: Unified Comonad Pattern (2026-01-30)

### Prototype Results

**Branch**: `prototype-unified-comonad`
**Documentation**: `docs/prototype-unified-comonad-findings.md`

Successfully prototyped architecture where **Parser creates EvalContext and passes to all semirings**.

### What Was Validated

✅ Parser successfully creates and passes EvalContext to Boolean semiring
✅ Elements store and carry contexts through parsing
✅ multiply() builds proper context trees: `children => [$left_ctx, $right_ctx]`
✅ Test shows correct parent+children structure for grammar `S -> A B`
✅ Backward compatibility maintained (optional context parameter)

### Key Discovery

**All semirings should operate on same EvalContext comonad**, just with different domain values:
- **SemanticElement**: `{ context, value: IR_node }`
- **TypeInferenceElement**: `{ context, value: { type_obj, type_env } }`
- **PrecedenceElement**: `{ context, value: { valid, operator, level } }`
- **BooleanElement**: `{ context, value: bool }`

This eliminates:
- on_complete() metadata passing (rule is in context)
- Cross-semiring peeking (TypeInference doesn't peek at Semantic)
- Duplicate position tracking (all use `context->start_pos/end_pos`)

### Trade-offs

**Pros**:
- Clearer data flow (Parser → context → semiring)
- Explicit context management (no hidden state)
- Natural comonad structure (extract/extend/duplicate)
- Eliminates architectural violations

**Cons**:
- Performance cost (more allocations, no cached identities)
- All semirings must be updated
- Identity element semantics change

### Decision Point

**Before proceeding with ExpressionList removal**, must decide:

**Option A**: Adopt unified comonad architecture
- Update all semirings (Boolean, Precedence, TypeInference, SemanticValidation)
- Refactor Parser to create contexts
- Benchmark performance impact
- **Estimated effort**: 10-15 days

**Option B**: Keep current architecture
- Fix immediate bugs (TypeInference/SemanticValidation multiply validation)
- Accept architectural complexity
- Proceed with ExpressionList removal
- **Estimated effort**: 2-3 days

**Recommendation**: Pursue Option A. The architectural benefits (elimination of peeking, unified API, proper comonad structure) outweigh the implementation cost.

## Next Steps

### If Adopting Unified Architecture (Recommended):

1. **Extend prototype to TypeInference and Semantic** (highest value semirings)
2. **Benchmark performance** on real Chalk code
3. **If acceptable**: Extend to Precedence and SemanticValidation
4. **Then**: Proceed with ExpressionList removal using unified architecture

### If Keeping Current Architecture:

1. Fix TypeInference.multiply() to reject type-invalid sequences
2. Fix SemanticValidation.multiply() to validate semantic sequences
3. Proceed with ExpressionList removal
4. Accept cross-semiring peeking as necessary evil
