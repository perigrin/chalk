# Classes

`feature class` MOP idioms: class declaration, fields, methods, ADJUST blocks,
and inheritance via `:isa`.

All idioms in this topic are `L: GAP` — class/object representation requires the
full MOP and Scalar object model, neither of which is in the current runtime-free
lowering slice. Behavior is specified by perl (the sole oracle); the IR shape
records the honest GAP reason rather than constructing a partial graph.

## class-simple

A minimal `class C {}` with no fields or methods. Instantiating it produces a
blessed scalar reference whose `ref()` is the class name. The object exists
entirely in the MOP's Scalar representation; there is no runtime-free IR for it.

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Empty { }
my $e = Empty->new;
ref($e)
```

```behavior
return: Empty
context: scalar
```

```ir
L: GAP(class/object needs MOP + Scalar representation; not runtime-free lowerable)
```

## field-basic

A field declared with `:param` requires the constructor to accept a named
argument. A method that returns the field value reads from the object's Scalar
slot, which is part of the MOP representation not yet in the IR.

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
return: cat
context: scalar
```

```ir
L: GAP(field read requires MOP Scalar slot access; not runtime-free lowerable)
```

## field-attrs

Fields may combine `:param` (constructor binding) and `:reader` (auto-generated
accessor method). The `:reader` attribute tells the MOP to synthesize a method
that returns the field value — purely an object-model feature, with no
runtime-free IR representation.

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
return: 30
context: scalar
```

```ir
L: GAP(field :reader synthesis and object slot access need MOP + Scalar representation)
```

## method-simple

A method that ignores `$self` and returns a literal value is the simplest
non-trivial method. Even though the body contains only a constant, the dispatch
path (object lookup, method resolution, invocant binding) belongs to the MOP
layer and is not runtime-free.

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
return: 42
context: scalar
```

```ir
L: GAP(method dispatch requires MOP object lookup; not runtime-free even for constant body)
```

## method-call

A method that mutates a field (`$n += 1`) followed by a method that reads the
same field exercises the full object-mutation + read sequence. The field write
requires an object Scalar slot write, and the subsequent read requires a slot
read — both depend on the MOP representation.

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
return: 11
context: scalar
```

```ir
L: GAP(field mutation and read across method calls requires MOP Scalar slot write/read)
```

## class-isa

A child class that inherits a method from a parent class via `:isa(Parent)`.
The dispatch must walk the MRO (method resolution order) to find the inherited
method on the parent. MRO lookup is part of the MOP layer and has no
runtime-free representation.

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
return: base
context: scalar
```

```ir
L: GAP(MRO lookup for inherited method requires MOP; not runtime-free lowerable)
```

## adjust

An `ADJUST` block runs after the constructor has bound all `:param` fields. It
can compute derived fields from the constructor arguments. The ADJUST mechanism
is entirely within the MOP constructor protocol and depends on the object's
Scalar representation for both reads and writes.

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
return: 14
context: scalar
```

```ir
L: GAP(ADJUST block writes derived fields via MOP constructor protocol; needs Scalar representation)
```
