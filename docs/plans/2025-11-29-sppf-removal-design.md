# SPPF Removal from ChalkIR Pipeline

**Date:** 2025-11-29
**Status:** Draft
**Supersedes:** Partially supersedes 2025-11-25-semantic-ir-rewrite-design.md (ID strategy changed)

## Problem Statement

Analysis revealed that SPPF is included in the ChalkIR composite but never actually used:

1. **SPPF merges alternatives** via `$forest->add_alternative()` in its `add()` method
2. **Disambiguation semirings filter alternatives** by returning `add_id` for rejected parses
3. **These work at cross-purposes** - SPPF keeps dead alternatives that Precedence already rejected
4. **Rule classes never query the forest** - zero calls to `$ctx->forest` or `$ctx->alternatives()`

The Semantic semiring already works like the AST semiring: it builds IR during parsing via `rule->evaluate($ctx)` in `on_complete()`, and the winning parse's `focus` contains the complete IR graph as linked nodes.

## Key Discovery

The AST semiring (used in `t/semiring/ast.t`) works without SPPF:

```perl
my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
my $ast = Chalk::Semiring::AST->new();
my $composite = Chalk::Semiring::Composite->new(
    semirings => [$chalksyntax, $ast]
);
# No SPPF! Disambiguation via ChalkSyntax, building via AST
```

Semantic can work the same way.

## Evidence

### SPPF is Dead Code in ChalkIR

From `lib/Chalk/Semiring/ChalkIR.pm`:
```perl
$composite = Chalk::Semiring::Composite->new(
    semirings => [$sppf_sr, $precedence_sr, $semantic_sr]
);
```

Grep for forest usage in Rule classes: **zero matches**.

### EvalContext Forest is Vestigial

From `lib/Chalk/Semiring/Semantic.pm`, forest is propagated through every EvalContext constructor (lines 106, 147-150, 163, 177, 206, 329, 349, 377) but **never read by any Rule class**.

### Content-Addressable IDs Cause Sharing

Current pattern in `lib/Chalk/IR/Node/Add.pm`:
```perl
field $id :reader = "add_" . $left->id . "_" . $right->id;
```

This causes nodes to be shared across parse alternatives when they have the same structure, which breaks isolation between winning and losing parses.

## Design

### Change 1: Remove SPPF from ChalkIR Composite

**File:** `lib/Chalk/Semiring/ChalkIR.pm`

```perl
# From:
semirings => [$sppf_sr, $precedence_sr, $semantic_sr]

# To:
semirings => [$precedence_sr, $semantic_sr]
```

### Change 2: Stop Propagating Forest in Semantic.pm

**File:** `lib/Chalk/Semiring/Semantic.pm`

Remove `forest => ...` from all EvalContext constructor calls. The field remains in EvalContext (optional, defaults to undef) but Semantic stops passing it.

Affected lines: 106, 147-150, 163, 177, 206, 329, 349, 377

### Change 3: Use refaddr for IR Node IDs

**Files:** All `lib/Chalk/IR/Node/*.pm` files

Change from content-addressable strings to object address:

```perl
# From:
field $id :reader = "add_" . $left->id . "_" . $right->id;

# To:
field $id :reader;
ADJUST { $id = refaddr($self); }
```

This ensures each node instance has a unique ID, preventing sharing between parse alternatives.

## What Stays Unchanged

- **EvalContext** - forest field stays (optional), alternatives() methods stay (vestigial but harmless)
- **Precedence semiring** - essential for operator precedence disambiguation
- **IR::Graph** - stays for optimization passes and serialization (not needed for IR generation)
- **Rule class evaluate() pattern** - continues to build IR via semantic actions

## Risk Assessment

| Change | Risk | Mitigation |
|--------|------|------------|
| Remove SPPF from ChalkIR | Low | Rule classes don't use forest |
| Stop forest propagation | Low | Never accessed by Rules |
| Change ID to refaddr | Medium | Update tests that pattern-match on ID strings |

## Tests to Watch

- `t/semiring/chalk-ir.t` - Core IR generation tests
- `t/sea-of-nodes/chapter02.t` - Arithmetic IR tests (checks ID format at lines 248-254)
- `t/sea-of-nodes/ir-generation-basic.t` - Basic IR structure tests
- `t/parser/sppf-*.t` - SPPF-specific tests (may need updates or removal)

## Implementation Order

1. Change IR Node IDs to refaddr (isolated change, can verify with existing tests)
2. Stop forest propagation in Semantic.pm (removes dead code paths)
3. Remove SPPF from ChalkIR composite (final cleanup)

Each step should be independently testable.
