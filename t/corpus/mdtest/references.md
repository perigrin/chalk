# References

Array and hash construction, element access, element assignment, anonymous
references, and deref idioms.

All 8 original cases (R1-R8) are now `L: GREEN` — array, hash, and ref
operations are runtime-free (RF): an array is a `{len, cap, Slot*}` vector, a
hash is a `{count, cap, HashEntry*}` table, and a ref is a pointer (bitcast to
i8*). Their operations are pure host-C ops — no libperl AV*/HV*/SV*. The G4
campaign group (Array/Hash representation) closed these cases. Adversarial
cases R9-R11 cover OOB reads, missing-key hash lookups, and hash iteration order
normalization.

Slot representation: `{i1 defined, i64 payload}` — a tagged-scalar. Element
reads return either a defined Int payload or `Undef:` when OOB or key-missing,
matching perl faithfully without sentinel values.

Archive sources used: `anonymous-array.chalk`, `anonymous-hash.chalk`,
`array-literal.chalk`, `hash-literal.chalk`, `array-access.chalk`,
`hash-access.chalk`, `deref-array.chalk`, `deref-hash.chalk` (all from
`archive/pu-2026-03-24:t/corpus/ir/`). Also A2/A3 and C4/C5 from
`t/fixtures/ir-audit-corpus.pl`.

## R1 array literal and scalar count

An array literal `(1, 2, 3)` creates an array — a `{len, cap, Slot*}` vector.
`scalar @a` returns the element count as an Int, a pure load on the vector.
The construction path (allocate the vector, write the elements) is pure
machine-level work; it is runtime-free.

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
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%c3  = Constant(3) :Int
%arr = ArrayRef(%c1, %c2, %c3) :ArrayRef
%r   = Length(%arr) :Int
return %r
L: GREEN
```

## R2 array element read

Reading an element `$a[1]` from a declared array is a bounds-checked index
into the `{len, cap, Slot*}` vector — a pure op. The bounds check is always
emitted; for a known-valid index the OOB branch is dead. The result is an Int.

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
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%c3  = Constant(3) :Int
%arr = ArrayRef(%c1, %c2, %c3) :ArrayRef
%idx = Constant(1) :Int
%r   = Subscript(%arr, %idx) :Int
return %r
L: GREEN
```

## R3 hash literal and element read

A hash literal `(a => 1, b => 2)` creates a hash table `{count, cap, HashEntry*}`.
Reading `$h{a}` is a key lookup — a linear scan with memcmp on Str keys.
Key hashing and bucket dispatch are ordinary machine-level work; no libperl.

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
%ka   = Constant("a") :Str
%v1   = Constant(1) :Int
%kb   = Constant("b") :Str
%v2   = Constant(2) :Int
%hash = HashRef(%ka, %v1, %kb, %v2) :HashRef
%lk   = Constant("a") :Str
%r    = Subscript(%hash, %lk) :Int
return %r
L: GREEN
```

## R4 anonymous array ref and deref

An anonymous array constructor `[1, 2, 3]` allocates a `{len, cap, Slot*}`
vector and yields a pointer to it (bitcast to i8*) — not an AV\* wrapped in
an SV\*. The dereference `$r->[0]` is a load-through-pointer (bitcast back to
%Array*) then a bounds-checked index: both pure ops.

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
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%ref   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%deref = PostfixDeref(%ref, sigil: "@") :Array
%idx   = Constant(0) :Int
%r     = Subscript(%deref, %idx) :Int
return %r
L: GREEN
```

## R5 anonymous hash ref and deref

An anonymous hash constructor `{a => 1, b => 2}` allocates a hash table and
yields a pointer to it — not an HV\* wrapped in an SV\*. The dereference
`$r->{a}` is a load-through-pointer then a key lookup: both pure ops.

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
%ka    = Constant("a") :Str
%v1    = Constant(1) :Int
%kb    = Constant("b") :Str
%v2    = Constant(2) :Int
%ref   = HashRef(%ka, %v1, %kb, %v2) :HashRef
%deref = PostfixDeref(%ref, sigil: "%") :Hash
%lk    = Constant("a") :Str
%r     = Subscript(%deref, %lk) :Int
return %r
L: GREEN
```

## R6 array element assignment

Writing to an array element `$a[0] = 42` is a bounds-checked store into a slot
of the `{len, cap, Slot*}` vector: pure ops, no AV\* mutation. The read back
`$a[0]` is an index into the same vector (which returns the stored value).

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
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%c3   = Constant(3) :Int
%arr  = ArrayRef(%c1, %c2, %c3) :ArrayRef
%idx  = Constant(0) :Int
%lval = Subscript(%arr, %idx) :Int
%nv   = Constant(42) :Int
%r    = Assign(%lval, %nv) :Int
return %r
L: GREEN
```

## R7 hash element assignment

Writing to a hash element `$h{k} = 99` is a store into the hash table
`{count, cap, HashEntry*}`: key scan then slot update — pure ops, no HV\* mutation.
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
%kk   = Constant("k") :Str
%v0   = Constant(0) :Int
%hash = HashRef(%kk, %v0) :HashRef
%wk   = Constant("k") :Str
%lval = Subscript(%hash, %wk) :Int
%wv   = Constant(99) :Int
%r    = Assign(%lval, %wv) :Int
return %r
L: GREEN
```

## R8 nested array ref deref

A two-level dereference `$r->[1][0]` chains two load-through-pointer levels:
the outer ref loads a vector, an index yields an inner ref (an ArrayRef pointer
stored as a slot payload), a second load-through-pointer and index produce the
value. Just repeated pure ops on `{len, cap, Slot*}` vectors plus pointer refs.

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
%ca1       = Constant(1) :Int
%ca2       = Constant(2) :Int
%ca3       = Constant(3) :Int
%ca4       = Constant(4) :Int
%ref0      = ArrayRef(%ca1, %ca2) :ArrayRef
%ref1      = ArrayRef(%ca3, %ca4) :ArrayRef
%outer_ref = ArrayRef(%ref0, %ref1) :ArrayRef
%outer_arr = PostfixDeref(%outer_ref, sigil: "@") :Array
%idx1      = Constant(1) :Int
%inner_ref = Subscript(%outer_arr, %idx1) :ArrayRef
%inner_arr = PostfixDeref(%inner_ref, sigil: "@") :Array
%idx0      = Constant(0) :Int
%r         = Subscript(%inner_arr, %idx0) :Int
return %r
L: GREEN
```

## R9 out-of-bounds array read

An out-of-bounds array read `$a[9]` on a 3-element array returns perl's `undef`
— exactly as perl does. The bounds-check `icmp ult idx, len` is always emitted
in the LLVM IR; when the index exceeds the length, the OOB path yields a
`Slot{defined=false, payload=0}` which the epilogue prints as `Undef:`.
This is NEVER a segfault: bounds-checking is unconditional.

```perl
# source
my @a = (1, 2, 3);
$a[9]
```

```behavior
return: Undef:
context: scalar
```

```ir
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%c3  = Constant(3) :Int
%arr = ArrayRef(%c1, %c2, %c3) :ArrayRef
%idx = Constant(9) :Int
%r   = Subscript(%arr, %idx) :Slot
return %r
L: GREEN
```

## R10 missing-key hash lookup

A missing-key hash lookup `$h{z}` where `z` is not a key returns perl's `undef`.
The linear scan exhausts all entries without a match; the miss path yields a
`Slot{defined=false, payload=0}` which the epilogue prints as `Undef:`.

```perl
# source
my %h = (a => 1, b => 2);
$h{z}
```

```behavior
return: Undef:
context: scalar
```

```ir
%ka   = Constant("a") :Str
%v1   = Constant(1) :Int
%kb   = Constant("b") :Str
%v2   = Constant(2) :Int
%hash = HashRef(%ka, %v1, %kb, %v2) :HashRef
%lk   = Constant("z") :Str
%r    = Subscript(%hash, %lk) :Slot
return %r
L: GREEN
```

## R11 hash keys sorted order

`join(",", sort keys %h)` returns the keys in sorted (normalized) order.
Hash iteration order is randomized in perl; the corpus normalizes by sorting.
This case is `L: GAP` because `sort` and `join` are not yet in the LLVM
lowering slice — they require list-context operations that are deferred to a
future campaign group (list operators / control-flow-in-list). The behavior is
specified for deterministic sorted output; unsorted reliance would be non-stable.

The guard: raw `keys %h` order without sorting is NOT asserted as a stable GREEN
result (perl's hash randomization makes it non-deterministic). Only the sorted
form is corpus-stable.

```perl
# source
my %h = (b => 2, a => 1);
join(",", sort keys %h)
```

```behavior
return: a,b
context: scalar
```

```ir
L: GAP(sort+join+keys requires list-context ops not yet in LLVM slice; deferred to list-operators campaign group)
```
