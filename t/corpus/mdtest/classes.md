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
%cls    = MOP::Class(name: "Empty")
%new_e  = Call(dispatch_kind: "method", name: "new", class: "Empty") :Object
%result = RefType(%new_e) :Str
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
%cls    = MOP::Class(name: "Animal")
%mf     = MOP::Field(class: %cls, name: "name", fieldix: 0, param: true, reader: false, has_default: false, type: "Str")
%fa     = FieldAccess(field_index: 0, field_stash: "Animal") :Str
%mi     = MOP::Method(class: %cls, name: "name", body: %fa, return_repr: "Str")
%nval   = Constant("cat") :Str
%new_a  = Call(%nval, dispatch_kind: "method", name: "new", class: "Animal", param_names: "name") :Object
%result = Call(%new_a, dispatch_kind: "method", name: "name", class: "Animal") :Str
return %result
L: GREEN
```

## field-str-default

A `:param` field with a Str DEFAULT. Constructed with no argument, the field
takes its default value. The default is boxed into a %StrPair the same way a
supplied Str `:param` is, via the shared field-payload store helper — earlier
only Int defaults lowered and a Str default GAPped (019f4512).

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Greeter {
    field $msg :param = "hi";
    method hello { return $msg }
}
my $g = Greeter->new;
$g->hello
```

```behavior
return: Str:hi
context: scalar
```

```ir
%cls    = MOP::Class(name: "Greeter")
%mf     = MOP::Field(class: %cls, name: "msg", fieldix: 0, param: true, reader: false, has_default: true, type: "Str")
%fa     = FieldAccess(field_index: 0, field_stash: "Greeter") :Str
%mi     = MOP::Method(class: %cls, name: "hello", body: %fa, return_repr: "Str")
%new_g  = Call(dispatch_kind: "method", name: "new", class: "Greeter") :Object
%result = Call(%new_g, dispatch_kind: "method", name: "hello", class: "Greeter") :Str
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
%cls    = MOP::Class(name: "Pair")
%mf_l   = MOP::Field(class: %cls, name: "left",  fieldix: 0, param: true, reader: true, has_default: false, type: "Int")
%mf_r   = MOP::Field(class: %cls, name: "right", fieldix: 1, param: true, reader: true, has_default: false, type: "Int")
%lval   = Constant(10) :Int
%rval   = Constant(20) :Int
%new_p  = Call(%lval, %rval, dispatch_kind: "method", name: "new", class: "Pair", param_names: "left,right") :Object
%lr     = Call(%new_p, dispatch_kind: "method", name: "left", class: "Pair")  :Int
%rr     = Call(%new_p, dispatch_kind: "method", name: "right", class: "Pair") :Int
%result = Add(%lr, %rr) :Int
return %result
L: GREEN
```

## field-attrs-custom-param

A `:reader` field whose `:param(NAME)` gives the constructor parameter a name
DIFFERENT from the field variable (`field $left :param(alpha) :reader`). The
reader accessor is still named after the VARIABLE (`left`), not the param. The
field's variable name must come from the class's own field metadata
(`xhv_class_fields`), not `$` . param_name -- else the reader is mis-detected and
emitted as a shadowing user-method that GAPs (zhi 019f4625). Neither field is
referenced by any method or ADJUST body, which is exactly the case that exposed
the bug.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Pair {
    field $left  :param(alpha) :reader;
    field $right :param(beta)  :reader;
}
my $p = Pair->new(alpha => 10, beta => 20);
$p->left - $p->right
```

```behavior
return: Int:-10
context: scalar
```

```ir
%cls    = MOP::Class(name: "Pair")
%mf_l   = MOP::Field(class: %cls, name: "left",  fieldix: 0, param: true, reader: true, has_default: false, type: "Int")
%mf_r   = MOP::Field(class: %cls, name: "right", fieldix: 1, param: true, reader: true, has_default: false, type: "Int")
%lval   = Constant(10) :Int
%rval   = Constant(20) :Int
%new_p  = Call(%lval, %rval, dispatch_kind: "method", name: "new", class: "Pair", param_names: "alpha,beta") :Object
%lr     = Call(%new_p, dispatch_kind: "method", name: "left", class: "Pair")  :Int
%rr     = Call(%new_p, dispatch_kind: "method", name: "right", class: "Pair") :Int
%result = Subtract(%lr, %rr) :Int
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
%cls    = MOP::Class(name: "Greeter")
%body   = Constant(42) :Int
%mi     = MOP::Method(class: %cls, name: "greet", body: %body, return_repr: "Int")
%new_g  = Call(dispatch_kind: "method", name: "new", class: "Greeter") :Object
%result = Call(%new_g, dispatch_kind: "method", name: "greet", class: "Greeter") :Int
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
%cls       = MOP::Class(name: "Counter")
%mf_n      = MOP::Field(class: %cls, name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%fa_n_lv   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%fa_n_rd   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%one       = Constant(1) :Int
%n_plus1   = Add(%fa_n_rd, %one) :Int
%fw_n      = Assign(%fa_n_lv, %n_plus1) :Int
%mi_inc    = MOP::Method(class: %cls, name: "inc", body: %fw_n, return_repr: "Int")
%fa_n2     = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%mi_val    = MOP::Method(class: %cls, name: "val", body: %fa_n2, return_repr: "Int")
%ten       = Constant(10) :Int
%new_c     = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%inc_call  = Call(%new_c, dispatch_kind: "method", name: "inc", class: "Counter") :Int
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
control: %inc_call -> %result
return %result
L: GREEN
```

## method-call-chain

A CHAIN of two void mutating calls followed by a read: `$c->inc; $c->inc;
$c->val`. Each `inc` stores the incremented field back, and the two stores are
memory-ordered (call 2 observes call 1's store), so `val` reads the accumulated
value. The non-tail `inc` is a void statement effect threaded via control_in;
without ordering both it and the field mutation would be lost (zhi 019f2dee).

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
$c->inc;
$c->val
```

```behavior
return: Int:12
context: scalar
```

```ir
%cls       = MOP::Class(name: "Counter")
%mf_n      = MOP::Field(class: %cls, name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%ten       = Constant(10) :Int
%new_c     = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%inc1      = Call(%new_c, dispatch_kind: "method", name: "inc", class: "Counter") :Int
%inc2      = Call(%new_c, dispatch_kind: "method", name: "inc", class: "Counter") :Int
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
control: %inc1 -> %inc2 -> %result
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
%base_cls  = MOP::Class(name: "Base")
%kind_body = Constant("base") :Str
%mi_kind   = MOP::Method(class: %base_cls, name: "kind", body: %kind_body, return_repr: "Str")
%child_cls = MOP::Class(name: "Child", parent: "Base")
%new_c     = Call(dispatch_kind: "method", name: "new", class: "Child") :Object
%result    = Call(%new_c, dispatch_kind: "method", name: "kind", class: "Child") :Str
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
%cls       = MOP::Class(name: "Box")
%mf_val    = MOP::Field(class: %cls, name: "val",    fieldix: 0, param: true,  reader: false, has_default: false, type: "Int")
%mf_dbl    = MOP::Field(class: %cls, name: "double", fieldix: 1, param: false, reader: false, has_default: false, type: "Int")
%fa_val    = FieldAccess(field_index: 0, field_stash: "Box") :Int
%two       = Constant(2) :Int
%dbl_val   = Multiply(%fa_val, %two) :Int
%fa_dbl_lv = FieldAccess(field_index: 1, field_stash: "Box") :Int
%fw_dbl    = Assign(%fa_dbl_lv, %dbl_val) :Int
%adj       = MOP::Adjust(class: %cls, body: [%fw_dbl])
%fa_dbl    = FieldAccess(field_index: 1, field_stash: "Box") :Int
%mi_dbl    = MOP::Method(class: %cls, name: "double", body: %fa_dbl, return_repr: "Int")
%seven     = Constant(7) :Int
%new_b     = Call(%seven, dispatch_kind: "method", name: "new", class: "Box", param_names: "val") :Object
%result    = Call(%new_b, dispatch_kind: "method", name: "double", class: "Box") :Int
return %result
L: GREEN
```

## conditional-void-call

A void mutating method call GUARDED by a runtime condition: `$c->inc if $x > 3`.
The call runs only when the guard is true, so its field store is
control-dependent on the branch: it is walked on the true Proj (control-threaded)
and a Region merges the taken/not-taken edges. The post-branch `val` read
observes the merged state. Without building the branch control flow, the void
call rebinds no pad slot and the effect is silently dropped when taken (zhi
019f2df7). The invocant (the `new` construction bound to `$c`) is used both in
the guarded arm and after the merge, so it is pre-lowered in the dominating
pre-branch block.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method inc { $n = $n + 1 }
    method val { return $n }
}
my $c = Counter->new(n => 10);
my $x = 5;
$c->inc if $x > 3;
$c->val
```

```behavior
return: Int:11
context: scalar
```

```ir
%ten       = Constant(10) :Int
%new_c     = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%five      = Constant(5) :Int
%three     = Constant(3) :Int
%cmp       = NumGt(%five, %three) :Bool
%if        = If(%cmp)
%proj0     = Proj(%if, index: 0)
%proj1     = Proj(%if, index: 1)
%inc       = Call(%new_c, dispatch_kind: "method", name: "inc", class: "Counter") :Int
%region    = Region(%proj1, %inc)
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
return %result
branch_control: %proj0 -> %inc
L: GREEN
```

## method-branched-field-store

A method whose body is an if/else that mutates a field in BOTH arms
(`method bump { if ($n < 100) { $n = $n + 5 } else { $n = $n + 1 } }`). Each arm's
field store is control-dependent on its own branch Proj and a Region merges the
arms, so the mutation persists exactly like a straight-line `$n += 1` store. The
method body lowers through the same control-chain elaboration the top-level graph
uses; a linear control_in walk would stop at the merge Region and drop the arm
stores, leaving the field unmutated (zhi 019f5368: `bump; val` returned 10, not
15). The method's own return value is the discarded assignment residual (Undef).

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method bump { if ($n < 100) { $n = $n + 5 } else { $n = $n + 1 } }
    method val { $n }
}
my $c = Counter->new(n => 10);
$c->bump;
$c->val
```

```behavior
return: Int:15
context: scalar
```

```ir
%cls       = MOP::Class(name: "Counter")
%mf_n      = MOP::Field(class: %cls, name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%fa_rd     = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%hundred   = Constant(100) :Int
%cmp       = NumLt(%fa_rd, %hundred) :Bool
%if        = If(%cmp)
%proj0     = Proj(%if, index: 0)
%proj1     = Proj(%if, index: 1)
%five      = Constant(5) :Int
%sum_t     = Add(%fa_rd, %five) :Int
%fa_lv_t   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%store_t   = Assign(%fa_lv_t, %sum_t) :Int
%one       = Constant(1) :Int
%sum_f     = Add(%fa_rd, %one) :Int
%fa_lv_f   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%store_f   = Assign(%fa_lv_f, %sum_f) :Int
%region    = Region(%store_t, %store_f)
%mi_bump   = MOP::Method(class: %cls, name: "bump", body: %region, return_repr: "Undef")
%fa_val    = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%mi_val    = MOP::Method(class: %cls, name: "val", body: %fa_val, return_repr: "Int")
%ten       = Constant(10) :Int
%new_c     = Call(%ten, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%bump_call = Call(%new_c, dispatch_kind: "method", name: "bump", class: "Counter") :Undef
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
control: %bump_call -> %result
branch_control: %proj0 -> %store_t
return %result
L: GREEN
```

## method-branched-field-store-else-arm

The `else`-arm sibling of method-branched-field-store: constructing with `n = 200`
makes `$n < 100` FALSE, so the ELSE arm (`$n = $n + 1`, control-dependent on Proj
index 1) runs and the field becomes 201. This is the bilateral coverage for the
branch — the then-arm case (n = 10 -> 15) never exercises the else store, so a
miscompile that drops only the else arm or selects the wrong Proj would gate-green
without it.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method bump { if ($n < 100) { $n = $n + 5 } else { $n = $n + 1 } }
    method val { $n }
}
my $c = Counter->new(n => 200);
$c->bump;
$c->val
```

```behavior
return: Int:201
context: scalar
```

```ir
%cls       = MOP::Class(name: "Counter")
%mf_n      = MOP::Field(class: %cls, name: "n", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%fa_rd     = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%hundred   = Constant(100) :Int
%cmp       = NumLt(%fa_rd, %hundred) :Bool
%if        = If(%cmp)
%proj0     = Proj(%if, index: 0)
%proj1     = Proj(%if, index: 1)
%five      = Constant(5) :Int
%sum_t     = Add(%fa_rd, %five) :Int
%fa_lv_t   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%store_t   = Assign(%fa_lv_t, %sum_t) :Int
%one       = Constant(1) :Int
%sum_f     = Add(%fa_rd, %one) :Int
%fa_lv_f   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%store_f   = Assign(%fa_lv_f, %sum_f) :Int
%region    = Region(%store_t, %store_f)
%mi_bump   = MOP::Method(class: %cls, name: "bump", body: %region, return_repr: "Undef")
%fa_val    = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%mi_val    = MOP::Method(class: %cls, name: "val", body: %fa_val, return_repr: "Int")
%c200      = Constant(200) :Int
%new_c     = Call(%c200, dispatch_kind: "method", name: "new", class: "Counter", param_names: "n") :Object
%bump_call = Call(%new_c, dispatch_kind: "method", name: "bump", class: "Counter") :Undef
%result    = Call(%new_c, dispatch_kind: "method", name: "val", class: "Counter") :Int
control: %bump_call -> %result
branch_control: %proj1 -> %store_f
return %result
L: GREEN
```

## self-method-call in a value position

A method that calls a SIBLING method on `$self` in a value position
(`method pick { $self->flag() ? 10 : 20 }`). The `$self->flag()` Call records its
statically-known class (the enclosing class, from the CV stash) so the backend
dispatches it, and the self receiver lowers to the method's %self object pointer
(zhi 019f5dec). This is the most common method-dispatch shape in real lib/ methods
(e.g. Chalk::Grammar::Symbol::to_string calls `$self->is_terminal()`).

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Widget {
    method flag { 1 }
    method pick { $self->flag() ? 10 : 20 }
}
Widget->new->pick
```

```behavior
return: Int:10
context: scalar
```

```ir
%cls    = MOP::Class(name: "Widget")
%new_w  = Call(dispatch_kind: "method", name: "new", class: "Widget") :Object
%result = Call(%new_w, dispatch_kind: "method", name: "pick", class: "Widget") :Int
return %result
L: GREEN
```

## conditional string append (.= guarded by a postfix if)

A method that appends to a string only when a field is defined
(`method m { my $s = $v; $s .= $q if defined $q; $s }`) currently GAPs at the
method body root NO representation -- the branch-guarded `.=` field/local append in
a return-value position is not yet lowered (distinct from the branch-guarded
element/field STORE, which is; this is a value-context conditional Concat). This is
the second NO-REPR trigger in Chalk::Grammar::Symbol::to_string
(`$str .= $quantifier if defined $quantifier`).

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Tagged {
    field $v :param;
    field $q :param = undef;
    method render {
        my $s = $v;
        $s .= $q if defined $q;
        $s
    }
}
Tagged->new(v => "a", q => "b")->render
```

```behavior
return: Str:ab
context: scalar
```

```ir
L: GAP(a value-context conditional string append -- $s .= $x if defined $x -- feeding the method return is not yet lowered; the branch-guarded Concat residual reaches the method body root with no representation)
```
