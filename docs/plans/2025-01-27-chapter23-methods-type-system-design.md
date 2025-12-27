# Chapter 23: Methods and Type System Design

## Overview

This document describes the implementation of Chapter 23 from the Sea of Nodes book, adapted for Chalk's XS code generation target. The goal is to compile `class` declarations with methods to XS modules using Perl's native `ObjectFIELDS` for O(1) field access.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Object model | Native ObjectFIELDS | Matches perlclassguts, O(1) field access |
| Class structure | New ClassDef IR node | Explicit structure for XS generation |
| Methods | Reuse FunctionDef with $self | Minimal IR changes, $self as parameter 0 |
| Fields | New Field IR node | Consistent with Sea of Nodes architecture |

## New IR Nodes

### Chalk::IR::Node::Field

Represents a field definition within a class.

```perl
class Chalk::IR::Node::Field :isa(Chalk::IR::Node::Base) {
    field $name :param :reader;           # '$grammar' (with sigil)
    field $index :param :reader;          # Position in ObjectFIELDS array
    field $field_type :param :reader = undef;  # Type constraint
    field $default :param :reader = undef;     # Default value IR node
    field $attributes :param :reader = [];     # [:param, :reader, etc.]

    method op() { 'Field' }

    method is_param() { grep { $_ eq ':param' } $attributes->@* }
    method is_reader() { grep { $_ eq ':reader' } $attributes->@* }
}
```

### Chalk::IR::Node::ClassDef

Organizes class structure for XS generation.

```perl
class Chalk::IR::Node::ClassDef :isa(Chalk::IR::Node::Base) {
    field $class_name :param :reader;          # "Chalk::Parser"
    field $fields :param :reader = [];         # [Field nodes]
    field $methods :param :reader = [];        # [FunctionDef nodes]
    field $parent_class :param :reader = undef; # For :isa() inheritance

    method op() { 'ClassDef' }

    method field_index($name) {
        for my $f ($fields->@*) {
            return $f->index if $f->name eq $name;
        }
        return undef;
    }
}
```

## Updated IR Nodes

### FunctionDef

Add optional `class_name` field to indicate method context:

```perl
field $class_name :param :reader = undef;  # Set for methods, undef for subs
```

### FieldLoad / FieldStore

Add `field_index` for XS generation while keeping `field_name` for interpreter:

```perl
field $object :param :reader;      # IR node for object (typically $self Parm)
field $field_index :param :reader; # Integer index for ObjectFIELDS
field $field_name :param :reader;  # Name for debugging/interpreter
```

### Stop

Add `class_defs` collection:

```perl
field $class_defs :param :reader = [];  # [ClassDef nodes]
```

## Grammar Rule Changes

### ClassDeclaration

Currently registers types but returns `undef`. Change to produce ClassDef:

```perl
method evaluate($context) {
    # ... existing field/method extraction ...

    # Create Field IR nodes with indices
    my @field_nodes;
    for my $i (0 .. $#field_info) {
        push @field_nodes, Chalk::IR::Node::Field->new(
            name       => $field_info[$i]{name},
            index      => $i,
            field_type => $field_info[$i]{type},
            default    => $field_info[$i]{default_node},
            attributes => $field_info[$i]{attributes},
        );
    }

    # Collect MethodDeclaration results from block
    my @method_nodes = grep {
        blessed($_) && $_->can('op') && $_->op eq 'FunctionDef'
    } @block_statements;

    # Create ClassDef
    return Chalk::IR::Node::ClassDef->new(
        class_name   => $class_name,
        fields       => \@field_nodes,
        methods      => \@method_nodes,
        parent_class => $parent_class,
    );
}
```

### MethodDeclaration (new semantic action)

Similar to SubroutineDeclaration but prepends `$self`:

```perl
method evaluate($context) {
    # Extract method name and parameters
    # ...

    my @parameters = ('$self', @extracted_params);

    return Chalk::IR::Node::FunctionDef->new(
        name       => $method_name,
        parameters => \@parameters,
        body_node  => $body,
        class_name => $context->env->{current_class},
    );
}
```

## XS Code Generation

### Output Files

Each class generates two files:

**`lib/Chalk/Parser.xs`:**
```c
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = Chalk::Parser  PACKAGE = Chalk::Parser

SV*
new(class, ...)
    SV* class
CODE:
    SV* obj = newSV_type(SVt_PVOBJ);
    ObjectMAXFIELD(obj) = 2;
    Newxz(ObjectFIELDS(obj), 3, SV*);
    // Initialize from named args
    RETVAL = obj;
OUTPUT:
    RETVAL

SV*
parse(self, input)
    SV* self
    SV* input
CODE:
    SV* tmp_0 = ObjectFIELDS(self)[0];  // $grammar field
    // ... method body ...
    RETVAL = tmp_1;
OUTPUT:
    RETVAL
```

**`lib/Chalk/Parser.pmc`:**
```perl
package Chalk::Parser;
use v5.40;
use XSLoader;
our $VERSION = '0.01';
XSLoader::load(__PACKAGE__, $VERSION);
1;
```

### New XS Target Visitors

| Visitor | Purpose |
|---------|---------|
| `visit_ClassDef` | Generate MODULE/PACKAGE, iterate fields and methods |
| `visit_Field` | Compute layout, generate accessor XSUBs for :reader |
| `visit_FieldLoad` | Emit `ObjectFIELDS(obj)[index]` |
| `visit_FieldStore` | Emit `ObjectFIELDS(obj)[index] = value` |

### Constructor Generation

The `new()` XSUB:

1. Allocates `SVt_PVOBJ` with `newSV_type()`
2. Sets `ObjectMAXFIELD()` to field count - 1
3. Allocates field array with `Newxz()`
4. Parses named arguments from `@_`
5. Initializes `:param` fields from args or defaults
6. Returns the object

## Implementation Order

| Step | Component | Files |
|------|-----------|-------|
| 1 | Field IR node | `lib/Chalk/IR/Node/Field.pm` |
| 2 | ClassDef IR node | `lib/Chalk/IR/Node/ClassDef.pm` |
| 3 | Update FunctionDef | `lib/Chalk/IR/Node/FunctionDef.pm` |
| 4 | MethodDeclaration rule | `lib/Chalk/Grammar/Chalk/Rule/MethodDeclaration.pm` |
| 5 | Update ClassDeclaration | `lib/Chalk/Grammar/Chalk/Rule/ClassDeclaration.pm` |
| 6 | Update Stop node | `lib/Chalk/IR/Node/Stop.pm` |
| 7 | Update FieldLoad/FieldStore | `lib/Chalk/IR/Node/FieldLoad.pm`, `FieldStore.pm` |
| 8 | XS visit_ClassDef | `lib/Chalk/Target/XS.pm` |
| 9 | XS visit_Field | `lib/Chalk/Target/XS.pm` |
| 10 | XS constructor | `lib/Chalk/Target/XS.pm` |
| 11 | XS visit_FieldLoad/Store | `lib/Chalk/Target/XS.pm` |
| 12 | Multi-file output | `lib/Chalk/Target/XS.pm` |

## Test Strategy

### Unit Tests

- `t/ir/field-node.t` - Field IR node creation and attributes
- `t/ir/classdef-node.t` - ClassDef IR node with fields and methods

### Integration Tests

- `t/target/xs-class.t` - XS generation for simple class
- `t/target/xs-method.t` - Method body compilation
- `t/target/xs-field-access.t` - FieldLoad/FieldStore to ObjectFIELDS

### End-to-End Tests

- `t/target/xs-class-e2e.t` - Full pipeline: class source -> XS -> compile -> run

## Success Criteria

From issue #292:

- [ ] Method dispatch generates correct IR
- [ ] Object method calls work (`$obj->method()`)
- [ ] Field access uses ObjectFIELDS indexing
- [ ] Type system correctly tracks object types
- [ ] Each class generates .xs + .pmc files
- [ ] Generated XS compiles and loads correctly
- [ ] `$self` implicit parameter works correctly
- [ ] Tests pass for OO method invocation

## References

- [Sea of Nodes Chapter 23](https://github.com/SeaOfNodes/Simple)
- [perlclassguts](https://perldoc.pl/perlclassguts) - Native class internals
- [perlapi](https://perldoc.pl/perlapi) - ObjectFIELDS macros
