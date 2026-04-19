# TypeInference Extend-Based Redesign

## Problem

TypeInference uses `_tags()` (flat merge) to read child information in `on_complete`.
This destroys the Context tree structure, making type reasoning work against the
comonad instead of with it. The catch-all rule copies all tags upward solely to
compensate for this flat merge.

## Core Insight

Each rule's `on_complete` is a partial function over the Context tree, applied via
`extend`. No flat merge, no tag propagation, no catch-all copying.

- **Annotation**: compute the rule's type from its children's types
- **Rejection**: return undef for ill-typed parses (partial function)
- Both are the same `extend` operation — rejection IS type inference

## Design Principles

- Every Expression has a type — intermediate rules aren't scaffolding
- Wrapper rules (Expression, Atom, PostfixExpression): "my type = my child's type"
- Rich rules (BinaryExpression, CallExpression): "my type = f(children's info)"
- All cases are `extend` with a rule-specific annotation function

## Perl Type Semantics

- Perl is operator-oriented: BinaryExpr return type = f(operator), not f(operand types)
- Operand types matter for validation (future), not return type computation
- CallExpression: return type known for builtins, `Unknown` for user calls
- `Any` = permissive top (Perl runtime: "accepts anything")
- `Unknown` = conservative default (Chalk compiler: "not yet determined, must narrow")

## Scan-Time vs Complete-Time

Parse-time TypeInference is lightweight annotation + disambiguation:
1. **Scan-time**: tag tokens with type facts (sigils, operators, keywords, literals)
2. **Complete-time** via `extend`:
   - Reject ill-formed parses (invalid identifiers, ambiguous unary)
   - Validate builtin argument compatibility
   - Propagate types through wrappers
   - Annotate return types where known

SemanticAction (5th semiring) is the consumer — traverses the Context tree to build
IR using type annotations. TypeInference and SemanticAction collaborate through the
Context comonad.

## Concrete Examples

### BinaryExpression: `$x + $y`

```perl
my $annotate_binop = sub($ctx) {
    my $op = $_get_op_text->($ctx);
    return unless defined $op;
    my $sig = get_binary_op($op);
    my $type = ($sig && $sig->{result} ne 'Any') ? $sig->{result} : undef;
    return { valid => true, ($type ? (type => $type) : ()) };
};
return $value->extend($annotate_binop);
```

### CallExpression: `push @arr, $x`

```perl
my $annotate_call = sub($ctx) {
    my $valid = $_is_valid_identifier->($ctx);
    return unless $valid;
    my $call_sym = $_get_call_symbol->($ctx);
    my $return_type = 'Unknown';
    if ($call_sym) {
        my $sig = $builtin_lookup->($call_sym);
        if ($sig) {
            my $item_types = $_get_item_types->($ctx);
            # ... validation ...
            $return_type = $sig->{return_type};
        }
    }
    return { valid => true, type => $return_type };
};
return $value->extend($annotate_call);
```

### Atom (wrapper)

```perl
my $annotate_atom = sub($ctx) {
    my $valid = $_is_valid_identifier->($ctx);
    return unless $valid;
    my $child_type = $_get_rightmost_type->($ctx);
    return { valid => true, ($child_type ? (type => $child_type) : ()) };
};
return $value->extend($annotate_atom);
```

## Naming Changes

- `keyword_as_identifier` → `is_valid_identifier` (positive assertion, expandable)
  - Covers: keywords as bare identifiers, sigil-prefixed in non-variable context,
    reserved words

## What Gets Eliminated

- `_tags()` helper (flat merge)
- Catch-all rule (tag propagation)
- `call_symbol` propagation from ExpressionList/BinaryExpr/UnaryExpr
- All tag copying in boundary rules (they become transparent or scope boundaries)

## Tree-Walk Helpers (Reusable Vocabulary)

These replace the flat merge as the way rules access child information:
- `$_get_rightmost_type` — child's type (for wrappers)
- `$_get_op_text` — operator text (for BinaryExpr/UnaryExpr)
- `$_get_call_symbol` — function name (for CallExpression)
- `$_get_item_types` — per-position arg types (for CallExpression)
- `$_is_valid_identifier` — identifier validity check (for Atom/CallExpression)
- `$_has_ambiguous_unary` — disambiguation signal (for add/selects_alternative)

## Open Questions

- Should `ambiguous_unary` move to Precedence semiring?
- Should `selects_alternative` be replaced by filter-based rejection?
  (See separate architecture discussion on `selects_alternative`)
- Boundary rules: do they need special handling, or are they just wrappers
  that happen to create scope?

## Future Work

- Post-parse type inference via SemanticAction walking the annotated tree
- BinaryExpr operand type validation (e.g. reject `*STDIN x *STDOUT`)
- `Unknown` type in TypeLibrary (distinct from `Any`)
