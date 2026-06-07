# References

Array and hash construction, element access, element assignment, anonymous
references, and deref idioms.

All cases in this topic are `L: GAP`. Arrays, hashes, and refs are all
runtime-free (RF): an array is a `{len, cap, elem*}` vector, a hash is a hash
table `{Str->value}`, and a ref is a pointer to one of those structs plus a ref
tag. Their operations (push/pop/index/scalar/slice, keys/values/exists/delete/
lookup, deref/element) are pure ops — load-through-pointer for refs. None of
these need the Perl interpreter. The GAP here means the Array/Hash
representations are simply not modelled YET; clearing them is a work-list item
for campaign group G4 (Array/Hash), NOT a libperl dependency. The behavior
oracle (perl) is specified for every case; the IR block records the honest GAP
reason rather than fabricating a constructive graph that does not exist yet.

Archive sources used: `anonymous-array.chalk`, `anonymous-hash.chalk`,
`array-literal.chalk`, `hash-literal.chalk`, `array-access.chalk`,
`hash-access.chalk`, `deref-array.chalk`, `deref-hash.chalk` (all from
`archive/pu-2026-03-24:t/corpus/ir/`). Also A2/A3 and C4/C5 from
`t/fixtures/ir-audit-corpus.pl`.

## R1 array literal and scalar count

An array literal `(1, 2, 3)` creates an array — a `{len, cap, elem*}` vector,
not an AV\*. `scalar @a` returns the element count as an Int, a pure op on the
vector. The construction path (allocate the vector, write the elements) is all
pure machine-level work; it is runtime-free. It is a GAP only because the Array
representation is not modelled yet (campaign group G4).

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
L: GAP(array is RF: a {len,cap,elem*} vector, allocation + scalar-count are pure ops; GAP only until the Array representation (G4) is modelled, NOT a libperl/AV dependency)
```

## R2 array element read

Reading an element `$a[1]` from a declared array is an index into a
`{len, cap, elem*}` vector — a pure op, not an AV\* access. The result is an Int.
There is nothing runtime-bound here; the index node is just not modelled yet.

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
L: GAP(array index is RF: index into a {len,cap,elem*} vector is a pure op; GAP only until the Array representation (G4) is modelled, NOT a libperl/AV dependency)
```

## R3 hash literal and element read

A hash literal `(a => 1, b => 2)` creates a hash table `{Str->value}`, not an
HV\*. Reading `$h{a}` is a key lookup — a pure op on that table. Key hashing and
bucket dispatch are ordinary machine-level work; none of it needs the Perl
runtime.

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
L: GAP(hash is RF: a hash table {Str->value}, key lookup is a pure op; GAP only until the Hash representation (G4) is modelled, NOT a libperl/HV dependency)
```

## R4 anonymous array ref and deref

An anonymous array constructor `[1, 2, 3]` allocates a `{len, cap, elem*}`
vector and yields a pointer to it plus a ref tag — not an AV\* wrapped in an
SV\*. The dereference `$r->[0]` is load-through-pointer then index: both pure
ops. The whole thing is runtime-free.

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
L: GAP(arrayref is RF: a {len,cap,elem*} vector + a pointer/tag ref, deref = load-through-pointer then index; GAP only until Array/Hash representations (G4) are modelled, NOT a libperl/SV/AV dependency)
```

## R5 anonymous hash ref and deref

An anonymous hash constructor `{a => 1, b => 2}` allocates a hash table
`{Str->value}` and yields a pointer to it plus a ref tag — not an HV\* wrapped
in an SV\*. The dereference `$r->{a}` is load-through-pointer then key lookup:
both pure ops. Construction and lookup are runtime-free.

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
L: GAP(hashref is RF: a hash table {Str->value} + a pointer/tag ref, deref = load-through-pointer then key lookup, both pure ops; GAP only until Array/Hash representations (G4) are modelled, NOT a libperl/SV/HV dependency)
```

## R6 array element assignment

Writing to an array element `$a[0] = 42` is a store into a slot of the
`{len, cap, elem*}` vector: bounds-check then slot write — pure ops, no AV\*
mutation. The read back `$a[0]` is an index into the same vector.

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
L: GAP(array element store is RF: store into a slot of a {len,cap,elem*} vector is a pure op; GAP only until the Array representation (G4) is modelled, NOT a libperl/AV dependency)
```

## R7 hash element assignment

Writing to a hash element `$h{k} = 99` is a store into the hash table
`{Str->value}`: key hashing then bucket insertion — pure ops, no HV\* mutation.
The read back `$h{k}` is a key lookup on the same table.

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
L: GAP(hash element store is RF: store into a hash table {Str->value} is a pure op; GAP only until the Hash representation (G4) is modelled, NOT a libperl/HV dependency)
```

## R8 nested array ref deref

A two-level dereference `$r->[1][0]` chains two load-through-pointer levels: the
outer ref loads a vector, an index yields an inner ref, a second
load-through-pointer and index produce the value. Just repeated pure ops on
`{len, cap, elem*}` vectors plus pointer/tag refs — runtime-free, like the
single-level case with one more follow step.

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
L: GAP(nested arrayref is RF: two load-through-pointer levels, each index a pure op; GAP only until Array/Hash representations (G4) are modelled, NOT a libperl dependency)
```
