# M19 Multi-Assign Design Decision

**Issue**: 019e9af9-8a1a  
**Date**: 2026-06-06  
**Status**: IMPLEMENTED — M19 is PASS in the gap map (75/78 PASS, was 74)

## Idiom

```perl
class C { method m() { my ($a, $b) = (1, 2); return $a + $b; } }
```

Expected return value: 3 ($a=1, $b=2, $a+$b=3).

## Investigation

### VarDecl (lib/Chalk/IR/Node/VarDecl.pm)

`VarDecl` carries:
- `inputs->[0]` = name Constant (string value like `'$a'`)
- `inputs->[1]` = init node (optional)
- `control_in` = effect-chain predecessor
- `scope` = `'my'` etc.

The `name()` accessor returns a single Constant node. Six call sites in the
emitter call `$node->name()->value()` expecting a scalar string. The
`_scope_body_vars_mop` and `_scope_body_vars` methods iterate VarDecl nodes
and call `$n->name` expecting a single Constant.

**Conclusion**: VarDecl cannot cleanly carry a list LHS without breaking every
caller that expects `name()` to return a single Constant node.

### ExpressionList (lib/Chalk/IR/Node/ExpressionList.pm)

`ExpressionList` carries `inputs->[0]` = arrayref of items. It is designed for
parameter lists and list-context expressions. It could serve as the RHS of a
list assignment, and it is already in NodeFactory's DATA_CLASSES.

**Conclusion**: ExpressionList is the correct RHS for `my ($a,$b) = (1, 2)`.

### Assign (lib/Chalk/IR/Node/Assign.pm)

`Assign` is a `BinOp` subclass: `inputs = [op_constant, lhs, rhs]`. It emits
as `lhs = rhs` via `_emit_binary_expr`. It has no mechanism for parenthesized
list LHS or list-context assignment semantics.

**Conclusion**: Assign cannot represent `my ($a,$b) = (1, 2)` without emitter
special-casing that would be fragile.

### Parser Actions (lib/Chalk/Bootstrap/Perl/Actions.pm)

The `VariableDeclaration` action only handles a single variable: it scans for
the first sigil-starting Constant leaf. There is no current parser path for
`my ($a, $b)` — this is a spike to determine the correct IR shape for when
that parser path is added.

## Decision: New `Chalk::IR::Node::ListAssign` node

**Chosen representation**:

```perl
ListAssign {
    scope  => 'my'                    # declarator keyword
    inputs => [
        [$name_a, $name_b, ...],      # inputs->[0]: arrayref of name Constants
        $rhs_node,                    # inputs->[1]: init (ExpressionList or other)
    ]
    control_in => $predecessor        # effect-chain predecessor (like VarDecl)
}
```

**Rationale**:

1. **Non-destructive to VarDecl**: VarDecl has 6+ call sites expecting `name()->value()` to
   return a string. A new node avoids modifying that interface.

2. **Content-hash is per-position identity**: Like VarDecl, a list declaration
   is a side-effect with positional identity. Two `my ($a,$b)=(1,2)` in different
   control positions are distinct nodes. NodeFactory allocates fresh IDs
   (`ListAssign#N`), never hash-consing by content.

3. **Clean emitter path**: `_emit_list_assign` emits `my ($a, $b) = (rhs);`.
   The RHS is handled by `_emit_list_rhs` which flattens ExpressionList nodes
   into `(item1, item2, ...)` — parenthesized list context, not arrayref.

4. **Correct semantics**: `my ($a,$b) = (1,2)` in Perl assigns $a=1, $b=2.
   The naive wrong representation — `my $a = [1,2]` + `my $b` — assigns $a to
   the arrayref (a memory address) and $b to undef.

5. **Parser-ready shape**: When the parser eventually handles `my ($a,$b)=...`,
   the `VariableDeclaration` action can emit a `ListAssign` node with the
   scanned name list and the init from `AssignmentExpression`.

## Emitter Changes

### Target/Perl.pm

- **Statement position**: `if ($node isa Chalk::IR::Node::ListAssign)` dispatches to
  `_emit_list_assign($node)` which returns `my ($a, $b) = (1, 2);` (with semicolon).

- **Expression position**: `_emit_list_assign_expr($node)` returns the same without
  semicolon (for for-init or other expression contexts).

- **RHS helper** `_emit_list_rhs($init)`: if init is an `ExpressionList`, flattens
  to `(item1, item2, ...)`. Otherwise wraps the single expr in parens.

- **Aggregate var scanning**: `_scope_body_vars` and `_scope_body_vars_mop` updated
  to scan ListAssign nodes for `@` and `%` sigil names (same logic as VarDecl).

## The Miscompile Guard

The naive wrong graph — `my $a = [1,2]; my $b;` — emits `my $a = [1, 2]; my $b;`
(the `_emit_init_expr` for a scalar var with an ArrayRef init does NOT strip the
brackets). Running this under perl:

- `$a` = arrayref (SCALAR(`[...]`), a numeric address like `94350144574448`)
- `$b` = undef
- `$a + $b` = that numeric address (not 3)

The rig test confirms this: the naive graph returns a non-3 value. The correct
ListAssign graph emits `my ($a, $b) = (1, 2);` and returns 3.

## Files Changed

- `lib/Chalk/IR/Node/ListAssign.pm` — new node class
- `lib/Chalk/IR/NodeFactory.pm` — registers ListAssign; per-position identity handler
- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` — emitter + scope-scan updates
- `lib/Chalk/CodeGen/Harness/HandGraphs.pm` — `_build_M19` builder + dispatch entry
- `lib/Chalk/CodeGen/Harness/Harness.pm` — M19 added to `%CORPUS`
- `t/bootstrap/codegen-harness/m19-multi-assign.t` — TDD test (RED->GREEN)
- `t/fixtures/codegen-harness/gap-map.json` — regenerated (M19: NOT-YET-COVERED -> PASS)

## Gap Map Tally

Before: PASS=74, NOT-YET-COVERED=3, REJECT=1 (total 78)  
After:  PASS=75, NOT-YET-COVERED=2, REJECT=1 (total 78)

M19: `{"tag":"M19","group":"M","verdict":"PASS","extra":{"graph_source":"hand","verdict":"PASS"}}`
