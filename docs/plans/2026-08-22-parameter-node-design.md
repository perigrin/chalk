# A `Parameter` node: every sub has a signature

**Date:** 2026-08-22
**Status:** DESIGNED, not built. Design settled with perigrin; two open calls
marked at the end.
**Inputs:** `2026-08-22-identity-kind-and-argssource-shape.md` (the measurement),
`2026-08-22-parameters-identity-valueness-prior-art.md` (verified prior art),
`2026-08-22-click-reply-son-vs-cfg.md` (why staying sea-of-nodes is sound).

---

## The problem, measured

Chalk has **no parameter representation**. It has three unrelated accidental
encodings of the same concept:

    sub f { my ($a,$b) = @_ }   ->  PadAccess(targ=1,$a)  PadAccess(targ=2,$b)   untyped
    sub g { $_[0] * 2 }         ->  Subscript(ArgsSource, Const(0), MemStart)     untyped
    sub h { my $s = shift }     ->  sequential consumption, a third shape
    method m($k)                ->  PadAccess(targ=2,$k)                          untyped

Nothing hangs off `Start`. The declared parameter list of `method m($k)` --
which perl knows structurally -- is discarded at three points: no parameter
node, no `params` on the wire's method record, and the invocant never appears.

Corpus/lib measurement of which idioms matter: in `lib/`, `method`/`field`
declarations outnumber all `sub`-with-arguments forms by ~4.5x (1205 vs 266).
In the corpus, `shift` (30) dominates `my(...)=@_` (7) and signatures (2).

## The rule: EVERY SUB HAS A SIGNATURE

perigrin: *we can do signature only and assume that `sub f {}` is exactly
equivalent to `sub f(@_)`.*

That dissolves the arity problem instead of deferring it. There is ONE
representation, not a declared-params path plus an aggregate fallback.

**But `sub f {}` and `sub f() {}` are exactly different** (perigrin) --
signature-less is the most permissive declaration, empty-signature the most
restrictive. Conflating them would invert the meaning of the strictest form:

| source | meaning | IR |
|---|---|---|
| `sub f($a,$b)` | two mandatory scalars | `Parameter(0)`, `Parameter(1)` |
| `sub f(@x)` | slurpy array | `Parameter(0) :Array` |
| `sub f(%h)` | slurpy hash | `Parameter(0) :Hash` |
| `sub f($a,@r)` | one scalar + slurpy | `Parameter(0)`, `Parameter(1) :Array` |
| `sub f {}` | implicit `sub f(@_)` | `Parameter(0) :Array` |
| `sub f()` | **arity zero, enforced** | *no parameters* |

Verified: `perl -e 'sub empty() {} empty(1)'` dies with "Too many arguments for
subroutine 'main::empty' (got 1; expected 0)".

## THE OPTREE ALREADY CARRIES ALL OF IT

Measured with `B::Concise`. The producer is not inferring anything -- it is
DISCARDING a signature perl already parsed, one op above where it currently
looks:

    sub ary(@x)        argcheck(0,0,@)   argelem(0)[@x] v/AV
    sub hsh(%h)        argcheck(0,0,%)   argelem(0)[%h] v/HV
    sub mix($a,@r)     argcheck(1,0,@)   argelem(0)[$a] v/SV
                                         argelem(1)[@r] v/AV
    sub opt($a,$b=9)   argcheck(2,1)     argelem(0)[$a] v/SV
                                         argdefelem(->7)[1] + argelem(1)[$b]
    sub empty()        argcheck(0,0)     (no argelem)
    sub none           (NO argcheck at all)

| what the model needs | where it comes from |
|---|---|
| mandatory / optional counts | `argcheck` operands 1 and 2 |
| slurpy, and its kind | `argcheck` operand 3: `@` or `%`, ABSENT if none |
| per-parameter type | `argelem` flags: `SV` scalar, `AV` Array, `HV` Hash |
| positional index | `argelem(N)` |
| defaults | `argdefelem` guarding the `argelem` |
| signature-less | no `argcheck` node |
| arity zero | `argcheck(0,0)`, no third operand, no `argelem` |

**The third operand is load-bearing.** `sub ary(@x)` is `argcheck(0,0,@)` --
reading only the first two operands says "takes no arguments", inverting it.

Types come from the SIGIL, per parameter. That is the same principle that fixed
`EntryDef` earlier in this session, where `$_` and `@_` hash-consed into ONE
node because identity was keyed on name without the sigil. Second appearance of
the same lesson.

## The node

Modelled on TurboFan's `Parameter`, verified verbatim in `common-operator.cc`:

    IrOpcode::kParameter, Operator::kPure,     // opcode
    "Parameter",                               // name
    1, 0, 0, 1, 0, 0,                          // counts
    ParameterInfo(index, debug_name));

- **PURE.** Both V8 pipelines agree (`Operator::kPure` / `OpEffects()`). A
  parameter read floats, CSEs, hoists. Chalk's `$_[0]` currently takes a
  `MemStart` input and cannot.
- **Hash-consed by index.** `hash_value(ParameterInfo p) { return p.index(); }`
  -- two reads of parameter 0 are ONE node. A parameter is a value, not an event.
- **Individually typed**, from its sigil.

`ArgsSource` RETIRES. It becomes the slurpy parameter, so `$_[0]` is
`Subscript(Parameter(0), 0)` -- and its memory input is then CORRECT, because
indexing an array genuinely is a load. What was wrong was never the memory
edge; it was that the indexed thing had no type and no identity as a parameter.

## Aliasing: a property of the BINDING, not the type or the value

perigrin first proposed an alias that "takes the address of what it's
aliasing", then withdrew it. Withdrawing was right, and the reason generalises:

- An address is a REPRESENTATION, not a type. `$x` in `my \$x = $y` has `$y`'s
  type; being stored as a pointer is lowering. Putting it in the type recreates
  the two-type-systems-in-one-namespace defect from the seams doc.
- An alias is not a property of the VALUE but of the BINDING -- two names
  reaching one cell. SSA values do not have addresses; that is what makes them
  values.

`@_` aliases the caller's lvalues (`$_[0] = 5` modifies the caller's variable);
a signature slurpy `@x` copies. Same type, different binding.

**Chalk has NO alias analysis, and this is structural, not a TODO.** Measured:
`MemStart` is a bare token -- no inputs, no locations, no partitioning. The only
"alias" handling is `_unwrap_ref`, a SYNTACTIC unwrap resolving `$r->[0]` to
its container at construction. `@_` is not in that class: the caller's lvalues
are not visible from the callee's graph.

So:

- **reads through an alias: fine**, a load is a load;
- **writes through an alias: GAP**, and not "until the memory model lands" --
  there is no memory model to extend. Closing it needs either a real alias
  analysis or a calling convention passing references explicitly.

This preserves current behavior. Verified today: `sub bump { $_[0] = $_[0]+10 }`
already GAPs (for an unrelated reason -- effects in an inlined callee). The
hazard for this work is not losing a working case; it is CREATING a miscompile
where a GAP stands.

## Slices

**1. Producer records the signature.** `params => []` stops being a placeholder
and starts carrying `{index, name, sigil, kind}` plus mandatory/optional counts
and the slurpy marker, read from `argcheck`/`argelem`. Distinguishes all three
of signature / empty-signature / signature-less. Changes no lowering --
verifiable on its own, same shape as the `return_type` work that opened this
session.

**2. `Parameter(N)` node**, pure, hash-consed by index, typed from the sigil.
Minted from `argelem`. Replaces `PadAccess` for declared parameters.

**3. Invocant** at a reserved index for methods.

**4. Slurpy `Parameter`** replaces `ArgsSource`; `$_[0]` becomes a subscript of
it. Writes through an aliasing slurpy continue to GAP.

**REGRESSION SURFACE, flagged:** slice 2 changes node identity on a path every
method case exercises (`method scale($k)` currently emits
`Multiply(FieldAccess, PadAccess)`). This is the first change in this arc with
real blast radius -- run the corpus gate before and after, not just a unit test.

## OPEN -- perigrin's calls

1. **Invocant index.** TurboFan reserves NEGATIVE indices
   (`kMinIndex = Linkage::kJSCallClosureParamIndex`) for closure/context/
   receiver, so `$self` would be `Parameter(-1)` and user params start at 0.
   C2 instead starts user params at `TypeFunc::Parms` with slots 0-4 reserved
   for Control/I_O/Memory/FramePtr/ReturnAdr. Both are attested; they differ in
   whether "parameter 0" means the invocant or the first user argument.

2. **Optional parameters.** `argdefelem` makes an optional parameter
   structurally distinct from a mandatory one, not merely a count. Whether the
   default expression becomes part of the `Parameter` node or a separate
   guarded def is undecided.
