# Chapter 19: XS Target Design

## Overview

Implement instruction selection for the XS backend, mapping Sea of Nodes IR to Perl C API calls. This unblocks the Stage 0 milestone (self-hosting compilation to XS).

**Issue:** #291

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Backend scope | XS-only first | Simpler, refactor for LLVM/WASM later |
| Pipeline position | After all optimizations | XS doesn't benefit from machine-aware GCM |
| Output format | XS AST nodes + templates | Structured but simple serialization |
| Node scope | Incremental by test (TDD) | Add visitors as tests require |
| Architecture | Visitor pattern | Centralized XS logic, clean separation |
| Naming | `Chalk::Target::XS` | Standard compiler terminology |
| Context | Compose with IR::Context | Consistency with existing patterns |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Optimized IR Graph (Sea of Nodes)                      │
│  - Chalk::IR::Node::* (86 types)                        │
│  - Already optimized by peephole/GVN/GCM/DCE            │
└─────────────────────┬───────────────────────────────────┘
                      │ Chalk::Target::XS->generate()
                      ▼
┌─────────────────────────────────────────────────────────┐
│  XS Target (Visitor)                                    │
│  - Chalk::Target::XS                                    │
│  - visit_* methods for each IR node type                │
│  - Tracks node→variable mappings via IR::Context        │
└─────────────────────┬───────────────────────────────────┘
                      │ produces
                      ▼
┌─────────────────────────────────────────────────────────┐
│  XS AST Nodes                                           │
│  - Chalk::Target::XS::AST::*                            │
│  - Module, XSUB, Block, VarDecl, Assignment, etc.       │
└─────────────────────┬───────────────────────────────────┘
                      │ $ast->emit()
                      ▼
┌─────────────────────────────────────────────────────────┐
│  XS Source Output                                       │
│  - Template-based string emission                       │
│  - Valid .xs file ready for xsubpp/compilation          │
└─────────────────────────────────────────────────────────┘
```

## Namespace Structure

```
Chalk::Target::XS              # Main visitor class
Chalk::Target::XS::AST::Node   # Base AST class
Chalk::Target::XS::AST::Module # MODULE = X  PACKAGE = X
Chalk::Target::XS::AST::XSUB   # SV* method_name(...)
Chalk::Target::XS::AST::Block  # { ... }
Chalk::Target::XS::AST::VarDecl    # NV x;
Chalk::Target::XS::AST::Assignment # x = expr;
Chalk::Target::XS::AST::Return     # RETVAL = x;
Chalk::Target::XS::AST::BinaryOp   # left + right
Chalk::Target::XS::AST::Call       # Perl_newSVnv(aTHX_ value)
Chalk::Target::XS::AST::FieldAccess # self->x
```

## Main Class Structure

```perl
class Chalk::Target::XS {
    field $graph :param;
    field $module_name :param;
    field $ctx = Chalk::IR::Context->empty_context();
    field $temp_counter = 0;

    method generate() {
        # 1. Build emission order (reverse postorder from Return nodes)
        my @order = $self->schedule_emission();

        # 2. Visit each node, building XS AST
        my @statements;
        for my $node (@order) {
            my $xs_node = $self->visit($node);
            push @statements, $xs_node if $xs_node;
        }

        # 3. Wrap in module structure
        return Chalk::Target::XS::AST::Module->new(
            name => $module_name,
            body => \@statements,
        );
    }

    method visit($node) {
        my $type = ref($node) =~ s/.*:://r;
        my $method = "visit_$type";
        return $self->$method($node);
    }

    # Context management via IR::Context
    method bind_var($node_id, $var_name) {
        my $label = Chalk::IR::Context->make_label('xs_var', $node_id);
        $ctx = Chalk::IR::Context->extend_context($ctx, $label, $var_name);
    }

    method get_var($node_id) {
        my $label = Chalk::IR::Context->make_label('xs_var', $node_id);
        return $ctx->($label) // $self->alloc_temp($node_id);
    }

    method alloc_temp($node_id) {
        my $var = "tmp_" . $temp_counter++;
        $self->bind_var($node_id, $var);
        return $var;
    }

    method get_c_type($node) {
        # Map IR types to C types for Perl API
        my $ir_type = $node->type;
        return match ($ir_type) {
            'Int'    => 'IV',
            'Float'  => 'NV',
            'Str'    => 'SV*',
            'Array'  => 'AV*',
            'Hash'   => 'HV*',
            default  => 'SV*',  # Conservative fallback
        };
    }

    # Visitors added incrementally via TDD:
    method visit_Constant($node) { ... }
    method visit_Add($node) { ... }
    method visit_Return($node) { ... }
    # ... more as tests require
}
```

## Pipeline Integration

```perl
# In app.pl (or future chalk CLI)
sub compile_to_xs($source, $module_name) {
    # 1. Parse to IR (existing)
    my $graph = parse_and_build_ir($source);

    # 2. Optimize (existing passes)
    $graph = Chalk::IR::Optimizer::IterPeeps->optimize($graph);
    $graph = Chalk::IR::Optimizer::GCM->optimize($graph);
    $graph = Chalk::IR::Optimizer::DCE->optimize($graph);

    # 3. Generate XS (new)
    my $xs_target = Chalk::Target::XS->new(
        graph => $graph,
        module_name => $module_name,
    );
    my $xs_ast = $xs_target->generate();

    # 4. Emit source
    return $xs_ast->emit();
}
```

## Type Mapping

| IR Type | C Type | Notes |
|---------|--------|-------|
| Int | IV | Perl integer value |
| Float | NV | Perl numeric value |
| Str | SV* | Perl scalar (string) |
| Array | AV* | Perl array |
| Hash | HV* | Perl hash |
| Object | SV* | Blessed reference |
| Unknown | SV* | Conservative fallback |

Type inference from #293 feeds directly into this mapping.

## TDD Test Progression

### Test 1: Constant Return (output validation)
```perl
# t/target/xs-constant-return.t
# Input: sub foo { return 42; }
# Verify: output contains MODULE, RETVAL = 42
```

### Test 2: Compilation Verification
```perl
# t/target/xs-compiles.t
# Generate XS, write to temp dir, run Makefile.PL && make
# Verify: compilation succeeds (exit code 0)
# TODO: Research correct XS dynamic loading syntax (DynaLoader/XSLoader)
```

### Test 3: Execution Verification
```perl
# t/target/xs-executes.t
# Compile, load, call function
# Verify: returns correct value
```

### Incremental Node Coverage
Add visitors as tests require:
1. `visit_Constant`, `visit_Return` (Test 1)
2. `visit_Add`, `visit_Subtract`, etc. (arithmetic)
3. `visit_FieldLoad`, `visit_FieldStore` (objects)
4. `visit_If`, `visit_Region`, `visit_Phi` (control flow)

## Open Questions

1. **XS dynamic loading** - Exact syntax for loading compiled XS at runtime in tests (DynaLoader vs XSLoader vs require)

## Dependencies

- Requires optimized IR graph (existing)
- Uses type inference from #293 (complete)
- Blocks #294, #303-306 (XS backend sub-issues)

## Related Issues

- #291 - This issue (Chapter 19: Instruction Selection)
- #292 - Chapter 23: Methods and type system
- #293 - Type Inference Engine (closed, complete)
- #294 - XS Backend for Chapter 19
- #464 - Refactor IR::Context to OO (deferred cleanup)

## Notes

- Chapters 20-22 (register allocation, instruction encoding, ELF) are **not needed** for XS - the C compiler handles those
- This design is XS-specific; LLVM/WASM backends will need different Target implementations
- The visitor pattern centralizes all XS logic in one place for easy coverage tracking
