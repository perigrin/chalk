# References

Array and hash construction, element access, element assignment, anonymous
references, and deref idioms.

All cases in this topic are `L: GAP`. Arrays and hashes require a Perl `Scalar`
(SV\*) representation — they hold reference-counted heap values. None of the
array/hash/ref operations are runtime-free lowerable in the current Int/Num/Str
arithmetic slice. The behavior oracle (perl) is specified for every case;
the IR block records the honest GAP reason rather than fabricating a constructive
graph that does not exist yet.

Archive sources used: `anonymous-array.chalk`, `anonymous-hash.chalk`,
`array-literal.chalk`, `hash-literal.chalk`, `array-access.chalk`,
`hash-access.chalk`, `deref-array.chalk`, `deref-hash.chalk` (all from
`archive/pu-2026-03-24:t/corpus/ir/`). Also A2/A3 and C4/C5 from
`t/fixtures/ir-audit-corpus.pl`.

## R1 array literal and scalar count

An array literal `(1, 2, 3)` creates a Perl array (AV\*). `scalar @a` returns
the element count as an integer. The array itself has no runtime-free IR
representation: it requires an AV\* backed by a Scalar/SV layout. The count
could be an Int in principle, but the construction path (array allocation,
element insertion) is not lowerable without SV\* support.

```perl
# source
my @a = (1, 2, 3);
scalar @a
```

```behavior
return: 3
context: scalar
```

```ir
L: GAP(arrays require AV*/Scalar representation; array allocation not runtime-free)
```

## R2 array element read

Reading an element `$a[1]` from a declared array requires subscript access on
an AV\*. Even though the result is an integer, the lookup path goes through the
Perl runtime — the subscript operation has no Int-level IR node.

```perl
# source
my @a = (1, 2, 3);
$a[1]
```

```behavior
return: 2
context: scalar
```

```ir
L: GAP(array subscript requires AV*/Scalar representation; no runtime-free ArrayIndex node)
```

## R3 hash literal and element read

A hash literal `(a => 1, b => 2)` creates a Perl hash (HV\*). Reading `$h{a}`
requires key-based lookup on the HV\*, which is not runtime-free. Key interning,
bucket dispatch, and SV\* dereferencing all require the Perl runtime.

```perl
# source
my %h = (a => 1, b => 2);
$h{a}
```

```behavior
return: 1
context: scalar
```

```ir
L: GAP(hashes require HV*/Scalar representation; hash key lookup not runtime-free)
```

## R4 anonymous array ref and deref

An anonymous array constructor `[1, 2, 3]` allocates an AV\* and wraps it in
a reference SV\*. The dereference `$r->[0]` follows the reference and subscripts
the AV\*. Both the allocation and the deref are Scalar-level operations — no
runtime-free lowering exists.

```perl
# source
my $r = [1, 2, 3];
$r->[0]
```

```behavior
return: 1
context: scalar
```

```ir
L: GAP(anonymous arrayref allocates AV* + SV* ref; deref and subscript require Scalar representation)
```

## R5 anonymous hash ref and deref

An anonymous hash constructor `{a => 1, b => 2}` allocates an HV\* and wraps it
in a reference SV\*. The dereference `$r->{a}` follows the reference and looks up
the key in the HV\*. Both construction and lookup are Scalar-level.

```perl
# source
my $r = {a => 1, b => 2};
$r->{a}
```

```behavior
return: 1
context: scalar
```

```ir
L: GAP(anonymous hashref allocates HV* + SV* ref; deref and key lookup require Scalar representation)
```

## R6 array element assignment

Writing to an array element `$a[0] = 42` requires AV\* mutation: bounds-check,
slot access, and SV\* store. The array must already be backed by a Scalar layout.
The read back `$a[0]` similarly goes through the AV\*.

```perl
# source
my @a = (1, 2, 3);
$a[0] = 42;
$a[0]
```

```behavior
return: 42
context: scalar
```

```ir
L: GAP(array element assign mutates AV*/Scalar slot; no runtime-free ArrayStore node)
```

## R7 hash element assignment

Writing to a hash element `$h{k} = 99` requires HV\* mutation: key hashing,
bucket insertion, and SV\* store. The read back `$h{k}` is a key lookup.
Both are Scalar-level operations.

```perl
# source
my %h = (k => 0);
$h{k} = 99;
$h{k}
```

```behavior
return: 99
context: scalar
```

```ir
L: GAP(hash element assign mutates HV*/Scalar slot; no runtime-free HashStore node)
```

## R8 nested array ref deref

A two-level dereference `$r->[1][0]` chains two AV\* subscript operations through
SV\* references. This requires the same Scalar/SV layout as the single-level case,
plus an additional reference-follow step.

```perl
# source
my $r = [[1, 2], [3, 4]];
$r->[1][0]
```

```behavior
return: 3
context: scalar
```

```ir
L: GAP(nested arrayref requires two AV*/SV* deref levels; no runtime-free lowering for chained subscript)
```
