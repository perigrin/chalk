# Perl's special hashes are tied containers over chalk's metaobjects

**Origin:** perigrin, 2026-11-15, while retiring Context.pm (step 2 of
`2026-11-14-step-1-ir-methods-printer-ops-split.md`):

- "%SIG and %INC feel like tied metaclass objects."
- "Stashes totally feel like tied metaobjects ... a tied container to the
  Package/Class metaobjects that represent the given package/class."
- "Strict and warnings should be built into the system."
- Part of the current goal. It is the first piece of task #50: tie
  metaclasses belong to "Chalk's implementation of the language" -- compiled
  Perl, not hand-written LLVM.

**Cases it closes** (census ids; `script/t2-case` runs one):

| Case | Program | Needs |
|---|---|---|
| c027 argument-extent:3 | `local $SIG{__WARN__} = sub {}; warn ...` | %SIG |
| c318 loading:4, c319 loading:5, adjacency-12_packages:1 | `require strict` / `require $m` (`"warnings.pm"`); `$INC{...} ? ...` | strict, warnings built in; %INC |
| c316 loading:2, c317 loading:3 | `use POSIX` / `use POSIX ()`; `$INC{"POSIX.pm"}`, `$main::{floor}` | %INC; the stash |
| c346 names:6 | `exists $::{answer}`, `my %stash = %::` | the stash |
| c408 symbol-table:2 | `ref(\*STDOUT)` -> `GLOB` | a glob value |

## The idea

A special hash is an ordinary T2 hash whose **container metaobject** is not
the default one. T2 already works this way for `tie`
(`lib/Chalk/Target/LLVM/Runtime.pm`, "THE CONTAINER PROTOCOL"): every
`%Array` -- an array, or a hash's pairs -- points at a `%Meta`, a 20-slot
vtable plus a datum. The default vtable's entries are the runtime's own
functions. A tie's entries call the datum object's methods by name
(`t2_tie_call`: FETCH, STORE, EXISTS, ...).

So each special hash is a hash **tied, before the program runs, to an object
of a class written in Perl** -- the implementation layer -- whose methods
answer from the metaobject behind it:

| Hash | Tied to | Its methods ask |
|---|---|---|
| `%Foo::` (a stash) | Foo's `Chalk::MOP::Class` instance itself | the Class metaobject: which symbols exist, a glob view of one |
| `%INC` | `Chalk::Impl::INC` | the module registry: the built-ins and what was compiled in |
| `%SIG` | `Chalk::Impl::SIG` | the runtime's handler table: `__WARN__`, `__DIE__` |

**Tie is not the protocol; it is perl's way to supply an implementation of
it.** The container protocol is the operations every container supports
(fetch, store, exists, delete, length, push/pop/shift/unshift, keys...: T2's
20-slot vtable). Tie swaps a container's metaobject for one whose entries
call an object's methods (FETCH, STORE, ... are perl's names for those
operations). The special hashes reuse that mechanism -- a MOP object
implements the protocol -- but they are not "tied" to the program: perl's
`tied %SIG` is false, so `tied` must report false for these too (a test in
each step).

Nothing about `warn`, `die`, `require` or `exists` is special-cased in the
builder. `warn` asks `%SIG` for `__WARN__`; `exists $::{x}` is an EXISTS on
a tied hash; `local $SIG{__WARN__}` is a `local` on a tied hash's element,
which T2 already restores through STORE.

## 1. The implementation layer: Perl classes T2 compiles in

`lib/Chalk/Impl/*.pm` holds Perl classes written in the subset chalk's own
grammar recognizes (postfix deref; `t/bootstrap/style-postfix-deref.t`).
They are compiled by the same path as a program: B::SoN's wire, chalk's
loader, T2. Chalk -- not the program's wire -- owns them:

- Chalk runs B::SoN over `lib/Chalk/Impl/*.pm` once and keeps the graphs
  (rebuilt when a file changes). The program's wire is unchanged.
- The pipeline links an Impl class's graphs into a program that uses the
  hash it backs (a program that never touches `%SIG` gets no `Chalk::Impl::SIG`).
- Start-up: before the program's first statement, each special hash it uses
  is tied to its Impl object (the same TIEHASH path a program's own `tie`
  takes).
- An Impl class is held to the same gates as a program: what T2 cannot lower
  in it is refused by name, at build time.

Which hashes are special is a Perl fact, so it is the IR's, not the target's
(`EntryDef::is_perls_own` exists since step 1a; it grows the ones this plan
backs).

The Perl functor (`2026-11-14-the-perl-target-replaces-deparse.md`) needs
none of this: Perl has these hashes natively.

## 2. %SIG over the handler table

`Chalk::Impl::SIG`: STORE `__WARN__`/`__DIE__` records the handler in the
runtime's handler table; FETCH returns it; DELETE clears it. `warn`: if a
`__WARN__` handler is set, call it with the message (as perl does) instead
of printing. `die`: call a `__DIE__` handler first, then die as before.
Other keys (signal names) are stored and fetched like a plain hash; a
signal itself being raised is refused by name (`kill`, `alarm` stay refused).

*Test first:* c027, and a t2 test of `local $SIG{__WARN__}` restored at
scope exit, `__DIE__` inside an eval, and a handler that dies.

## 3. strict and warnings built in; %INC over the module registry

perigrin: strict and warnings are built into the system. `use`/`require` of
`strict` or `warnings` -- or a run-time `require` of a name that is a
constant naming one -- always succeeds, loads no file, and enters the
module in the registry.

`Chalk::Impl::INC`: EXISTS and boolean FETCH answer from the registry (the
built-ins, plus each module the program compiled in, which the wire already
names). The **value** -- a path -- is perl's file system, not chalk's: a
FETCH whose value is used as anything but a truth is refused by name
(perigrin, 2026-11-15: "refuse by name"), unless the producer recorded the
real path at compile time. STORE and DELETE (a program faking a load) are
refused by name.

*Test first:* c318, c319, adjacency-12_packages:1, c316, c317 (their `%INC`
half).

## 4. One MOP, at compile time and at run time; a stash is a Class, tied

**The principle** (perigrin): "the idea of the MOP is that it's the object
oriented version of metacircularity." The language describes itself with its
own objects, and the description runs: a class is an object; its class is a
metaclass; and the metaclass is itself an instance of a class -- `Class` is
an instance of `Class` (Smalltalk, CLOS, Moose's `Class::MOP::Class->meta`).
For chalk: `Chalk::MOP::Class` is written in chalk-Perl and compiled by
chalk; every package's description is one of its instances, **its own
included** (the knot is tied once, at start-up); the compiler and the
running program use the same objects. The special hashes are this one MOP
seen through the container protocol. A test of step 3 that means something:
`Chalk::MOP::Class`'s own description is a `Chalk::MOP::Class` that
describes `Chalk::MOP::Class` -- at compile time and at run time.

perigrin: "I'm not convinced there is a distinction between a runtime and
compile time MOP ... there is just a MOP that exists at both run time and
compile time." As in perl: one symbol table, built by `use` and BEGIN,
used by the running program.

So there is no second class. The class is **`Chalk::MOP::Class`** (with
`Chalk::MOP::Method`, `Sub`, `Field`), the one chalk's compiler builds and
fills while it loads a program. It is part of the implementation layer: T2
compiles `lib/Chalk/MOP/*.pm` into a program like any class, and the
instances the compiler built carry across into the program's run. Method
dispatch (`t2_class_of` + lookup), `can`, `isa`, `@ISA` and the stash view
call its methods (`find_method` depth first through its parents as perl
does, `superclasses`, `can`, `isa`, the symbol questions below).

Today's bare-hash stashes in `@t2_stashes` (`Builder/Calls.pm`, `make_mop`)
are a stand-in for these instances and go.

**The phase boundary** is the real design work: which of a
`Chalk::MOP::Class`'s state the program carries into its run, and how a
method is held once compiled (a code value, alongside or instead of its
graph). Start with the smallest set the cases need -- name, parents, methods
and subs by name (as code values), fields, the package's variables -- and
see. The rest (graphs, the node factory, bindings) is **not** ruled out of
the run (perigrin: "I don't know that those things need to go away"): a
string eval or recompiling a method at run time may want them, and adding
them later is the class saying so, not a second class. This is a
behaviour-preserving move first: the ratchet and the census are unchanged.

The stash is then **that instance, seen as a hash**: `%Foo::` is a hash
tied to Foo's `Chalk::MOP::Class` (the class implements the tie interface).
Its symbols are the package's subs and its variables (known at compile
time: T2's package arrays, hashes and scalars are globals named for them):

- EXISTS `name` -> the package has a sub or a variable `name` (and nested
  packages, `Bar::`).
- FETCH `name` -> a **glob** for it: a value whose `ref \` is `GLOB`, whose
  slots are the sub and the variables of that name. (This is c408's glob
  value too: `\*STDOUT` is a reference to main's STDOUT glob.)
- Keys, values, `%::` copied whole -> the package's symbols, as globs.
- STORE (`*Foo::bar = sub {...}`) and DELETE (`delete $::{x}`) change the MOP
  at run time: refused by name until chalk has a mutable run-time MOP. That
  is the next piece of #50, not this goal.

What `use POSIX` imported is already in main's Package metaobject (the
imported subs), so c316/c317's `$main::{floor}` needs no wire change.

*Test first:* c346, c316, c317 (their stash half), c408.

## Order

1. The implementation layer's plumbing (compile `lib/Chalk/Impl`, link,
   tie at start-up) with the smallest class first: `Chalk::Impl::SIG`
   (c027).
2. strict/warnings built in and `Chalk::Impl::INC` (c318, c319,
   adjacency-12, the %INC half of c316/c317).
3. One MOP: `Chalk::MOP::Class` compiled in, its instances carried across
   the phase boundary; dispatch, `can`, `isa`, `@ISA` through them; the
   bare-hash stashes go (behaviour-preserving -- ratchet and census
   unchanged).
4. Globs, then the stash as that Class instance tied as a hash (c408, c346,
   c316, c317).

Each step: its cases added to `t/bootstrap/ir/t2-census-cases.t` first (red),
then green; full verify; never a silent wrong answer.
