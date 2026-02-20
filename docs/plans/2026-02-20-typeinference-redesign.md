# TypeInference Redesign: Extend Model + should_scan Protocol

**Supersedes**: `2026-02-19-typeinference-extend-redesign.md` (which covered
the extend model only; this document adds `should_scan` and incorporates
decisions from the brainstorming session).

## Problem

TypeInference has two structural problems:

1. **Flat merge destroys the comonad.** `on_complete` uses `_tags()` to flatten
   the Context tree into a hash, reads child information from that hash, then
   rebuilds a new Context with propagated tags. This works *against* the
   comonad instead of *with* it. The catch-all rule copies 6 tags upward solely
   to compensate for this flat merge.

2. **Keyword rejection is scan-time context that TypeInference can't see.**
   When `class` appears as a QualifiedIdentifier, TypeInference rejects it at
   Atom on_complete. But `class => "Foo"` (fat-arrow context) needs `class`
   admitted as an identifier because the LHS of `=>` is cast to String. The
   Earley parser has the information to distinguish these cases (is
   ClassDeclaration predicted at this position?), but TypeInference can't query
   the chart.

## Design Overview

Two changes, layered:

1. **`should_scan` semiring protocol** — the parser asks the semiring "should I
   admit this scan?" before matching. Enables syntax-aware lexing: keyword
   rejection becomes a chart-context decision, not a tag-and-propagate hack.

2. **Extend-based value model** — TypeInference values become Contexts.
   `on_complete` uses `extend()` to compute types from children's types.
   Eliminates `_tags()`, catch-all propagation, and flat merging.

These are independent and can be implemented in either order, but `should_scan`
is simpler and should go first.

## Part 1: should_scan Protocol

### Concept: Syntax-Aware Lexing

The insight comes from Kegler/Marpa: the parser's predicted items tell the
scanner which tokens are valid at each position. Our scanless Earley parser
already knows what's predicted — it just doesn't expose that information to
semirings.

`should_scan` bridges this gap. Before admitting a terminal scan, the parser
asks each semiring: "given what you know and what the chart says, should this
scan proceed?"

### API

```perl
method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted)
```

- `$item` — the Earley item (rule, dot, origin, value)
- `$alt_idx` — which alternative of the rule
- `$pos` — chart position
- `$matched_text` — the text the terminal regex matched
- `$is_predicted` — coderef callback: `$is_predicted->('RuleName')` returns
  true if `RuleName` has a predicted item at `$pos` in the chart

Returns: boolean. `true` to admit the scan, `false` to reject it.

### Callback Design

`$is_predicted` is a closure over the chart, provided by the parser:

```perl
my $is_predicted = sub($rule_name) {
    return exists $chart[$pos]->{"$rule_name:..."}  # simplified
};
```

This is lazy (no chart copying), stable (the callback interface doesn't change
if chart internals change), and decoupled (semirings never see chart data
structures directly).

### Parser Integration (Earley.pm)

In `_scan`, before the regex match or after it but before calling `on_scan`:

```perl
# Build the $is_predicted callback for this position
my $is_predicted = sub($rule_name) {
    # Check if any item in chart[$pos] has this rule predicted
    # (i.e., an item waiting for this rule as a nonterminal)
    return exists $waiting_for{$rule_name}{$pos};
};

# Ask semiring if scan should proceed
next unless $semiring->should_scan($item, $alt_idx, $pos, $matched, $is_predicted);
```

### FilterComposite Protocol

Short-circuit on first `false`:

```perl
method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
    for my $i (0 .. $semirings->$#*) {
        my $component_item = { %$item, value => $item->{value}->[$i] };
        return false unless $semirings->[$i]->should_scan(
            $component_item, $alt_idx, $pos, $matched_text, $is_predicted
        );
    }
    return true;
}
```

First semiring to return `false` kills the scan. This matches FilterComposite's
first-wins design: earlier semirings (Boolean, Precedence) have higher priority.

### Default Implementation

Semirings that don't need scan filtering return `true`:

```perl
method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
    return true;
}
```

Boolean, Precedence, Structural, and SemanticAction all use this default.
Only TypeInference implements non-trivial logic (initially).

### TypeInference should_scan: Keyword Rejection

The core use case: reject keywords scanned as QualifiedIdentifier when the
keyword's grammar rule is also predicted.

```perl
method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
    my $rule_name = $item->{rule}->name();

    # Only filter QualifiedIdentifier scans
    return true unless $rule_name eq 'QualifiedIdentifier';

    # Check if matched text is a keyword
    my $keyword_rule = $keyword_table->keyword_rule($matched_text);
    return true unless defined $keyword_rule;

    # Reject keyword-as-identifier ONLY when the keyword-consuming rule
    # is predicted at this position (unambiguous rejection).
    # When the keyword rule is NOT predicted, the keyword may be used
    # as an identifier (e.g., `class => "Foo"` where class is a hash key
    # and ClassDeclaration is not predicted in this context).
    return !$is_predicted->($keyword_rule);
}
```

This replaces the current mechanism:
- Scan-time: `keyword_as_identifier` tag set on QualifiedIdentifier
- Complete-time: Atom and CallExpression check the tag and reject

The new mechanism is simpler (one check at scan time), more correct (uses chart
context to distinguish ambiguous vs unambiguous cases), and solves the fat-arrow
problem: inside `(class => "Foo")`, ClassDeclaration is not predicted after an
open paren in ExpressionList context, so `class` is admitted as an identifier.

### What should_scan Does NOT Handle

- **Unary vs binary +/-**: Removed from TypeInference entirely. Precedence
  semiring's `add()` handles this via level comparison (BinaryExpression level
  > UnaryExpression level). See commit 369a54d.

- **Regex vs division `//`**: Already handled at scan time by TypeInference
  `on_scan` (empty regex rejection). Could potentially move to `should_scan`
  but no need — current approach works.

## Part 2: Extend-Based Value Model

### Core Insight

Each rule's `on_complete` is a partial function over the Context tree, applied
via `extend()`. No flat merge, no tag propagation, no catch-all copying.

- **Annotation**: compute the rule's type from its children's types
- **Rejection**: return undef for ill-typed parses (partial function returns nothing)
- Both are the same `extend` operation — rejection IS type inference

### TypeInferenceActions Class

A separate class with methods named after grammar rules, dispatched by
TypeInference's `on_complete` via `$actions->can($rule_name)`. This mirrors
SemanticAction's existing pattern:

```perl
class Chalk::Bootstrap::Semiring::TypeInferenceActions {
    method BinaryExpression($ctx) {
        my $op = $_get_op_text->($ctx);
        return unless defined $op;
        my $sig = get_binary_op($op);
        my $type = ($sig && $sig->{result} ne 'Any') ? $sig->{result} : undef;
        return { valid => true, ($type ? (type => $type) : ()) };
    }

    method CallExpression($ctx) {
        my $call_sym = $_get_call_symbol->($ctx);
        my $return_type = 'Unknown';
        if ($call_sym) {
            my $sig = $builtin_lookup->($call_sym);
            $return_type = $sig->{return_type} if $sig;
        }
        return { valid => true, type => $return_type };
    }

    method Atom($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
        return { valid => true, ($child_type ? (type => $child_type) : ()) };
    }

    # Wrapper rules: identity (my type = my child's type)
    method Expression($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
        return { valid => true, ($child_type ? (type => $child_type) : ()) };
    }

    # ... etc for each rule that needs type logic
}
```

### TypeInference on_complete

Mirrors SemanticAction exactly:

```perl
method on_complete($item, $alt_idx, $pos) {
    my $value = $item->{value};
    return undef if !defined $value;

    my $rule_name = $item->{rule}->name();
    my $method = $actions ? $actions->can($rule_name) : undef;
    if ($method) {
        my $result = $value->extend(sub { $actions->$method(@_) });
        return undef if !defined $result;  # partial function rejected
        return $result;
    }

    # No action registered: pass through (identity wrapper)
    return $value;
}
```

### What Gets Eliminated

- `_tags()` helper (flat merge of Context tree into hash)
- Catch-all rule (the 6-tag propagation block at the bottom of on_complete)
- Boundary rule tag clearing (replaced by actions that create clean scopes)
- `keyword_as_identifier` propagation (replaced by `should_scan`)
- `ambiguous_unary` (already removed — Precedence handles it)
- All tag copying through intermediate rules

### What Remains in TypeInference (Not in Actions)

- `on_scan`: scan-time type facts (sigils, operators, literals, `call_symbol`)
  stay in TypeInference directly — they operate on matched text, not the
  Context tree
- `should_scan`: keyword rejection (chart context query)
- `zero()`/`one()`/`is_zero()`/`multiply()`: semiring algebra (unchanged)
- `add()`: no longer needs `_tags()` — identity collapse or merged Context
- Hash-consing (`%_ctx_cache`): unchanged

### Design Principles

- Every Expression has a type — intermediate rules aren't scaffolding
- Wrapper rules: "my type = my child's type" (identity via `$_get_rightmost_type`)
- Rich rules: "my type = f(children's info)" (BinaryExpr, CallExpr, etc.)
- Rejection is type inference — ill-typed parse = partial function returns undef
- Perl is operator-oriented: return type = f(operator), not f(operand types)
- `Any` = permissive top (Perl runtime: "accepts anything")
- `Unknown` = conservative default (Chalk compiler: "not yet determined")

### Tree-Walk Helpers

These already exist and replace flat merge as the way actions access children:
- `$_get_rightmost_type` — child's type (for wrappers)
- `$_get_op_text` — operator text (for BinaryExpr/UnaryExpr)
- `$_get_call_symbol` — function name (for CallExpression)
- `$_get_prev_item_types` — per-position arg types (for CallExpression)
- `$_is_valid_identifier` — identifier validity check (moves to should_scan)

## Implementation Phases

### Phase 1: should_scan Protocol

**1a. Add should_scan to semiring API**
- Add default `should_scan` (returns true) to all 5 semirings
- Add `should_scan` to FilterComposite (first-false short-circuit)
- Add `should_scan` call site in Earley.pm `_scan` method
- Build `$is_predicted` callback closure over `%waiting_for`
- Tests: verify default behavior (all scans admitted)

**1b. TypeInference keyword rejection via should_scan**
- Implement `should_scan` in TypeInference using `$keyword_table`
- Test: keyword rejected when keyword-consuming rule is predicted
- Test: keyword admitted when keyword-consuming rule is NOT predicted
- Test: fat-arrow case (`class => "Foo"`) — keyword admitted

**1c. Remove keyword_as_identifier mechanism**
- Remove `keyword_as_identifier` tagging from on_scan
- Remove `keyword_as_identifier` checks from Atom/CallExpression on_complete
- Remove `keyword_as_identifier` propagation from catch-all
- Remove `keyword_as_identifier` clearing from boundary rules
- Verify all existing tests pass (keyword rejection now at scan time)

### Phase 2: TypeInferenceActions Class

**2a. Create TypeInferenceActions class**
- New file: `lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm`
- Implement actions for rules that currently have explicit on_complete logic:
  BinaryExpression, UnaryExpression, CallExpression, Atom, Expression,
  ExpressionList, PostfixExpression, etc.
- Each action is a method that receives a Context and returns a focus hash
  (or undef for rejection)

**2b. Wire TypeInference on_complete to actions**
- TypeInference on_complete dispatches via `$actions->can($rule_name)`
- Uses `$value->extend(sub { $actions->$method(@_) })` pattern
- Boundary rules become actions that create clean scope contexts
- Remove catch-all propagation block
- Remove `_tags()` helper

**2c. Remove flat merge infrastructure**
- Remove `_tags()` function
- Remove all tag propagation from catch-all
- Remove boundary rule tag clearing
- Verify all integration tests pass

### Phase 3: Cleanup and Validation

- Run full 1,824-test regression suite
- Verify concise-per-file fat-arrow test (currently failing) now passes
- Update test file comments
- Update MEMORY.md

## Risks

- **Low**: `should_scan` adds one method call per scan attempt. Mitigated by
  the check being a simple hash lookup (`%waiting_for`).
- **Medium**: Fat-arrow keyword case depends on ClassDeclaration NOT being
  predicted in ExpressionList context. Need to verify this holds for all
  keyword/context combinations.
- **Low**: TypeInferenceActions dispatch adds one `can()` call per on_complete.
  Same cost as SemanticAction (already proven acceptable).
- **Medium**: The extend model changes how type information flows. Integration
  tests are the safety net — 389 concise-actions + 208 concise-validation
  tests exercise real Perl parsing.

## Resolved Questions (from brainstorming)

- **ambiguous_unary → Precedence?** Resolved: removed entirely. Precedence
  add() handles it via level comparison. Commit 369a54d.
- **selects_alternative → filter-based?** Resolved: selects_alternative fully
  removed in FilterComposite architecture. All disambiguation is via
  `_filter_compare` first-wins.
- **Boundary rules special handling?** They become TypeInferenceActions methods
  that return clean-scope focus hashes (preserving type, clearing everything
  else).
- **Dispatch model?** TypeInferenceActions class (mirrors SemanticAction).
  Chosen over Rule classes (too much ceremony for bootstrap) and dispatch
  tables (less extensible).

## Future Work

- Post-parse type inference via SemanticAction walking the annotated tree
- BinaryExpr operand type validation (e.g. reject `*STDIN x *STDOUT`)
- `Unknown` type in TypeLibrary (distinct from `Any`)
- Precedence `should_scan` for future scan-time precedence decisions
