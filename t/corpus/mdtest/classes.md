# Classes

`feature class` MOP idioms: class declaration, fields, methods, ADJUST blocks,
and inheritance via `:isa`.

All idioms in this topic are `L: GREEN` — `feature class` is statically/lexically
declared, so an object is a static `{class*, fields}` struct, a field read is a
known offset load, and method dispatch is a known per-class vtable slot + indirect
call (no runtime `@ISA` mutation in the subset). These are all runtime-free (RF).

## class-simple

A minimal `class C {}` with no fields or methods. Instantiating it produces an
object whose `ref()` is the class name. Because the class is statically declared,
the object is a static `{class*, fields}` struct — runtime-free.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Empty { }
my $e = Empty->new;
ref($e)
```

```behavior
return: Str:Empty
context: scalar
```

```ir
%cls    = ClassInfo(name: "Empty")
%new_e  = New(%cls) :Object
%result = Ref(%new_e) :Str
return %result
L: GREEN
```

## field-basic

A field declared with `:param` requires the constructor to accept a named
argument. A method that returns the field value reads from the object struct at a
known offset — a typed struct field, not a Scalar SV* slot. The read is
runtime-free.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Animal {
    field $name :param;
    method name { return $name }
}
my $a = Animal->new(name => 'cat');
$a->name
```

```behavior
return: Str:cat
context: scalar
```

```ir
%fa     = FieldAccess(field_index: 0, field_stash: "Animal") :Str
%mi     = MethodInfo(name: "name", body_node: %fa, return_repr: "Str")
%mf     = MOP::Field(name: "name", fieldix: 0, param: true, reader: false, has_default: false, type: "Str")
%cls    = ClassInfo(name: "Animal", methods: [%mi], fields: [%mf])
%nval   = Constant("cat") :Str
%new_a  = New(%cls, %nval, param_names: "name") :Object
%result = MethodCall(%new_a, %cls, method_name: "name") :Str
return %result
L: GREEN
```

## field-attrs

Fields may combine `:param` (constructor binding) and `:reader` (auto-generated
accessor method). The `:reader` attribute tells the MOP to synthesize a method
that returns the field value — a known vtable slot returning a known struct
offset load, statically resolved. Runtime-free.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Pair {
    field $left  :param :reader;
    field $right :param :reader;
}
my $p = Pair->new(left => 10, right => 20);
$p->left + $p->right
```

```behavior
return: Int:30
context: scalar
```

```ir
%mf_l   = MOP::Field(name: "left",  fieldix: 0, param: true, reader: true, has_default: false, type: "Int")
%mf_r   = MOP::Field(name: "right", fieldix: 1, param: true, reader: true, has_default: false, type: "Int")
%cls    = ClassInfo(name: "Pair", fields: [%mf_l, %mf_r])
%lval   = Constant(10) :Int
%rval   = Constant(20) :Int
%new_p  = New(%cls, %lval, %rval, param_names: "left,right") :Object
%lr     = MethodCall(%new_p, %cls, method_name: "left")  :Int
%rr     = MethodCall(%new_p, %cls, method_name: "right") :Int
%result = Add(%lr, %rr) :Int
return %result
L: GREEN
```

## method-simple

A method that ignores `$self` and returns a literal value is the simplest
non-trivial method. The dispatch path is a known per-class vtable slot + indirect
call (static, no runtime `@ISA` mutation), so it is runtime-free.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Greeter {
    method greet { return 42 }
}
my $g = Greeter->new;
$g->greet
```

```behavior
return: Int:42
context: scalar
```

```ir
%body   = Constant(42) :Int
%mi     = MethodInfo(name: "greet", body_node: %body, return_repr: "Int")
%cls    = ClassInfo(name: "Greeter", methods: [%mi])
%new_g  = New(%cls) :Object
%result = MethodCall(%new_g, %cls, method_name: "greet") :Int
return %result
L: GREEN
```

## method-call

A method that mutates a field (`$n += 1`) followed by a method that reads the
same field exercises the full object-mutation + read sequence. The field write is
a store to a known struct offset and the read is a load from the same offset —
typed struct fields, not Scalar SV* slots. Both are runtime-free.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method inc { $n += 1 }
    method val { return $n }
}
my $c = Counter->new(n => 10);
$c->inc;
$c->val
```

```behavior
return: Int:11
context: scalar
```

```ir
%fa_n_lv   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%fa_n_rd   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%one       = Constant(1) :Int
%n_plus1   = Add(%fa_n_rd, %one) :Int
%fw_n      = Assign(%fa_n_lv, %n_plus1) :Int
%mi_inc    = MethodInfo(name: "inc", body_node: %fw_n, return_repr: "Int")
%fa_n2     = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%mi_val    = MethodInfo(name: "val", body_node: %fa_n2, return_repr: "Int")
%mf_n      = MOP::Field(name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%cls       = ClassInfo(name: "Counter", methods: [%mi_inc, %mi_val], fields: [%mf_n])
%ten       = Constant(10) :Int
%new_c     = New(%cls, %ten, param_names: "n") :Object
%inc_call  = MethodCall(%new_c, %cls, method_name: "inc") :Int
%result    = MethodCall(%new_c, %cls, method_name: "val") :Int
control: %inc_call -> %result
return %result
L: GREEN
```

## class-isa

A child class that inherits a method from a parent class via `:isa(Parent)`.
The inherited-method lookup is a static vtable/MRO resolution at compile time
(classes are lexically declared, no runtime `@ISA` mutation in the subset), so it
is runtime-free.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Base { method kind { return 'base' } }
class Child :isa(Base) { }
my $c = Child->new;
$c->kind
```

```behavior
return: Str:base
context: scalar
```

```ir
%kind_body = Constant("base") :Str
%mi_kind   = MethodInfo(name: "kind", body_node: %kind_body, return_repr: "Str")
%base_cls  = ClassInfo(name: "Base", methods: [%mi_kind])
%child_cls = ClassInfo(name: "Child", parent: "Base", parent_ci: %base_cls)
%new_c     = New(%child_cls) :Object
%result    = MethodCall(%new_c, %child_cls, method_name: "kind") :Str
return %result
L: GREEN
```

## adjust

An `ADJUST` block runs after the constructor has bound all `:param` fields. It
can compute derived fields from the constructor arguments. ADJUST is constructor
code writing known struct field offsets — typed struct fields, not Scalar SV*
slots — so it is runtime-free.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Box {
    field $val    :param = 0;
    field $double;
    ADJUST { $double = $val * 2 }
    method double { return $double }
}
my $b = Box->new(val => 7);
$b->double
```

```behavior
return: Int:14
context: scalar
```

```ir
%fa_val    = FieldAccess(field_index: 0, field_stash: "Box") :Int
%two       = Constant(2) :Int
%dbl_val   = Multiply(%fa_val, %two) :Int
%fa_dbl_lv = FieldAccess(field_index: 1, field_stash: "Box") :Int
%fw_dbl    = Assign(%fa_dbl_lv, %dbl_val) :Int
%fa_dbl    = FieldAccess(field_index: 1, field_stash: "Box") :Int
%mi_dbl    = MethodInfo(name: "double", body_node: %fa_dbl, return_repr: "Int")
%mf_val    = MOP::Field(name: "val",    fieldix: 0, param: true,  reader: false, has_default: false, type: "Int")
%mf_dbl    = MOP::Field(name: "double", fieldix: 1, param: false, reader: false, has_default: false, type: "Int")
%cls       = ClassInfo(name: "Box", methods: [%mi_dbl], fields: [%mf_val, %mf_dbl], adjusts: [%fw_dbl])
%seven     = Constant(7) :Int
%new_b     = New(%cls, %seven, param_names: "val") :Object
%result    = MethodCall(%new_b, %cls, method_name: "double") :Int
return %result
L: GREEN
```
