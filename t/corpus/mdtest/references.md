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
use 5.42.0;
my @a = (1, 2, 3);
say(scalar @a);
```

```behavior
stdout: 3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%c3  = Constant(3) :Int
%arr = ArrayRef(%c1, %c2, %c3) :ArrayRef
%r   = Length(%arr) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R1b array in implicit scalar context (assignment)

Assigning an array to a scalar (`my $n = @a`) imposes scalar context WITHOUT an
explicit `scalar` op — perl counts the array. The producer keys on the RHS being
an aggregate-variable read (padav) and wraps it in a `Length`, exactly as
`scalar @a` does; an anon-ref literal (`my $r = [1,2,3]`) is a scalar reference
and is left alone. The graph is identical to R1: the count is a pure load.

```perl
# source
use 5.42.0;
my @a = (1, 2, 3);
my $n = @a;
say($n);
```

```behavior
stdout: 3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%c3  = Constant(3) :Int
%arr = ArrayRef(%c1, %c2, %c3) :ArrayRef
%r   = Length(%arr) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R2 array element read

Reading an element `$a[1]` from a declared array is a bounds-checked index
into the `{len, cap, Slot*}` vector — a pure op. The bounds check is always
emitted; for a known-valid index the OOB branch is dead. The result is an Int.

```perl
# source
use 5.42.0;
my @a = (1, 2, 3);
say($a[1]);
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%c3  = Constant(3) :Int
%arr = ArrayRef(%c1, %c2, %c3) :ArrayRef
%idx = Constant(1) :Int
%r   = Subscript(%arr, %idx) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R3 hash literal and element read

A hash literal `(a => 1, b => 2)` creates a hash table `{count, cap, HashEntry*}`.
Reading `$h{a}` is a key lookup — a linear scan with memcmp on Str keys.
Key hashing and bucket dispatch are ordinary machine-level work; no libperl.

```perl
# source
use 5.42.0;
my %h = (a => 1, b => 2);
say($h{a});
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%ka   = Constant("a") :Str
%v1   = Constant(1) :Int
%kb   = Constant("b") :Str
%v2   = Constant(2) :Int
%hash = HashRef(%ka, %v1, %kb, %v2) :HashRef
%lk   = Constant("a") :Str
%r    = Subscript(%hash, %lk) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R3b hash in scalar context (key count)

Assigning a hash to a scalar (`my $n = %h`) imposes scalar context; modern perl
yields the key count. The producer wraps the HashRef in a `Length` (like the
array case), and the backend loads the `count` field of the `%Hash` struct
(`{count, cap, HashEntry*}`, field 0) — a pure load, no libperl.

```perl
# source
use 5.42.0;
my %h = (a => 1, b => 2);
my $n = %h;
say($n);
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%ka   = Constant("a") :Str
%v1   = Constant(1) :Int
%kb   = Constant("b") :Str
%v2   = Constant(2) :Int
%hash = HashRef(%ka, %v1, %kb, %v2) :HashRef
%r    = Length(%hash) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R4 anonymous array ref and deref

An anonymous array constructor `[1, 2, 3]` allocates a `{len, cap, Slot*}`
vector and yields a pointer to it (bitcast to i8*) — not an AV\* wrapped in
an SV\*. The dereference `$r->[0]` is a load-through-pointer (bitcast back to
%Array*) then a bounds-checked index: both pure ops.

```perl
# source
use 5.42.0;
my $r = [1, 2, 3];
say($r->[0]);
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%ref   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%deref = PostfixDeref(%ref, sigil: "@") :Array
%idx   = Constant(0) :Int
%r     = Subscript(%deref, %idx) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R5 anonymous hash ref and deref

An anonymous hash constructor `{a => 1, b => 2}` allocates a hash table and
yields a pointer to it — not an HV\* wrapped in an SV\*. The dereference
`$r->{a}` is a load-through-pointer then a key lookup: both pure ops.

```perl
# source
use 5.42.0;
my $r = {a => 1, b => 2};
say($r->{a});
```

```behavior
stdout: 1\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%ka    = Constant("a") :Str
%v1    = Constant(1) :Int
%kb    = Constant("b") :Str
%v2    = Constant(2) :Int
%ref   = HashRef(%ka, %v1, %kb, %v2) :HashRef
%deref = PostfixDeref(%ref, sigil: "%") :Hash
%lk    = Constant("a") :Str
%r     = Subscript(%deref, %lk) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R6 array element assignment

Writing to an array element `$a[0] = 42` is a bounds-checked store into a slot
of the `{len, cap, Slot*}` vector: pure ops, no AV\* mutation. The read back
`$a[0]` is an index into the same vector (which returns the stored value).

```perl
# source
use 5.42.0;
my @a = (1, 2, 3);
$a[0] = 42;
say($a[0]);
```

```behavior
stdout: 42\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%c3   = Constant(3) :Int
%arr  = ArrayRef(%c1, %c2, %c3) :ArrayRef
%idx  = Constant(0) :Int
%lval = Subscript(%arr, %idx) :Int
%nv   = Constant(42) :Int
%r    = Assign(%lval, %nv) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R7 hash element assignment

Writing to a hash element `$h{k} = 99` is a store into the hash table
`{count, cap, HashEntry*}`: key scan then slot update — pure ops, no HV\* mutation.
The read back `$h{k}` is a key lookup on the same table.

```perl
# source
use 5.42.0;
my %h = (k => 0);
$h{k} = 99;
say($h{k});
```

```behavior
stdout: 99\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%kk   = Constant("k") :Str
%v0   = Constant(0) :Int
%hash = HashRef(%kk, %v0) :HashRef
%wk   = Constant("k") :Str
%lval = Subscript(%hash, %wk) :Int
%wv   = Constant(99) :Int
%r    = Assign(%lval, %wv) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R8 nested array ref deref

A two-level dereference `$r->[1][0]` chains two load-through-pointer levels:
the outer ref loads a vector, an index yields an inner ref (an ArrayRef pointer
stored as a slot payload), a second load-through-pointer and index produce the
value. Just repeated pure ops on `{len, cap, Slot*}` vectors plus pointer refs.

```perl
# source
use 5.42.0;
my $r = [[1, 2], [3, 4]];
say($r->[1][0]);
```

```behavior
stdout: 3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
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
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
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
use 5.42.0;
my @a = (1, 2, 3);
say($a[9]);
```

```behavior
stdout: \n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%c3  = Constant(3) :Int
%arr = ArrayRef(%c1, %c2, %c3) :ArrayRef
%idx = Constant(9) :Int
%r   = Subscript(%arr, %idx) :Slot
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Slot -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R10 missing-key hash lookup

A missing-key hash lookup `$h{z}` where `z` is not a key returns perl's `undef`.
The linear scan exhausts all entries without a match; the miss path yields a
`Slot{defined=false, payload=0}` which the epilogue prints as `Undef:`.

```perl
# source
use 5.42.0;
my %h = (a => 1, b => 2);
say($h{z});
```

```behavior
stdout: \n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%ka   = Constant("a") :Str
%v1   = Constant(1) :Int
%kb   = Constant("b") :Str
%v2   = Constant(2) :Int
%hash = HashRef(%ka, %v1, %kb, %v2) :HashRef
%lk   = Constant("z") :Str
%r    = Subscript(%hash, %lk) :Slot
%nl = Constant("\n") :Str
%co_p  = Coerce(%r : Slot -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
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

## R12 aliased element store (store via ref, read via name)

Storing through an alias `$r->[0] = 42` (where `$r = \@a`) mutates the SAME
underlying array as `@a`, so a subsequent `$a[0]` must see `42`. `$r->[0]`
subscripts the `Ref` node while `$a[0]` subscripts the `ArrayRef` node the `Ref`
wraps. Because `\@a` and `@a` share backing storage in Perl, the `Ref` is a
transparent alias: the store-lvalue path unwraps it to its target `ArrayRef`, so
both the store and the read resolve to the SAME aggregate pointer (the ArrayRef's
canonical i8*, cached and re-bitcast at each use). The store's memory write is
therefore visible to the read (the read's memory input already threads the store
Assign — memory-SSA phase 2a). No new alias analysis is needed: unwrapping the
`Ref` container to its input is the whole fix.

```perl
# source
use 5.42.0;
my @a = (1, 2, 3);
my $r = \@a;
$r->[0] = 42;
say($a[0]);
```

```behavior
stdout: 42\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%c3   = Constant(3) :Int
%arr  = ArrayRef(%c1, %c2, %c3) :ArrayRef
%ref  = Ref(%arr)
%i0   = Constant(0) :Int
%lval = Subscript(%ref, %i0)
%v42  = Constant(42) :Int
%st   = Assign(%lval, %v42) :Int
%rd   = Subscript(%arr, %i0) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%rd : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R13 element store then read a DIFFERENT index (materialized load)

`$a[0] = 42; $a[1]` stores into slot 0, then reads slot 1 -- an independent
element. The read must be a real load of slot 1 (`2`), NOT the last stored value
(`42`). This is the teeth for the materialize path: a value-substitution read-back
would return `42` here; a real memory load returns `2`.

```perl
# source
use 5.42.0;
my @a = (1, 2, 3);
$a[0] = 42;
say($a[1]);
```

```behavior
stdout: 2\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%c3   = Constant(3) :Int
%arr  = ArrayRef(%c1, %c2, %c3) :ArrayRef
%i0   = Constant(0) :Int
%lval = Subscript(%arr, %i0)
%v42  = Constant(42) :Int
%st   = Assign(%lval, %v42) :Int
%i1   = Constant(1) :Int
%rd   = Subscript(%arr, %i1) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%rd : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R14 element read before a store to the SAME slot (WAR ordering)

`my $x = $a[0]; $a[0] = 99; $x` reads slot 0 (`5`), THEN overwrites it. The read
must observe the value live at its program point (`5`), not the final slot value
(`99`). The read is memory-ordered before the store: it is a distinct load pinned
to the pre-store memory, not a pure data node the scheduler floats past the store
(the read/store WAR hazard, zhi 019f3354, closed by the memory-SSA milestone).

```perl
# source
use 5.42.0;
my @a = (5, 6, 7);
my $x = $a[0];
$a[0] = 99;
say($x);
```

```behavior
stdout: 5\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c5   = Constant(5) :Int
%c6   = Constant(6) :Int
%c7   = Constant(7) :Int
%arr  = ArrayRef(%c5, %c6, %c7) :ArrayRef
%i0   = Constant(0) :Int
%rd   = Subscript(%arr, %i0) :Int
%v99  = Constant(99) :Int
%lval = Subscript(%arr, %i0)
%st   = Assign(%lval, %v99) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%rd : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R15 interleaved read between two stores to the SAME slot (WAR ordering)

`$a[0] = 1; my $x = $a[0]; $a[0] = 2; $x + $a[0]` stores 1, reads (`1`), stores 2,
then reads again (`2`). The mid read must see `1` (its program point) and the
final read `2` -- two distinct loads at distinct memory versions, so
`$x + $a[0]` is `3`, not `4` (both reads collapsing to the final value).

```perl
# source
use 5.42.0;
my @a = (1, 2, 3);
$a[0] = 1;
my $x = $a[0];
$a[0] = 2;
say($x + $a[0]);
```

```behavior
stdout: 3\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%c3   = Constant(3) :Int
%arr  = ArrayRef(%c1, %c2, %c3) :ArrayRef
%i0   = Constant(0) :Int
%rd1  = Subscript(%arr, %i0) :Int
%rd2  = Subscript(%arr, %i0) :Int
%sum  = Add(%rd1, %rd2) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%sum : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R16 a Str array element round-trips through the Slot payload

An aggregate element is one machine word (`%Slot` = {i1 defined, i64 payload}),
but a Str is a (ptr,len) PAIR -- too wide. Storing one boxes it into a heap
`%StrPair` and keeps the ADDRESS in the payload; reading unboxes it back into
ptr+len. Without both halves the read yields the raw address, which prints as a
number: a silent miscompile, not a GAP. The read side must also re-register the
length, or `length()` on the element reads whatever was tracked last.

```perl
# source
use 5.42.0;
my @a = ("hi", "there");
say($a[1]);
```

```behavior
stdout: there\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0   = Constant("hi") :Str
%s1   = Constant("there") :Str
%arr  = ArrayRef(%s0, %s1) :ArrayRef
%i1   = Constant(1) :Int
%rd   = Subscript(%arr, %i1) :Str
%nl = Constant("\n") :Str
%p  = Print(%rd, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R17 length() of a Str array element

The companion to R16: proves the READ side re-registers the string's length
rather than leaving it to whatever the length table last held. `length(there)`
is 5; a stale registration would silently yield the length of another string.

```perl
# source
use 5.42.0;
my @a = ("hi", "there");
say(length($a[1]));
```

```behavior
stdout: 5\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%s0   = Constant("hi") :Str
%s1   = Constant("there") :Str
%arr  = ArrayRef(%s0, %s1) :ArrayRef
%i1   = Constant(1) :Int
%rd   = Subscript(%arr, %i1) :Str
%len  = Length(%rd) :Int
%nl = Constant("\n") :Str
%co_p  = Coerce(%len : Int -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R18 a Num array element round-trips through the Slot payload

A Num is one word wide but is NOT an integer: putting it in the i64 payload is a
`bitcast`, and reading it back is the inverse. Reading a Num payload as an Int
prints the double's bit pattern (2.5 reads as 4612811918334230528) -- the same
silent-miscompile class as R16, in the other direction.

```perl
# source
use 5.42.0;
my @a = (1.5, 2.5);
say($a[1]);
```

```behavior
stdout: 2.5\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%n0   = Constant(1.5) :Num
%n1   = Constant(2.5) :Num
%arr  = ArrayRef(%n0, %n1) :ArrayRef
%i1   = Constant(1) :Int
%rd   = Subscript(%arr, %i1) :Num
%nl = Constant("\n") :Str
%co_p  = Coerce(%rd : Num -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R19 a Str hash VALUE round-trips through the entry payload

`%HashEntry` inlines the same {defined, payload} pair as `%Slot`, so a hash
value is boxed and unboxed by the SAME rule as an array element (R16). This case
pins that the two spellings share one rule rather than diverging -- a hash of
strings was a GAP while an array of strings worked.

```perl
# source
use 5.42.0;
my %h = (k => "val");
say($h{k});
```

```behavior
stdout: val\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%k    = Constant("k") :Str
%v    = Constant("val") :Str
%h    = HashRef(%k, %v) :HashRef
%kk   = Constant("k") :Str
%rd   = Subscript(%h, %kk) :Str
%nl = Constant("\n") :Str
%p  = Print(%rd, %nl)
return %p
control: %start -> %p
L: GREEN
```

## R20 a Num hash value round-trips through the entry payload

The Num half of R19, mirroring R18. Together R16-R20 cover both containers
across both non-Int scalar reprs.

```perl
# source
use 5.42.0;
my %h = (k => 1.5);
say($h{k});
```

```behavior
stdout: 1.5\n
return: Bool:1
context: scalar
```

```ir
%start = Start()
%k    = Constant("k") :Str
%v    = Constant(1.5) :Num
%h    = HashRef(%k, %v) :HashRef
%kk   = Constant("k") :Str
%rd   = Subscript(%h, %kk) :Num
%nl = Constant("\n") :Str
%co_p  = Coerce(%rd : Num -> Str) :Str
%p  = Print(%co_p, %nl)
return %p
control: %start -> %p
L: GREEN
```
