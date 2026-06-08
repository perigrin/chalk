# Classes

`feature class` MOP idioms: class declaration, fields, methods, ADJUST blocks,
and inheritance via `:isa`.

All idioms in this topic are `L: GAP` — but the GAP means "not modelled YET,"
not "needs the interpreter." `feature class` is statically/lexically declared, so
an object is a static `{class*, fields}` struct, a field read is a known offset
load, and method dispatch is a known per-class vtable slot + indirect call (no
runtime `@ISA` mutation in the subset). These are all runtime-free (RF); they are
GAPs only until the MOP object-struct + static-vtable lowering is modelled
(campaign group G5), NOT a libperl/Scalar-SV dependency. Behavior is specified by
perl (the sole oracle); the IR shape records the honest GAP reason rather than
constructing a partial graph.

## class-simple

A minimal `class C {}` with no fields or methods. Instantiating it produces an
object whose `ref()` is the class name. Because the class is statically declared,
the object is a static `{class*, fields}` struct — runtime-free; lowered via G5
MOP static vtable + object struct.

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
%cls    = ClassDecl(class_name: "Empty")
%new_e  = New(%cls) :Object
%result = Ref(%new_e) :Str
return %result
L: GREEN
```

## field-basic

A field declared with `:param` requires the constructor to accept a named
argument. A method that returns the field value reads from the object struct at a
known offset — a typed struct field, not a Scalar SV* slot. The read is
runtime-free; lowered via G5 MOP static vtable + object struct.

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
%meth   = MethodDef(%fa, method_name: "name")
%fdef   = FieldDef(field_name: "name", field_index: 0, is_param: true, has_reader: false, has_default: false)
%cls    = ClassDecl(%meth, %fdef, class_name: "Animal")
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
offset load, statically resolved. Runtime-free; lowered via G5 MOP static vtable
with synthesized reader methods.

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
%fd_l   = FieldDef(field_name: "left",  field_index: 0, is_param: true, has_reader: true, has_default: false, field_repr: "Int")
%fd_r   = FieldDef(field_name: "right", field_index: 1, is_param: true, has_reader: true, has_default: false, field_repr: "Int")
%cls    = ClassDecl(%fd_l, %fd_r, class_name: "Pair")
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
call (static, no runtime `@ISA` mutation), so it is runtime-free; lowered via G5
MOP static vtable emission.

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
%meth   = MethodDef(%body, method_name: "greet")
%cls    = ClassDecl(%meth, class_name: "Greeter")
%new_g  = New(%cls) :Object
%result = MethodCall(%new_g, %cls, method_name: "greet") :Int
return %result
L: GREEN
```

## method-call

A method that mutates a field (`$n += 1`) followed by a method that reads the
same field exercises the full object-mutation + read sequence. The field write is
a store to a known struct offset and the read is a load from the same offset —
typed struct fields, not Scalar SV* slots. Both are runtime-free; lowered via G5
MOP with FieldAccess + FieldWrite in method body context.

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
%fa_n      = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%one       = Constant(1) :Int
%n_plus1   = Add(%fa_n, %one) :Int
%fw_n      = FieldWrite(%n_plus1, field_index: 0) :Int
%meth_inc  = MethodDef(%fw_n, method_name: "inc")
%fa_n2     = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%meth_val  = MethodDef(%fa_n2, method_name: "val")
%fdef_n    = FieldDef(field_name: "n", field_index: 0, is_param: true, has_reader: false, has_default: false, field_repr: "Int")
%cls       = ClassDecl(%meth_inc, %meth_val, %fdef_n, class_name: "Counter")
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
is runtime-free; lowered via G5 MOP compile-time MRO flatten (parent vtable
slots copied into child at lowering time).

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
%meth_kind = MethodDef(%kind_body, method_name: "kind")
%base_cls  = ClassDecl(%meth_kind, class_name: "Base")
%child_cls = ClassDecl(%base_cls, class_name: "Child", parent_name: "Base")
%new_c     = New(%child_cls) :Object
%result    = MethodCall(%new_c, %child_cls, method_name: "kind") :Str
return %result
L: GREEN
```

## adjust

An `ADJUST` block runs after the constructor has bound all `:param` fields. It
can compute derived fields from the constructor arguments. ADJUST is constructor
code writing known struct field offsets — typed struct fields, not Scalar SV*
slots — so it is runtime-free; lowered via G5 MOP ADJUST-as-constructor-code.

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
%fw_dbl    = FieldWrite(%dbl_val, field_index: 1) :Int
%adj       = AdjustBlock(%fw_dbl)
%fa_dbl    = FieldAccess(field_index: 1, field_stash: "Box") :Int
%meth_dbl  = MethodDef(%fa_dbl, method_name: "double")
%fdef_val  = FieldDef(field_name: "val",    field_index: 0, is_param: true,  has_reader: false, has_default: false, field_repr: "Int")
%fdef_dbl  = FieldDef(field_name: "double", field_index: 1, is_param: false, has_reader: false, has_default: false, field_repr: "Int")
%cls       = ClassDecl(%meth_dbl, %fdef_val, %fdef_dbl, %adj, class_name: "Box")
%seven     = Constant(7) :Int
%new_b     = New(%cls, %seven, param_names: "val") :Object
%result    = MethodCall(%new_b, %cls, method_name: "double") :Int
return %result
L: GREEN
```
