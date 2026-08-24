# Delete `Slot`; thread access provenance; govern it with a MOP

**Date:** 2026-08-24
**Status:** DESIGN SKETCH from the owner, with the load-bearing premise
MEASURED. Not built, not fully specified. Open questions listed at the end.
**Origin:** perigrin —

> I think Slot goes away, it shouldn't exist. Instead when we do
> array/hash/ref access we should thread the provenance information through so
> that the lowering pass can set up the right memory access. That provenance I
> think [should] be stored in the Stamp based on what you said about C2 and
> Graal … we probably could have specific Stamp subclasses for each type of
> value access … I think all of this needs to be governed by a Metaobject
> Protocol because TIE and Magic are both basically alternative/user defined
> versions of *exactly* this MOP.

## The tie/magic premise is CORRECT, and it is the binding constraint

Measured, and this is the fact everything else has to accommodate.

One sub, compiled once:

    my $reader = sub { my $aref = shift; $aref->[0] };
    ops: leavesub lineseq nextstate padsv_store shift null nextstate
         null multideref null

Called with an untied array → `42`. Called with a `Tie::StdArray` → `42`.
**Same optree. The sub was compiled once; its ops cannot depend on which
container it receives.**

Same for magic on a scalar: `sub { my $r = shift; $$r }` is `rv2sv padsv`
whether it dereferences a plain scalar or `$!`.

So **tie and magic are RUNTIME properties of the container, not static
properties of the access site.** perl's own implementation agrees: the check is
in the op's runtime behaviour (`SvTIED_mg`/`SvMAGICAL`), not in op selection.

### The consequence, stated plainly

Access provenance recorded at compile time is a **speculation**, never a proof.
This is exactly the position V8 is in with `ElementsKind`, and V8 pays for it
with **deoptimization** — see `2026-08-24-typed-memory-prior-art.md`, which
records that Chalk cannot pay that price (no interpreter to bail to).

Therefore every provenance-derived narrowing must be either:

- **PROVEN** — the container never escapes and is never tied within the
  compilation unit (a real, checkable property for `my @a = (...)` used
  locally), or
- **GUARDED** — an emitted runtime branch: fast path for the plain container,
  slow path through the MOP. Code size instead of deopt.

A design that assumes provenance is static will miscompile the moment someone
ties a container. Given GAP-not-miscompile, the guard is not optional.

## Why the MOP framing is the right one

The insight is that **tie/magic are not an obstacle to the MOP — they are its
user-facing extension point.** A plain array access and a tied array access are
the same operation dispatched to different implementations:

| access | plain implementation | user-defined implementation |
|---|---|---|
| array element fetch | read the AV's SV slot | `FETCH` on the tie object |
| hash element fetch | hash lookup | `FETCH` |
| element store | write the slot | `STORE` |
| scalar read | read the SV | `get` magic |
| scalar write | write the SV | `set` magic |

If the compiler models access as a MOP dispatch, tie and magic are not special
cases bolted on — they are alternative implementations of methods the protocol
already names. That is a genuinely better factoring than treating them as
exceptions, and it is why the framing is worth taking seriously rather than
treating tie as an edge case to GAP on.

Chalk already HAS a MOP (`lib/Chalk/MOP/`) for classes/methods/fields. Whether
access dispatch belongs in the same MOP or a sibling protocol is an open
question below.

## The access kinds to model

perigrin asked "any other kinds of access we should worry about? Field?" The
inventory, from what the IR actually builds today:

| access | node today | magic/tie applies |
|---|---|---|
| array element | `Subscript` (container=ArrayRef) | tie `@a`, magic |
| hash element | `Subscript` (container=HashRef) | tie `%h`, magic |
| scalar deref | `PostfixDeref` / `rv2sv` | tie `$s`, magic (`$!`, `$0`, ...) |
| **class field** | `FieldAccess` | **YES — measured, see below** |
| package variable | `EntryDef` | magic (`$!`, `%ENV`, `@ARGV`) |
| filehandle | — | tie `*FH` |

### CORRECTION — a class field CAN be tied. Measured.

An earlier revision of this document claimed `feature class` fields are not
tieable, and proposed `FieldAccess` as the safe first implementation because
its provenance would be static. **That was false**, and it was the one place
this document recommended starting, so the error mattered.

    package Shouty { our @ISA = ("Tie::StdScalar");
      sub FETCH { my $s = shift; uc($$s) } }

    class Point {
        field $x :param :reader;
        method tie_it { tie $x, "Shouty"; $x = "quiet"; return }
    }

    before: plain
    after:  QUIET        <- FETCH fires through the :reader

A field is a lexical inside the class body, and `tie` works on it like any
other lexical. The tie is fully live: the generated `:reader` dispatches
through `FETCH`.

**So there is NO access kind with statically guaranteed provenance.** Every one
of them can be tied or magical at runtime, which strengthens rather than
weakens the MOP framing — but removes the "start with the easy case" option.
What remains as a starting point is a PROVABLE case rather than a safe access
KIND: a container that demonstrably never escapes the compilation unit and is
never passed to `tie`.

`%ENV` and `@ARGV` are the opposite extreme — magical by construction, always.

## Where provenance lives: Stamp subclasses

The prior art supports this shape directly
(`2026-08-24-typed-memory-prior-art.md`):

- **Graal** — `Stamp` is an abstract class with subclasses per value kind
  (`IntegerStamp`, `FloatStamp`, `ObjectStamp`, `IllegalStamp`), each carrying
  kind-specific facts. `ObjectStamp` carries `type` + `exactType` + `nonNull` +
  `alwaysNull` + `alwaysArray` — precisely "facts about where this value came
  from and what is known about it".
- **C2** — a stamp is an abstract-interpretation fact ABOUT a value, of which
  the type is one component.

So "specific Stamp subclasses for each type of value access" is exactly Graal's
existing shape, applied to a new axis. The producer's `SoN::IR::Stamp` is
already a class with a single `type` field and a documented intent to grow
(`SoN::IR::Value`'s comment, perl5-son `dc3aea1`: *"a stamp is an
abstract-interpretation fact ABOUT a value ... that machinery is intended"*).

This also retires `Slot` in the right way. `Slot` is currently the ONLY
representation-vocabulary member that is not a type name
(`2026-08-24-there-should-be-no-representation-field.md`, measured: 11 of 12
are lattice types). It exists because a memory cell needs `{defined, payload}`
and nothing carries what the payload IS. If provenance rides in the stamp, the
lowering pass knows the payload type and picks the encoding — and `Slot` is not
a thing the IR needs a name for.

## What this design must still answer

1. **Where does the guard go?** If provenance is a speculation, something must
   check it. On the container at first use? At every access? Hoisted out of
   loops? This is the deopt-replacement and it is undesigned.
2. **What does the slow path cost?** A MOP dispatch to `FETCH` is a real method
   call. For a runtime-free target that is a call through a function pointer to
   emitted code — but the tie object is a blessed Perl object, so the slow path
   may need machinery that does not exist.
3. **Same MOP or a sibling?** `lib/Chalk/MOP/` models classes, methods, fields.
   Access dispatch is a different protocol over different subjects
   (containers, not classes). Sharing the name may or may not mean sharing the
   implementation.
4. **Does the wire carry provenance?** The producer would have to derive it and
   serialize it; today the wire carries a bare stamp string
   (`SoN/Serialize/JSON.pm` emits `$node->stamp->type`). A subclassed stamp
   means a richer wire encoding — and the producer/chalk mirror obligation
   applies.
5. **What is provable, and how?** "This container is never tied in this
   compilation unit" needs escape analysis in general, and Chalk has none. The
   field case does NOT avoid it (see the correction above).

   **But the self-hosting subset does** — measured: 0 `tie` sites and 1
   mechanically-convertible `@ISA` across both repos. So the first
   implementation has a subset where the speculation is trivially sound, and
   the guard can be built afterwards rather than as a prerequisite. What must
   NOT happen is shipping the narrow path with no guard and no check that the
   subset assumption holds — that is a miscompile waiting for the first user
   who ties something.

## "Runtime and compile time are kinda wibbly-wobbly here" — and they are

perigrin, on the above. This is not a quibble; it undercuts the clean
speculation/proof split this document leans on.

Perl does not have a clean phase separation, and the ways it does not are all
live here:

- **`BEGIN` runs at compile time.** A `tie` inside a `BEGIN` block happens
  while later code is still being compiled. So "tied at runtime" is not even
  reliably later than "compiled". Measured:

      package Shouty { BEGIN { our @ISA = ("Tie::StdScalar") }
        sub FETCH { my $s = shift; uc($$s) } }
      our $v = "plain";
      BEGIN { tie $v, "Shouty"; $v = "set in BEGIN"; }
      say "at runtime: $v";        # -> PLAIN

  The `say` prints `PLAIN`, uppercased by `FETCH`: the tie was live before that
  line finished compiling.

  **Getting that repro to work is itself the point.** Two earlier attempts
  failed with `Can't locate object method "TIESCALAR"`, because
  `our @ISA = (...)` is RUNTIME code — at `BEGIN` time the class had no parent
  yet, so the tie could not be installed. Wrapping the `@ISA` assignment in its
  own `BEGIN` fixed it. Whether a tie is even INSTALLABLE at a given moment
  depends on how much of the class hierarchy has executed, which is not a
  question with a phase-shaped answer.

  **SCOPE NARROWING (perigrin): "Chalk's self hosting doesn't need runtime
  `@ISA`."** Correct, and measured — which retires that particular
  wibbliness from the SELF-HOSTING subset even though it stands for Perl
  generally:

  | | chalk `lib/` | producer `lib/` |
  |---|---|---|
  | files using `:isa()` (compile-time) | **111** | 92 on `feature class` |
  | runtime `our @ISA =` | **1** | **0** |
  | `tie` / `Tie::` | **0** | 0 |

  The single `@ISA` site (`Target/LLVM/ElaboratedContext.pm:38`) is a
  plain-package subclass whose parent is a literal, `use`d on the line
  immediately above — no dynamism, and mechanically convertible to `:isa()`.

  So for the self-hosting corpus the class graph IS statically known, and no
  container is tied. That does not make provenance static in general — the
  compiler must still handle Perl — but it means **the first implementation can
  target a subset where the hard case provably does not arise**, which is the
  "start somewhere" option the field-tie correction above appeared to remove.
  It returns, relocated: not a safe access KIND, but a safe compilation
  SUBSET.
- **`use` is `BEGIN require` + `import`.** Loading a module executes arbitrary
  code during compilation, which can tie anything reachable.
- **String eval compiles at runtime** — filed separately
  (`2026-08-23-entereval-shape-and-hintseval.md`); it is the same seam from the
  other direction, and B::SoN's whole position (CHECK time, after compilation,
  before running) sits inside this ambiguity rather than outside it.
- **B::SoN itself runs at CHECK**, between the two. Anything a `BEGIN` did is
  already done and visible; anything the program does later is not. The
  producer sees a WORLD MID-CONSTRUCTION, not a static program.

So the honest framing is not "compile time facts are proven, runtime facts are
speculated". It is: **facts are true as of the moment the producer walks the
optree**, and anything can change afterwards — including during what a naive
reading would call compile time.

That does not sink the design; it sharpens what the guard is for. The guard is
not "in case someone ties this later at runtime" but "in case this container is
not what it was when we looked" — a weaker and more honest claim, and one that
does not depend on a phase distinction Perl does not honour.

It also means an escape analysis answering "is this container ever tied" cannot
be a purely syntactic scan for `tie`. A `use` of a module that ties something
in its own `BEGIN` is invisible to that scan. Whatever provability story this
design ends up with has to be robust to that, or it must not claim proof at
all — only a guard.

## Relationship to the other open threads

- **Depends on** `2026-08-24-there-should-be-no-representation-field.md`: if
  representation is the type after a rewrite, provenance-in-the-stamp is the
  input to that rewrite. The two are the same change seen from opposite ends.
- **Supersedes the framing of** `2026-08-24-thread-use-information-to-lowering.md`:
  that plan threads a use-DEMAND backward. This threads a provenance FACT
  forward. Both feed a lowering pass; they are complementary, not alternatives,
  and TurboFan runs both directions for exactly this reason.
- **Answers the open question in** `2026-08-24-chalk-memory-model-baseline.md`
  §5.3 ("does `Slot` survive?"). Under this design: no.
