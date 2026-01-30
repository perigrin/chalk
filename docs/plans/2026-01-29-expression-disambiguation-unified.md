# Expression Disambiguation in use Statements - Unified Plan

**Date**: 2026-01-29
**Status**: ⚠️ **REVISION REQUIRED - DO NOT IMPLEMENT**
**Related Issue**: ❌ #562 is WRONG (C++ keywords) - See #571 or #605

---

## ⚠️ CRITICAL: PLAN REQUIRES REVISION

**Three senior architect reviews (2026-01-30) identified CRITICAL BLOCKERS:**

1. ❌ **Wrong issue number** - #562 is about C++ keywords, not use overload parsing
2. ❌ **No evidence** - Phase 1 investigation not executed (no actual error captured)
3. ❌ **Contradictory claims** - Plan argues both FOR and AGAINST ExpressionList

**DO NOT PROCEED with implementation until:**
- Issue number corrected (#571 or #605)
- Phase 1 investigation completed (capture actual error)
- Contradictions resolved (choose ONE approach)
- Comonad separated into independent RFC

**See**: "Senior Architect Review Findings" section below for details.

---

## Executive Summary

Sequential filtering correctly detects parse ambiguities in `use overload` statements. The root cause is grammar ambiguity in ExpressionList parsing, where the comma and fat-comma operators can be interpreted in multiple ways. This document presents a unified approach to fixing the ambiguity through grammar refinement and validation layers, aligned with the sequential filtering architecture.

## Problem Statement

### Observable Behavior

```perl
use overload '+' => 'add', '-' => 'sub';
```

**Current behavior**:
- Sequential filtering dies with ambiguity error
- TypeInference chooses one parse alternative
- Boolean/Precedence/SemanticValidation choose another
- Performance: Multi-line form takes 141 seconds vs <1 second for single-line

**Root cause**: ExpressionList grammar allows multiple valid parse trees for the same input.

### The Fundamental Issue

Perl does not have an "ExpressionList" construct. Instead, Perl has:
- **Expressions** (singular)
- **Context** (scalar vs list)
- The **comma operator** which evaluates to a list in list context

Our grammar currently models this as:

```bnf
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT ExpressionList

ExpressionList -> Expression WS_OPT ',' WS_OPT ExpressionList
ExpressionList -> Expression WS_OPT '=>' WS_OPT Expression WS_OPT ',' WS_OPT ExpressionList
```

This creates ambiguity because:
1. `=>` can be part of ExpressionList structure
2. `=>` can be part of an Expression (as an operator)
3. The comma can be both a separator AND an operator
4. Multiple valid parse trees exist for the same input

### Evidence: Perl's Canonical Parse

Using `B::Deparse` to see how Perl actually parses this:

```perl
# Input
use overload
  '+'  => 'add',
  '*'  => 'multiply',
  '""' => 'to_string';

# Perl's canonical parse
use overload ('+', 'add', '*', 'multiply', '""', 'to_string');
```

**Key insight**: It's a **flat list** of comma-separated values, not a nested structure of fat-comma pairs.

## Sequential Filtering Architecture Context

The sequential filtering architecture (see `docs/plans/2026-01-10-composite-sequential-filtering-design.md`) establishes that:

1. **ChalkSyntax MUST produce ONE unambiguous parse** before Semantic generates IR
2. Semirings filter progressively: Boolean → Precedence → TypeInference → SemanticValidation
3. Each semiring filters independently; if any disagree, it's a grammar bug
4. Short-circuit on invalid: any semiring returning `add_id` aborts immediately

**Critical principle**: If TypeInference disagrees with other semirings, **the bug is in an earlier layer**, not in TypeInference. The grammar or validation rules are incomplete.

## Solution Design

We have three complementary approaches that work together:

### Approach 1: Remove ExpressionList from Grammar (Primary Solution)

**Rationale**: ExpressionList doesn't match Perl's semantics and creates ambiguity.

**Changes**:

```bnf
# Remove ambiguous ExpressionList rules
# Replace with direct Expression usage

UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT Expression
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT VersionNumber WS_OPT Expression
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT VersionNumber
UseStatement -> 'use' WS_OPT QualifiedIdentifier
UseStatement -> 'use' WS_OPT VersionNumber
```

**Key insight**: Only ONE Expression slot after the module (and optional version). The Expression contains comma operators, which are evaluated based on context.

**Advantages**:
- Matches Perl's actual semantics precisely
- Eliminates grammar-level ambiguity
- Simpler grammar structure
- Context determines interpretation, not grammar structure

**Implementation**: See `docs/plans/2026-01-29-remove-expressionlist.md` for detailed migration plan.

### Approach 2: Type-Based Disambiguation (Supporting Layer)

**Rationale**: Even with grammar changes, we need type information to flow through the parse tree.

**Type signature for use statement**: `use SCALAR LIST?`
- MODULE: Scalar type (bareword module name)
- VERSION: Scalar type (version literal)
- ARGS: List type (import arguments)

**TypeInference role**: Annotate the parse tree with context information, NOT to choose between parses.

```perl
# In UseStatement semantic rules
method infer_type($semiring, $element) {
    # UseStatement knows its Expression argument is in list context
    # Mark it so semantic action evaluates it correctly

    my @children = $element->children->@*;

    for my $child (@children) {
        if ($this_is_the_expression_argument) {
            # Return element annotated with list context
            return create_new_element_with(
                container_context => 'list'
            );
        }
    }
}
```

**Effect**: When `UseStatement.evaluate()` runs, it knows to evaluate the Expression as a List.

**Comma operator in list context**:
```perl
# The comma operator produces different results based on context
my $x = (1, 2, 3);     # Scalar context: $x = 3 (last value)
my @x = (1, 2, 3);     # List context: @x = (1, 2, 3)
use Module (1, 2, 3);  # List context: passes (1, 2, 3)
```

### Approach 3: Precedence/Validation Refinement (Fallback)

**Rationale**: If grammar changes aren't sufficient, enhance validation layers.

**Precedence semiring**: Should recognize that comma/fat-comma have specific precedence relationships that can eliminate some parse alternatives.

**SemanticValidation**: Context-aware validation that understands UseStatement expects a list-producing expression.

## Implementation Plan

### Phase 1: Investigation and Evidence Gathering

**CRITICAL**: Before implementing, capture the actual error to validate our understanding.

1. **Capture actual error**:
   ```bash
   cd /home/perigrin/dev/chalk
   git checkout sequential-filtering-clean
   perl -Ilib t/self-hosting.t 2>&1 | tee ambiguity-error.log
   ```

2. **Analyze the error**:
   - What are the two parse alternatives?
   - Which file triggers it? (Hypothesis: CompilationError.pm)
   - Why does TypeInference choose differently?
   - What do `self` and `other` represent?

3. **Add debugging**:
   ```bash
   DEBUG_PARSE_ALTERNATIVES=1 perl -Ilib t/self-hosting.t
   ```
   - Show what TypeInference.add() sees
   - Show their types and contexts
   - Understand the actual decision being made

4. **Document findings**: Update this document with actual behavior, not speculation.

### Phase 2: Grammar Simplification (Preferred)

1. **Remove ExpressionList from UseStatement**:
   - Update `grammar/chalk.bnf` to use Expression instead
   - Remove ambiguous ExpressionList rules (or mark deprecated)
   - Ensure all UseStatement forms are covered

2. **Update semantic actions**:
   - Modify `lib/Chalk/Grammar/Chalk/Rule/UseStatement.pm`
   - Ensure Expression is evaluated in list context
   - Handle comma operator correctly

3. **Test progressive layers**:
   ```perl
   # Layer 1: Boolean only - does it parse at all?
   # Layer 2: Boolean + Precedence - are operators valid?
   # Layer 3: ChalkSyntax (all validation) - unambiguous?
   # Layer 4: ChalkIR (validation + IR) - correct IR?
   ```

### Phase 3: Type Information Flow (Supporting)

1. **Add context annotation to UseStatement**:
   ```perl
   # In lib/Chalk/Grammar/Chalk/Rule/UseStatement.pm
   method infer_type($semiring, $element) {
       # Mark Expression child as list context
       return annotate_expression_child_with_list_context($element);
   }
   ```

2. **Update TypeInference** (if needed):
   ```perl
   # Only if grammar changes aren't sufficient
   method add($other, $swap = undef) {
       # Existing type join logic...

       # If we have context expectations, validate compatibility
       if ($expected_type && $self->type_obj != $other->type_obj) {
           my $self_compatible = $self->type_matches_context($expected_type);
           my $other_compatible = $other->type_matches_context($expected_type);

           return $self if $self_compatible && !$other_compatible;
           return $other if $other_compatible && !$self_compatible;
       }

       # Rest of existing logic...
   }
   ```

### Phase 4: Validation (If Still Needed)

Only implement if Phases 2-3 don't resolve all ambiguities.

1. **Enhance Precedence validation**: Teach precedence rules about comma in different contexts
2. **Enhance SemanticValidation**: Add UseStatement-specific validation rules

## Testing Strategy

### Progressive Layer Testing

Test each layer independently to find where issues occur:

```perl
# Test with Boolean only
my $bool = ChalkGrammar->new(semiring => Boolean->new);
$bool->parse($input);  # Should accept multiple parses

# Test with Boolean + Precedence
my $prec = ChalkSyntax->new(semirings => [Boolean, Precedence]);
$prec->parse($input);  # Should reduce alternatives

# Test with full ChalkSyntax
my $syntax = ChalkSyntax->new;
$syntax->parse($input);  # Must produce ONE parse

# Test with ChalkIR
my $ir = ChalkIR->new;
$ir->parse($input);  # Must produce correct IR
```

Find the layer where it breaks → that's where the bug is.

### Test Cases

```perl
# Test 1: Single-line use overload
use overload '+' => 'add', '-' => 'sub';

# Test 2: Multi-line use overload
use overload
  '+'  => 'add',
  '*'  => 'multiply',
  '""' => 'to_string';

# Test 3: Use with no arguments
use strict;

# Test 4: Use with version
use feature 5.42;

# Test 5: Use with version and list
use feature 5.42 qw(say state);

# Test 6: Use with single string
use experimental 'class';

# Test 7: Use with qw list
use feature qw(say state);

# Test 8: Trailing comma
use overload '+' => 'add',;

# Test 9: Single pair
use overload '""' => 'as_string', fallback => 1;
```

### Verification

1. **Run self-hosting test**: All 279 lib/ files parse without ambiguity
2. **Check specific files**: CompilationError.pm and other files with `use overload`
3. **Performance test**: Multi-line should parse fast (<1s, not 141s)
4. **Type correctness**: Verify context annotations are correct
5. **IR correctness**: Verify generated IR matches expectations

## Success Criteria

- [ ] All lib/ files with `use overload` parse unambiguously
- [ ] Sequential filtering detects NO ambiguities in lib/ files
- [ ] Self-hosting test passes (t/self-hosting.t)
- [ ] Parse performance is acceptable (<1s for multi-line use statements)
- [ ] Progressive layer testing shows ambiguity resolves at correct layer
- [ ] TypeInference and other semirings agree on parse choice
- [ ] Generated IR matches Perl's semantic interpretation

## Current Unknowns (To Investigate)

### Question 1: Is there actually parse ambiguity?

**ANSWER (from investigation 2026-01-29)**: YES - Sequential filtering on `sequential-filtering-clean` branch detects ambiguity in parsing Chalk source files (specifically grammar/chalk.bnf).

**Evidence**:
- Input: `grammar/chalk.bnf` (not a Chalk program, but used as test input)
- Error: TypeInference semiring disagreed with Boolean/Precedence/SemanticValidation in Composite.add()
- Branch: `sequential-filtering-clean` with sequential filtering implementation
- The ambiguity is REAL and detected by the architecture

**Remaining unknown**: Exact input string that triggers the disagreement (need to capture from actual test run).

### Question 2: What was the CI error?

**PARTIAL ANSWER**:
```
Ambiguous parse in Composite.add():
  Boolean chose self
  Precedence chose self
  TypeInference chose other  ← Disagrees!
  SemanticValidation chose self
```

**What we know**:
- Triggered when parsing `grammar/chalk.bnf` with ChalkSyntax parser
- TypeInference semiring made different choice than other three semirings
- Sequential filtering correctly detected the disagreement and died
- This proves the architecture is working as designed

**Still unknown**:
- Exact input substring causing disagreement
- What "self" and "other" parse alternatives represent
- Which operator or construct causes the split (`/` vs `=~` was mentioned in error)

**How to answer**: Run with `DEBUG_PARSE_ALTERNATIVES=1` to see the actual alternatives.

### Question 3: Does TypeInference currently use container_context for filtering?

**ANSWER**: NO - `container_context` field exists in TypeInferenceElement (line 18) but is:
- Preserved through multiply() and add() operations
- NOT used for disambiguation decisions
- Available for future semantic action use

**Architectural Finding**: TypeInference CANNOT use context for filtering because it uses **tropical semiring with lattice join** for add(). Lattice join always succeeds (worst case returns `Any` top type), so TypeInference cannot return `add_id` to reject alternatives.

**Implication**: If context-based filtering is needed, it must happen in:
- **Precedence semiring** (can reject based on operator precedence rules), OR
- **SemanticValidation semiring** (can validate semantic constraints)

NOT in TypeInference, which only annotates types.

### Question 4: What is the actual root cause?

**ANSWER**: Multiple contributing factors discovered:

**A. Grammar Ambiguity (CONFIRMED)**: ExpressionList grammar allows overlapping parses
- `ExpressionList -> Expression WS_OPT ',' WS_OPT ExpressionList`
- `ExpressionList -> Expression WS_OPT '=>' WS_OPT Expression WS_OPT ',' WS_OPT ExpressionList`
- If Expression can contain `,` or `=>` operators, creates ambiguity with ExpressionList structure

**B. TypeInference Architectural Limitation (CONFIRMED)**: TypeInference uses lattice operations (join/meet) which cannot express "this parse is invalid"
- Join always produces a valid type (worst case: `Any`)
- Cannot return `add_id` to reject alternatives
- This is WHY TypeInference disagrees - it's using different algebra than Boolean/Precedence/SemanticValidation

**C. Unified Comonad Fixes Multiply() Validation (CONFIRMED)**: The architectural flaw is that multiply() cannot properly validate sequences

**The Real Problem**:
- multiply() is WHERE filtering should happen (combines sequential parse components)
- TypeInference.multiply() currently does type meet but CANNOT reject invalid sequences
- Even when types contradict (meet produces bottom), it returns a valid element with error recorded
- **Missing**: No way to return semiring's add_id to short-circuit invalid sequences

**What TypeInference.multiply() Lacks**:
1. Access to rule/grammar context (what rule is being parsed?)
2. Reference to semiring's add_id (to reject invalid sequences)
3. Parse tree structure (what are we actually combining?)

**How Unified Comonad Fixes This**:
```perl
method multiply($other, $swap = undef) {
    my $rule = $self->context->rule;  # NOW AVAILABLE

    # Can validate based on rule expectations
    if ($rule->expects_list_context() && !$other->type_obj->is_list_compatible()) {
        return $semiring_add_id;  # REJECT: type mismatch for this rule
    }

    # Type contradiction detection
    my $meet_type = $type_obj->meet($other_type);
    if ($meet_type->is_bottom() && !$type_obj->is_bottom() && !$other_type->is_bottom()) {
        return $semiring_add_id;  # REJECT: contradictory types
    }

    # Build valid context tree
    return TypeInferenceElement->new(...);
}
```

**Verdict**: NOT a red herring - this IS the architectural fix needed for proper multiply() validation

**D. Grammar Naming Confusion (CONFIRMED - Grammar Analysis 2026-01-30)**: Chalk's naming is backwards from Perl's

**Critical Discovery**: Chalk's current "Expression" is what Perl calls "term"!

**Perl's Actual Hierarchy** (from perly.y):
```
expr:
  - expr ANDOP expr
  - expr OROP expr
  - listexpr

listexpr:
  - listexpr ',' term
  - listexpr ','
  - term

term:
  - (all actual operators: arithmetic, ternary, references, literals, etc.)
```

**Chalk's Current Hierarchy**:
```
Expression:
  - Literal, Variable, Identifier
  - Assignment, Ternary, LogicalOp, ArithmeticOp, etc.
  - (all the things Perl calls "term")

ExpressionList:
  - Expression ',' ExpressionList
  - (should be comma-separated Terms)
```

**The Problem**: Chalk calls "term" → "Expression" and "listexpr" → "ExpressionList", but is **too permissive** because:
- Chalk's Expression includes everything (no separation of term vs expr)
- Chalk's ExpressionList uses Expression (should use Term)

**E. ExpressionList Semantic Model (CONFIRMED - Perl Research 2026-01-30)**: Perl DOES have LIST as a first-class construct

**Evidence from Perl Documentation**:
- **perlglossary**: "LIST: A syntactic construct representing a comma-separated list of expressions"
- **perldoc -f use**: Explicitly documents `use Module LIST` (not `use Module EXPR`)
- **perlop**: Comma has dual semantics - operator (scalar context) vs separator (list context)

**Critical Finding**: The claim "Perl doesn't have ExpressionList, just Expression in context" is **WRONG per Perl documentation**.

**Three Orthogonal Concepts**:
1. **LIST** = comma-separated expressions (syntactic construct)
2. **Expression** = can be evaluated in list or scalar context
3. **Context** = how expressions are evaluated (list vs scalar)

**Implication for Chalk**:
- ExpressionList SHOULD exist (matches Perl's documented LIST construct)
- Current problem: Chalk allows full Expression in ExpressionList, creating overlap
- Solution: Restrict to `Term` (expressions without comma operators) in ExpressionList, matching Perl's `listexpr` using `term` productions

**Root Cause Priority**:
1. **PRIMARY**: TypeInference cannot validate in multiply() due to architectural flaw (C)
   - Missing access to rule/grammar context
   - Missing reference to semiring's add_id for rejection
   - This CAUSES the algebra mismatch (B) - TypeInference can't short-circuit
2. **SECONDARY**: Grammar ambiguity (A) creates alternatives that need filtering
3. **TERTIARY**: Semantic model divergence from Perl (D) - LIST is first-class construct

**Critical Insight**: The unified comonad is NOT separate from the bug fix - it IS the architectural fix that enables proper multiply() validation across all semirings.

## Alternative Approaches Considered

### Alternative 1: CommaList Grammar Rule

Create a dedicated grammar rule:

```bnf
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT CommaList

CommaList -> CommaElement
CommaList -> CommaElement WS_OPT ',' WS_OPT CommaList

CommaElement -> Expression
CommaElement -> %BAREWORD_ANY% WS_OPT '=>' WS_OPT Expression
```

**Why rejected**: ExpressionList concept itself is wrong. Better to remove it entirely and use Expression with context.

### Alternative 2: Require Parentheses

```bnf
UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT '(' Expression ')'
```

**Why rejected**: Doesn't match Perl syntax. Perl doesn't require parentheses for `use` arguments.

### Alternative 3: Type-Only Solution

Keep grammar ambiguous, rely entirely on TypeInference to filter.

**Why rejected**: Violates sequential filtering principle. Grammar should be unambiguous. TypeInference should only add type information, not resolve structural ambiguity.

## Relationship to Sequential Filtering Architecture

This fix integrates with the sequential filtering architecture:

1. **Boolean**: Accept all syntactically valid parses
2. **Precedence**: Validate operator precedence relationships
3. **TypeInference**: Annotate with type/context information (not filter!)
4. **SemanticValidation**: Validate Perl-specific rules
5. **Semantic**: Build IR from single resolved parse

**Before this fix**: TypeInference had to filter parses (wrong layer for structural disambiguation)

**After this fix**: Grammar produces one unambiguous parse, TypeInference only annotates it with context

## Implementation Phases and Priorities

### Immediate (Phase 1) - REQUIRED FIRST
- [ ] Capture actual ambiguity error from CI
- [ ] Identify which file triggers it
- [ ] Understand what "self" and "other" represent
- [ ] Add debug output to see parse alternatives

### High Priority (Phase 2) - GRAMMAR FIX
- [ ] Remove ExpressionList from UseStatement (use Expression instead)
- [ ] Update UseStatement semantic action for list context
- [ ] Test with progressive layers
- [ ] Verify self-hosting test passes

### Medium Priority (Phase 3) - TYPE FLOW
- [ ] Add context annotation to UseStatement
- [ ] Ensure Expression evaluates correctly in list context
- [ ] Document context propagation mechanism

### Low Priority (Phase 4) - FALLBACK
- [ ] Enhance validation layers if needed
- [ ] Add context-aware precedence rules
- [ ] Improve error messages

## Documentation Updates

After implementation:

1. Update `docs/perl-expression-semantics.md` with final approach
2. Document context propagation in TypeInference layer
3. Add examples to sequential filtering documentation
4. Update grammar documentation
5. Document any new semantic rules

## Related Work

- Sequential filtering architecture: `docs/plans/2026-01-10-composite-sequential-filtering-design.md`
- Expression semantics: `docs/perl-expression-semantics.md`
- Type system foundation: `docs/perl-types-practical.md`
- Precedence validation: `docs/precedence-semiring.md`
- ExpressionList removal plan: `docs/plans/2026-01-29-remove-expressionlist.md`

## References

- Issue #562: Multi-line `use overload` parsing failure
- Perl's perly.y: `use_statement` grammar rule
- `perldoc -f use`: Full use statement specification
- `B::Deparse`: Shows Perl's canonical parse
- Earlier conversation: Investigation of ExpressionList hanging (2026-01-07)

## Architectural Discovery: Unified Comonad Pattern

### Investigation Results (2026-01-29)

During investigation of the TypeInference disagreement with other semirings, we discovered a **fundamental architectural issue**: TypeInference and SemanticValidation semirings lack access to full parse context in their `multiply()` methods, preventing proper sequential validation.

**Key Finding**: Only the Semantic semiring currently has EvalContext comonad structure. Other semirings have heterogeneous element types without access to rule, grammar, or parse tree information needed for context-aware validation.

### Prototype Validation

We prototyped a unified architecture where **Parser creates EvalContext** and passes it to all semirings:

**Branch**: `prototype-unified-comonad` (based on `sequential-filtering-clean`)
**Documentation**: `docs/prototype-unified-comonad-findings.md`
**Test**: `t/prototype/boolean-comonad.t` (10/10 passing)

**Architecture**:
```perl
# Parser creates context at prediction points
my $ctx = Chalk::EvalContext->new(
    focus => undef,
    children => [],
    start_pos => $pos,
    end_pos => $pos,
    env => {},
    grammar => $grammar,
    rule => $rule
);

# Passes to semiring
my $element = $semiring->init_element_from_rule($rule, $ctx);

# Element stores context
# field $context :param :reader = undef;  # EvalContext comonad

# multiply() builds context trees
method multiply($other, $swap = undef) {
    my @new_children = ( @{ $self->context->children }, $other->context );
    my $combined_ctx = Chalk::EvalContext->new(
        focus => $result_value,
        children => \@new_children,
        start_pos => $self->context->start_pos,
        end_pos => $other->context->end_pos,
        rule => $self->context->rule,
        ...
    );
    return NewElement->new(context => $combined_ctx, ...);
}
```

**Prototype Results**:
- ✅ Parser successfully creates and passes EvalContext to Boolean semiring
- ✅ Elements store and carry contexts through parsing
- ✅ multiply() builds proper context trees with children
- ✅ Test validates 2 children for grammar `S -> A B`
- ✅ All tests pass (10/10)

**Trade-offs Identified**:

**Pros**:
- Clearer data flow (Parser → semiring → element → multiply() → new element)
- Explicit context management (no hidden state)
- Natural comonad structure (extract/extend/duplicate operations)
- All semirings have access to full parse information for validation
- TypeInference and SemanticValidation can validate sequences properly in multiply()

**Cons**:
- Performance cost: Creates new elements in multiply() instead of using cached identities
- Memory impact: More allocations, no sharing of identity elements
- Backward compatibility: All semirings must be updated
- Identity element semantics change: Can't store parse-specific context in shared identity

### Architectural Decision Point

We now face a fundamental choice:

**Option A: Adopt Unified Comonad Architecture**
- Extend prototype to TypeInference and Semantic semirings
- Update all semirings to operate on EvalContext with domain-specific values
- Benchmark performance on real Chalk code
- Enables proper context-aware validation in multiply()
- Aligns with principle: "All semirings should operate on same underlying structure"

**Option B: Keep Current Architecture and Fix Immediate Bugs**
- Proceed with ExpressionList removal as planned
- Fix TypeInference to work within current constraints
- Leave architectural refactoring for future work
- Faster path to resolving Issue #562

### Recommendation

**Adopt Option A** (Unified Comonad Architecture) because:

1. **Root Cause**: Current issue is TypeInference can't validate sequences properly in multiply() due to lack of context
2. **Architectural Principle**: "SPPF is a semiring, Semantic is a semiring... all semirings should operate on the same underlying structure (the comonad)"
3. **Long-term Correctness**: Enables all semirings to perform context-aware validation as intended by sequential filtering
4. **Performance**: Can optimize later with techniques documented in prototype findings (object pooling, lazy context building, structural sharing)

**Next Steps if Adopting Option A**:
1. Extend prototype to TypeInference semiring
2. Extend prototype to Semantic semiring (already has EvalContext, just formalize)
3. Benchmark on real Chalk code (self-hosting test)
4. If performance acceptable, update all semirings
5. THEN proceed with ExpressionList removal

**Next Steps if Adopting Option B**:
1. Proceed directly to Phase 2: Grammar Simplification
2. Document architectural issue for future work
3. Work within current semiring constraints

## Senior Architect Review Findings (2026-01-30)

**Three independent senior architects reviewed this plan. All three identified CRITICAL BLOCKERS.**

### Consensus Findings (All Three Reviewers Agree):

**🚨 CRITICAL BLOCKERS - IMPLEMENTATION CANNOT PROCEED:**

1. **❌ WRONG ISSUE NUMBER**
   - Issue #562 is "Parameter name 'class' conflicts with C++ keyword"
   - NOT related to use overload parsing
   - Actual relevant issues: #571 or #605
   - **Impact**: Plan is solving the wrong problem

2. **❌ PHASE 1 INVESTIGATION NOT EXECUTED**
   - Plan marks it "CRITICAL" (line 161) but never ran it
   - No actual error message captured
   - No parse alternatives documented
   - **Impact**: All solutions are speculative without evidence

3. **❌ CONTRADICTORY PERL SEMANTICS CLAIMS**
   - Lines 8, 81: "Perl doesn't have ExpressionList" → remove it
   - Lines 469, 473: "Perl DOES have LIST" → keep ExpressionList
   - **Impact**: Plan argues for opposite solutions simultaneously

**✅ WHAT REVIEWERS CONFIRMED AS CORRECT:**

- ✅ Perl DOES have LIST as first-class construct (verified in perlglossary, perly.y)
- ✅ Sequential filtering implemented correctly in Composite.pm
- ✅ Perl has three-level hierarchy: term → listexpr → expr (verified in perly.y)
- ✅ Chalk's naming is backwards (Chalk Expression ≈ Perl term)

### Individual Review Findings:

**Review #1 - Coherence Expert:**
- Plan updated multiple times but created MORE contradictions
- Comonad presented as both PRIMARY fix (line 479) AND separate initiative (line 717)
- Success criteria don't match actual problem (targets use overload but error is in grammar/chalk.bnf)
- "Next Steps" section confusingly mixes blockers, findings, and future work

**Review #2 - Technical Architect:**
- TypeInference.multiply() behavior is **INTENTIONAL DESIGN**, not architectural flaw
- Soft failures (bottom type + errors) prevent breaking multi-statement programs (see TypeInference.pm lines 361-369)
- Unified comonad is useful but NOT required for immediate bug fix
- Should be separate RFC with performance benchmarks
- Proposed grammar refactoring conflicts with Chalk's architectural decision (flat grammar + Precedence semiring)

**Review #3 - Perl Expert (WINNER):**
- ✅ Three-level hierarchy claims verified against actual perly.y source
- ❌ **MISSING VERSION HANDLING**: `use Module VERSION, LIST` not supported in current grammar
- ❌ **MISSING EDGE CASE**: `use Module ()` vs `use Module` have different semantics (import called vs not called)
- Real ambiguity likely simpler: ExpressionList has both left-recursive AND right-recursive paths
- Example: `Expression => Expression , ExpressionList` creates parsing ambiguity

### Immediate Actions Required (All Reviewers Agree):

**BEFORE ANY DESIGN OR IMPLEMENTATION:**

1. **Fix issue number** - Replace all #562 references with #571 or #605
2. **Execute Phase 1 fully**:
   ```bash
   cd /home/perigrin/dev/chalk
   git checkout sequential-filtering-clean
   DEBUG_PARSE_ALTERNATIVES=1 perl -Ilib t/self-hosting.t 2>&1 | tee ambiguity-error.log
   ```
3. **Analyze real error**:
   - What input triggers it?
   - What are "self" and "other" alternatives?
   - Which semiring disagrees?
   - Is it actually about use overload or something else?
4. **Resolve contradictions**:
   - Decide: Keep ExpressionList (matches Perl) OR remove it?
   - Update plan to have ONE consistent position
5. **Separate comonad discussion** into independent RFC with benchmarks

### Verdict from All Reviewers:

**DO NOT IMPLEMENT THIS PLAN AS WRITTEN**

The plan contains critical errors and internal contradictions that would lead to implementing the wrong solution. Complete the investigation phase first, then revise plan based on actual evidence.

**Estimated Time to Fix Blockers**: 1-2 days

---

## Next Steps

### CRITICAL CORRECTIONS NEEDED FIRST

Based on three independent senior architect reviews (2026-01-30):

1. **❌ WRONG ISSUE NUMBER**: Issue #562 is "Parameter name 'class' conflicts with C++ keyword" - NOT about use overload parsing
   - **Action**: Find correct issue number (possibly #571 or #605) or create new issue
   - **Blocker**: Cannot proceed without knowing what we're actually fixing

2. **❌ INCOMPLETE INVESTIGATION**: Phase 1 not yet executed despite being marked "CRITICAL"
   - **Action**: Capture actual error with `DEBUG_PARSE_ALTERNATIVES=1`
   - **Action**: Get exact input string and parse alternatives
   - **Blocker**: All solutions are speculative without this data

3. **❌ PERL SEMANTICS ERROR**: Plan claims "Perl doesn't have ExpressionList" but Perl DOES have `listexpr` in perly.y
   - **Action**: Study actual Perl grammar (perly.y) for use statement
   - **Action**: Verify `use MODULE VERSION, LIST` form is valid (it is)
   - **Impact**: Proposed grammar may diverge from Perl semantics

### ARCHITECTURAL DECISION REQUIRED

**DO NOT CONFLATE THESE TWO DECISIONS**:

**Decision A: How to fix immediate ambiguity?**
- Option A1: Remove ExpressionList (grammar simplification)
- Option A2: Introduce Term construct (conservative, matches Perl)
- Option A3: Enhance Precedence/SemanticValidation filtering

**Decision B: Adopt unified comonad architecture?**
- This is a SEPARATE architectural improvement
- Not required to fix the immediate ambiguity
- Should be evaluated independently with benchmarks
- Requires separate RFC/proposal

**Recommendation from reviewers**:
- Treat unified comonad as separate work
- Focus Decision A on fixing immediate grammar issue
- Complete Phase 1 investigation BEFORE choosing A1/A2/A3

### IMMEDIATE ACTIONS (In Order)

1. **✅ COMPLETE PHASE 1 INVESTIGATION**:
   ```bash
   cd /home/perigrin/dev/chalk
   git checkout sequential-filtering-clean
   DEBUG_PARSE_ALTERNATIVES=1 perl -Ilib t/self-hosting.t 2>&1 | tee ambiguity-error-full.log
   ```
   - Capture exact error message
   - Identify triggering input string
   - See what "self" and "other" alternatives are
   - Verify which operators cause the split

2. **✅ VERIFY ISSUE NUMBER**:
   ```bash
   gh issue view 562  # Should show C++ keyword issue
   gh issue list --label "grammar" --label "parsing"
   ```
   - Find or create correct issue for use overload parsing
   - Update all references in this plan

3. **✅ STUDY PERL GRAMMAR**:
   - Read perly.y `bare_statement_utilize` production
   - Understand `optlistexpr` vs `listexpr` vs `term`
   - Document how Perl actually handles `use MODULE VERSION, LIST`

### THEN CONTINUE WITH ORIGINAL PLAN

4. **Design fix based on evidence** (not speculation)
5. **Choose grammar approach** (A1: remove ExpressionList OR A2: introduce Term)
6. **Implement chosen approach**
7. **Test thoroughly with progressive layers**
8. **Document findings and update related plans**

### Grammar Analysis Results (2026-01-30)

**Agent Review of chalk.bnf** found:

**Current State**:
- ✅ Comma and fat-comma are NOT Expression operators (prevents one overlap)
- ❌ ExpressionList uses full Expression instead of Term (diverges from Perl)
- ❌ No Term production exists (needed to match Perl's hierarchy)
- ⚠️ Minor structural ambiguities in ExpressionList rules (trailing comma variations)

**Key Finding**: Chalk's naming is backwards:
- Chalk "Expression" ≈ Perl "term" (the actual expressions)
- Chalk "ExpressionList" ≈ Perl "listexpr" (comma-separated)
- Chalk MISSING ≈ Perl "expr" (logical combinations of lists)

**Recommended Fix**: Introduce proper three-level hierarchy:
```bnf
# Level 1: Term (atomic expressions - Perl's "term")
Term -> Literal | Variable | Assignment | Ternary | ArithmeticOp | ...

# Level 2: ListExpression (comma-separated - Perl's "listexpr")
ListExpression -> Term
ListExpression -> Term ',' ListExpression
ListExpression -> Term '=>' Term ',' ListExpression

# Level 3: Expression (logical combinations - Perl's "expr")
Expression -> Term
Expression -> ListExpression
Expression -> Expression ANDOP Expression
Expression -> Expression OROP Expression
```

**Impact**: This refactoring would:
- Match Perl's documented three-level hierarchy
- Prevent ambiguity by restricting ListExpression to use Term
- Allow comma to be both separator (in ListExpression) and operator (in future Expression extensions)
- Align Chalk's grammar with Perl's actual design

**See**: Full analysis in agent output above with line number citations and specific ambiguity examples.

### SEPARATE TRACK: Unified Comonad Architecture

If pursuing unified comonad (Decision B):
- Create separate RFC document
- Benchmark prototype on real Chalk code
- Measure performance impact (allocations, memory, parse time)
- Evaluate benefit vs cost independently
- Do NOT tie to immediate bug fix
