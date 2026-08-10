# Effect-chain followups (2026-08-03)

Deferred work and measured defects surfaced by the `effect-chain-fix` milestone
(plan: `2026-08-03-effect-architecture-subtraction.md`). Each entry has a
measurement behind it. Nothing here was fixed by that milestone — these are
filed so they are findable on their own rather than buried in a plan that will
be closed out.

Extended 2026-08-08 by the `bare-block-classification` milestone (Part A3, Part D).

---

# Part A — gate and harness defects

**THREE GATE BLIND SPOTS, found in two consecutive milestones.** Individually small,
collectively load-bearing: the corpus gate's green number is weaker than it looks in
three independent ways.

| # | site | what it cannot see |
|---|---|---|
| A1 | `MdtestCorpus.pm:1146-1159` | operands of **control-reachable** nodes |
| A2 | `Mode1Runner.pm:167` | **exit status** — any nonzero lli exit becomes a skip |
| A3 | `son-corpus-wide.t:133-139` | GAP-declared cases — `pass()`ed **without running** |

## A1: the shape leg does not check operands of CONTROL-REACHABLE nodes

Not an `If` quirk — the first framing was too narrow. `_rooted_match`
(`t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm:1146-1159`) starts at
`Return.inputs[0]` and descends **value operands only**. Any node reachable only
through control therefore gets a presence check and **never an operand check**.

Measured with direct probes against a real graph:

```
spec identical to the real graph      -> PASS
spec with a WRONG If condition        -> PASS   (should fail)
spec with a WRONG branch-arm store    -> PASS   (should fail)
```

Consequence: a corpus ir-block can encode the wrong condition or the wrong
arm-store value and stay green. Stated precisely: the shape leg does not check
the operands of control-reachable nodes, only their presence. **This is the prerequisite for the `If`/`Loop`
control normalization**, which the milestone deliberately CUT precisely because
nothing could validate it — ~120 positional construction sites across ~26 files
would have been edited under a gate blind to the change.

## A2: there is no exit-code oracle anywhere

`t/lib/Chalk/CodeGen/Harness/Mode1Runner.pm:167` turns ANY nonzero lli exit into
a skip and never compares `$?`:

```perl
return (undef, "lli exited $exit: $out", $g) if $exit != 0;
```

This is why F1's dropped `print` was invisible to the harness for so long, why
corpus T2b is GAP-declared with a prose note that the harness cannot assert an
abort, and why this milestone's die-in-arm case can only ever be a marker rather
than a regression guard. The two die miscompiles (F1, F2) had to be verified by
hand against perl, outside the harness.

Adding the comparison is small but explicitly **NOT free** — nobody has measured
how many currently-green cases would flip when a nonzero exit stops being a skip.
Measure that first.

## A3: `Assign` is not universally control-pinned by the producer

Found while defining the control-chain invariant's op set. `Assign` is pinned at
8 of 9 producer build sites; the exception is the generic list-assign fallback
(`my ($a,$b) = LIST`) at `~/dev/perl5-son/lib/SoN/FromOptree.pm:2067`, which has
no `set_control_in` call.

Zero corpus cases exercise that shape, so the new TypedInvariant control-chain
leg is green — but the gap is real, and the invariant's "Assign is always pinned"
premise is true only for corpus-exercised shapes. Adding a `my ($a,$b) = ...`
corpus case would fail the invariant leg, which would be **correct behavior**:
it is a genuinely unpinned effect.

---

# Part B — M5 seed sites (2 of 3 remaining)

## Context

The M5 "trailing void statement-effect rides Return.inputs[1..]" encoding
existed to work around a pre-R1.0 producer convention: a void method call
(`$c->inc;`) was not the return value, so the loader kept it as an extra
Return input rather than demoting it to `control_in`.

perl5-son's R1.0 Call-pin (commit 40d8f8b,
"fix(fromoptree): pin control_in unconditionally so a non-void Call is never
dropped or reordered (F3/F4)") makes this encoding unproducible at the
source: every Call — void or not — now pins `control_in` unconditionally.
`SoN::FromOptree::_build_single_exit` builds `Return.inputs` as always
exactly `[value]`; see the comment there ("control_in is never a data input,
so a Return's inputs is always exactly [value] regardless of what kind of
node control is").

There were three LLVM-side sites carrying the M5
`Return.inputs[1..]`-as-extra-seed encoding. One is deleted
(`lib/Chalk/Target/LLVM.pm`'s `_process_control_chain` seed list, see commit
paired with this plan). The other two are **filed here, not touched**, per
the task's scope fence:

## Open site 1: `lib/Chalk/IR/Serialize/JSON.pm:994-1002` (`_control_chain_nodes`)

This sub is in the fenced-subs list per `t/bootstrap/mop-fence-audit.t:32` —
deleting or editing it trips the fence audit and needs its own sign-off
before touching. The seed-from-`inputs[1..]` block (lines 986-1002) is the
same M5 pattern as the deleted LLVM.pm site, now provably dead for the same
unproducible-at-source reason. Needs a decision on how to handle a fenced
sub: unfence-then-edit, or a separate fence-aware deletion path.

## Open site 2: `lib/Chalk/Target/LLVM/Context.pm:4372-4378` (trailing-effects GAP guard)

The direct-call inliner reads `$returns[0]->inputs->[-1]` as the callee's
return value (line 4371) and then, per the comment at 4385-4389, treats
`Return.inputs[1..]` as a possible trailing void statement-effect requiring
its own GAP guard. Same unproducible-at-source argument applies. Not
touched here — needs its own verification pass (the inliner path has more
surrounding logic than the LLVM.pm seed list did; Slice B's straight-line
effect chain work is layered on top of it) before deciding whether to
delete the guard outright or simplify it.

## Do not do yet

Neither open site should be treated as "obviously safe to delete" without
its own verification pass — the same rigor applied to the LLVM.pm site
(confirm the encoding is unproducible at the current producer HEAD, not
just "corpus stays green") applies to both.

---

# Part C — a committed plan claim that was false

`docs/plans/2026-07-23-slice-b-inliner-effect-ordering.md:259` claimed the silent
effect-drop miscompile class was CLOSED. That is true only as scoped to the
**callee**: Commit 1's guard inspects the callee's attachment paths, while the
**caller-side** path was unguarded.

F4 reproduced live on HEAD with no GAP — `sub f { print "x"; 2 } my $r = f(); 3`
printed nothing where perl prints `x`, because the producer DCE'd the unpinned
Call and chalk never saw it. The class was not closed; one side of it was.

That line has been re-scoped in place (not deleted) to say what is actually
closed, pointing at F4 and at the R1.0 Call-pin that finally closed the caller
side.

**The general lesson, worth more than the instance:** a guard that inspects one
side of a boundary does not close a class. "CLOSED" in a plan should name the
side it closes, or it will be read as the whole thing — including by the person
who wrote it.

---

# Part D — from `bare-block-classification` (2026-08-08)

## D1: GAP-declared corpus cases `pass()` WITHOUT running their source

`t/bootstrap/corpus/son-corpus-wide.t:133-139`:

```perl
if ($verdict eq 'GAP') { $tally{gap_declared}++; pass("$label: corpus-declared GAP (skipped)"); next; }
```

This is blind spot **A3** above. Two live consequences:

1. **GAP-message drift is undetectable.** Corpus **T4c**
   (`t/corpus/mdtest/control-flow.md:1412`) declares
   `"last not at the head of a loop body"` while the producer actually emits
   `"loop without a lowerable condition"`. Measured. Nothing notices.
2. **A GAP-declared case that has silently STARTED WORKING is undetectable.** It keeps
   passing as a declared gap forever and `gap_declared` never falls.

Consequence #2 is not hypothetical — it fired during this very milestone. Two cases
were drafted as `L: GAP` from the plan's wording; measuring the real producer output
showed they **already lowered and executed correctly**, and they were corrected to GREEN
before commit. Had they shipped as GAP they would have pinned nothing, forever, while
reading as coverage.

**Fix shape (not done here):** run a GAP-declared case's source anyway; assert it still
GAPs, and assert the message matches the declared one. That converts both silent
failures into loud ones. Cost is one corpus-gate run per GAP case (21 today).

## D2: shape 2 — headless loop whose only exit is a non-first-statement `last if`

`t/cmd/for.t`. `_walk_loop_body:3113-3116` gates head-of-body hoisting on
`$stmt_count == 1`; with a statement before the `last if`, the mid-body handler
(`:3162-3246`) builds an `If` and a break-proj but **never assigns `$exit_proj`**, so
the loop GAPs with "loop without a lowerable condition".

Independent of the bare-block fix — it is a REAL loop (`nextop = unstack`), so the
classification change does not touch it (verified: blocker unchanged before and after).

**Ready-made RED already exists: corpus T4c.** Note the interaction with D1 — T4c is
GAP-declared, so it is `pass()`ed without running. If shape 2 were fixed tomorrow,
nothing would notice.

---

# Part E — from the types/fetches architecture note (2026-08-10)

## E1: LIVE SILENT MISCOMPILE — a nested rvalue deref answers wrong with no GAP

**Severity: violates GAP-not-miscompile.** Wrong answer, no GAP, no diagnostic, exit 0.

Found while grounding a type-model discussion, not by a gate. Nothing in `docs/`,
`lib/` or `t/` mentions autovivification, so this was undocumented.

> **[REFRAMED 2026-08-10, perigrin.]** This entry was first titled *"...does not
> autovivify"*, which encodes the wrong requirement. **Chalk is not a port of perl's
> implementation.** It is a reimplementation of perl's *semantics where possible*, over a
> **subset**, using modern compiler theory, targeting an optimized binary. So "perl
> autovivifies at runtime, therefore chalk must" is not a valid inference, and neither is
> "perl mutates in place, therefore chalk must."
>
> **The defect is the SILENT WRONG ANSWER, not the absence of autovivification.** Those
> are different bugs, and separating them adds a resolution that was missing from every
> earlier draft below: **declare autovivification out of subset and GAP loudly.** That is
> cheap, honest, and satisfies the project invariant. Whether autoviv is *in* the subset
> is a scope decision, not a correctness one — but a construct outside the subset must
> refuse, not guess.

### Repro (measured 2026-08-10, stock perl 5.42.0, no pragmas)

```perl
my $r = [10, 20];
my $v = $r->[5][0];
print scalar(@$r), "\n";
```

| case | perl | chalk (lli) | verdict |
|---|---|---|---|
| `$r->[5][0]` literal index | **6** | **2** | **FAIL** |
| `$r->[$i][0]`, `$i = 5` dynamic index | **6** | **2** | **FAIL** |
| same, observed through an alias `my $s = $r` | **6** | **2** | **FAIL** |
| `$r->[0][1]` over `[[1,2],[3,4]]` in-bounds | 2 | 2 | PASS |
| flat `$r->[$i]` OOB, `defined()` consumer | undef | undef | PASS |

Nested subscript itself works, and a flat OOB read works. The defect is specifically
**fetch through a MISSING intermediate**.

The hash form (`my $h = {a=>1}; my $v = $h->{zz}{qq}; print scalar(keys %$h)`) GAPs
earlier on `keys` → "cannot lower op=Call", so it is **untested, not clean**.

### WHERE the fix belongs: the import boundary vs downstream

**[MODEL, perigrin 2026-08-10]** *"B::SoN is closer to Perl's implementation … you're
definitely pushing in the wrong direction when you decide that Perl's current
implementation is always correct."*

**[MODEL, perigrin 2026-08-10 — three layers, not two authorities]**

> *"Perl's Optree tells us **what IR to create** … Perl's semantics tell **how our IR
> should behave** (within some reason) … none of that defines **how our IR implements**
> that behavior."*

| layer | what perl supplies | what it constrains |
|---|---|---|
| **1. optree** | the **structure to build** | a foreign-function import boundary. `OPpDEREF`, `multideref`'s aux chain, `OPf_MOD` are facts; failing to read them is a **decoding bug**. |
| **2. semantics** | the **behaviour to exhibit**, *within some reason* | observable output. "Within some reason" is the **subset** clause — some behaviour may be legitimately out of scope, but then it must GAP, not guess. |
| **3. implementation** | **nothing** | **Chalk. This is the entire project.** |

**[MODEL, perigrin]** *"Chalk **is** L3 … that's where Chalk lives, it's what defines
Chalk. It's what we are implementing."* So importing perl's implementation into an L3
decision is not a small reasoning slip — **if perl's implementation decides L3, there is
no Chalk, only a port.**

**Layer 3 is the one this investigation kept violating.** *"Perl mutates the array in
place, therefore `Coerce` needs a memory edge"* imported perl's implementation as ours.
So did the original title of this entry (*"does not autovivify"*), which promoted a
mechanism to a requirement.

**The payoff of separating them:** the choice among coercion / static pre-sizing /
memory-SSA threading / in-place write is decided on **analyzability and optimization**
grounds, not fidelity grounds. That is the same test recorded in the DECISION RULE below,
and it only becomes available once layer 3 is recognised as free.

**So the fix splits by layer.** L1 — the producer must *report* that this access is in
deref context. L2 — the IR must behave as though the array were extended, or GAP. L3 —
how, is open, and is chosen for what it lets the optimizer do.

**Today chalk cannot decide anything at L3, because L1 never told it.** The outer
`Subscript` arrives **pure**. The information is lost at the import boundary, not
mishandled after it.

**But do not read that as "this is only a producer bug."** The L1 fix is the *enabler*;
the deliverable is the L3 design — coercion, static pre-sizing, DCE, escape analysis —
because **L3 is what Chalk is**. Fixing L1 and then reproducing perl's runtime at L3 would
close the miscompile and build nothing.

### Mechanism (measured, not inferred)

Two earlier guesses were wrong and are recorded so nobody re-treads them: it is NOT the
`padsv` OPpDEREF site (`FromOptree.pm:1420`), and multideref is NOT collapsed to a
single Subscript despite `OpMap.pm:234` declaring arity 1. `B::Concise` shows one
`multideref($r->[5][0])` op, and it decodes into TWO Subscripts correctly.

**[UNKNOWN — do not guess, and do not treat the above as a diagnosis]** *Where* that
two-level decode happens is **not established**. There is no `multideref` decoder in the
producer: no `aux_list` call for it (`aux_list` appears only for `multiconcat`,
`FromOptree.pm:1883`), no expansion pass, and `OpMap.pm:234` declares it a single
`Subscript`. The `Subscript` builder at `FromOptree.pm:1681` is on the `aelem`/`helem`
path. Yet the emitted IR contains two correctly-nested Subscripts.

**Find that path before proposing a producer fix.** Three mechanism guesses in this
investigation were already wrong; the decode site is the fourth open question and must be
*located*, not inferred. Everything above it — the repro, the reprs, the IR shape — is
measured and stands on its own.

The producer IR for the failing case:

```
3  ArrayRef  inputs=[1,2]        # [10,20]
5  Subscript inputs=[3,4]        # $r->[5]  <-- PURE: no memory input, no store
8  Subscript inputs=[5,6,7]      # ->[0]    (7 = MemStart)
9  Length    inputs=[3]          # scalar(@$r) reads the ORIGINAL node 3
```

**Node 5 is a pure read.** Perl requires it to autovivify: allocate an arrayref, store it
into `$r->[5]`, extending `@$r` to 6. That store is absent from the IR entirely, so
`Length(3)` reads the unmodified aggregate and answers 2.

Chalk has silently implemented `no autovivification` semantics. (That is a CPAN user
pragma, never in core — `Module::CoreList->first_release('autovivification')` is undef —
so it cannot be leaned on as an excuse; the miscompile is against DEFAULT perl.)

### Why this is a type-model finding as well as a bug

The same syntactic read has two types AND two effect classes, chosen by its CONSUMER:

| context | type | effect |
|---|---|---|
| `my $v = $r->[5]` (rvalue leaf) | `Maybe[Int]` | none |
| `$r->[5][0]` (intermediate in a deref chain) | `ArrayRef`, guaranteed — never Nothing | **a store** |

So "is this fetch `Maybe[T]`?" cannot be answered at the fetch site. This is exactly the
architecture note's §4 (fetches parameterised by context) and §5 (borrowing rules).

> **[RETRACTED 2026-08-10.]** This section originally concluded that the finding "adds a
> third axis to the `Maybe[T]` design: **does this fetch CREATE?** — an effect
> classification, not a type parameter." **That is wrong.** The difference is one of
> *requirement*, not of node kind, and the coercion rule already covers it. See **THE
> MODEL** below. The table above is still accurate; only the conclusion drawn from it was.


### The compiler ALREADY PROVES the miss and then discards the proof

**[MEASURED 2026-08-10]** Loading the failing case through chalk's own loader:

```
ArrayRef#2                     repr=ArrayRef
Subscript(ArrayRef#2, 5)       repr=Slot      <-- _static_miss FIRED
Subscript(that, 0, MemStart)   repr=UNDEF
```

`_static_miss` (`JSON.pm:1192`) counts the literal's elements and **proves** index 5 is
out of bounds. It then types the read `Slot` — which is correct for a *leaf* rvalue read
and wrong for this one, because the consumer is another `Subscript`. In a deref chain
"provably Nothing" means **"this read is a store"**: it autovivifies, and its result is
guaranteed `ArrayRef`, never Nothing.

**The proof is on the right node at the right time and the consumer ignores it.** This is
not a missing analysis; it is an analysis whose result is used in exactly one context and
dropped in the other.

### THE MODEL: autovivification IS a coercion

**[MODEL, perigrin 2026-08-10.]** This supersedes an earlier framing in this file that
offered two fixes — "emit the autovivifying store" (as a special case) or "diagnose it".
**Neither is the answer.** The coercion rule already covers this, and the store is its
*lowering*.

The access states a **requirement**; the operand does not satisfy it; a `Coerce` is
inserted unconditionally, keyed only on the requirement. That is exactly §3 of
`docs/architecture/2026-08-09-types-fetches-and-contexts.md`, with no new mechanism.

`$r->[5][0]` is **two** coercions:

| | operand | requirement | coercion |
|---|---|---|---|
| outer | `Array[Int,2]` | `Array[_, ≥6]` | extend the array |
| inner | `Undef` (the new slot) | `ArrayRef` | allocate an empty arrayref |

`Coerce(Undef → ArrayRef)` — "make an empty arrayref" — is precisely what perl does.

**This dissolves the "does this fetch CREATE?" axis** proposed in the section above. There
is no effect classification to add: the *fetch* stays pure, and the requirement-driven
`Coerce` carries the work. The leaf-vs-chain split is then just a difference of
**requirement**, not of node kind — `my $v = $r->[5]` requires nothing of `$r`, so no
coercion fires and the result is honestly `Maybe[Int]`.

**And `Maybe[T]` stops being special.** If arrays can be extended with holes then every
Perl array is `Array[Maybe[T]]` — holes are legal Perl. Which makes
`%Slot = { i1 defined, i64 payload }` **the correct representation of `Maybe[T]`**. The
backend built the right thing; the lattice never named it.

### How the extension is realised — UNDECIDED, three candidates

> **[CORRECTED 2026-08-10, perigrin.]** This section previously asserted that an
> array-extending coercion "mutates a heap object" and concluded that `Coerce` must gain a
> memory edge. **Neither followed from the evidence.** The measurement below is a fact
> about *perl's observable behaviour*; it does not constrain chalk's IR structure, and
> in-place mutation is not the only implementation. Recorded as the error it was: a
> behavioural measurement used to force an IR design.

**[MEASURED 2026-08-10]** The semantic requirement, which any implementation must meet —
the extension is observable through an alias (third FAIL variant of this bug):

```perl
my $r = [10, 20];
my $s = $r;
my $v = $r->[5][0];
print scalar(@$s), "\n";      # perl: 6   chalk: 2   FAIL
```

### DECISION RULE and verdict

**[DECISION, perigrin 2026-08-10]** *"If we can replicate autovivification using SSA and
coercion and provide tools to better analyze and optimize that behavior then we will do
that … if we can't then we won't."*

So this is a **feasibility** question, not a scope preference. **Verdict: we can.**

**[CODE] The one thing feasibility turns on is aliasing**, and it is already solved.
`docs/plans/2026-07-05-memory-ssa-element-reads.md:4` — *"approved model: full
memory-value + MemPhi, **one global memory**"*. With a single global memory value every
memory operation is ordered against every other, so an extension through `$r` is
**necessarily** observed by a later read through `$s`. Conservative on ordering precision,
**sound on aliasing by construction, with no alias analysis required.**

### One model, one optimization, one lowering — not three implementations

An earlier draft of this section listed three "implementations" to choose between. They
are not alternatives; they are three layers of the same answer:

| layer | what it is |
|---|---|
| **model** | `Coerce` threaded on the global memory chain — memory in, memory out. The **same shape** `Assign`/element-store already has. |
| **optimization** | **static pre-sizing.** When the index is statically known — which `_static_miss` **already proves** — fold the extension back to the allocation site and the runtime extension disappears. This is what the optimizer does *to* the coercion, not a rival to it. |
| **lowering** | in-place write. A backend decision, invisible to the IR. |

### This is the "tools to analyze and optimize" half, and it is the point

Perl's autovivification is a runtime behaviour **invisible to any optimizer**. A `Coerce`
node is not. Putting it in the IR buys, with no new machinery:

- **DCE** removes the extension when the array is dead
- **escape analysis** — if no alias is live, the extension is unobservable and goes away
- **CSE / hoisting / sinking** apply to it like any other node
- **the static fold above**, which is just constant propagation reaching a coercion

That is strictly more analyzable than what perl does, which is the bar this project sets.

### Cost, stated honestly

`Coerce` is pure today (`sitofp`, `zext`, `icmp`) and has no memory input, while
`Subscript` and `Assign` do. Giving it one is a real change — but it is an **extension of
shipped machinery into the same shape**, not a new mechanism. An earlier draft called this
"a new thing in this IR"; that overstated it.

**GAP-and-declare-out-of-subset is the fallback, and is not needed.** It stays recorded
only as the answer had feasibility gone the other way.

**What IS established:** every `Coerce` today is pure — `sitofp`, `zext`, `icmp`
(`_lower_coerce`, `Target/LLVM/Context.pm:1019+`) — and `Coerce` has no memory input
(`Coerce.pm`: `from_repr`, `to_repr`, `inputs`; emitted IR confirms `Coerce inputs=[node]`)
while `Subscript` takes one. **What is NOT established:** that it needs one.

### Diagnostics: still available, no longer the fix

**[MEASURED] Perl itself does NOT warn** — `perl -w -Mstrict` prints `6` silently. So
chalk cannot *reject* this; it is legal Perl. chalk holds the literal and perl does not,
so a warning is available to chalk that is not available to perl:

> *"index 5 is out of bounds for the 2-element array literal declared at line 1 — this
> read will extend it to 6 elements"*

Worth having. **Not** a substitute for compiling it correctly.

### The type-design catch: this needs a SIZED type

`_static_miss` proves the miss by **counting the `ArrayRef` node's inputs** — a structural
fact about the literal, not a type. The architecture note's §7 `Array[T]` **cannot express
"length 2"**, so folding this special case into the type system needs *refinement* types
(`Array[Int, 2]`), not merely parameterised ones.

That is the note's thesis running in reverse: here the ad-hoc pass is **more** precise than
the lattice. Any claim that the type library subsumes these passes must account for it, or
explicitly scope it out.

### Corpus note

There is no slot for this today. A known-miscompiling case cannot be added GREEN (it
fails) and must not be added GAP (it does not GAP — see D1: GAP-declared cases are
`pass()`ed without running, so it would pin nothing while reading as coverage). Per the
bare-block precedent, the RED cases land WITH the fix, in the same commit that turns them
GREEN.

---

# Part F — t/base term.t + translate.t, priced (2026-08-10)

Both files reported the SAME first blocker, which read as one shared fix worth two
files. Measured per-construct, they have almost nothing in common. All measurements
below are through `ProgramRunner` (each snippet compiled as a standalone program,
stdout AND exit status compared against perl).

## F1: term.t is a TRUE ARCHITECTURE GAP — do not iterate on it

Its first blocker is not what stands in its way. Behind it, measured:

| construct | source | blocker |
|---|---|---|
| `` $x = `$^X -le "..."` `` | :20 | subprocess spawn (fork/exec) — lands as an untyped `Assign` |
| `open(try, "/dev/null")` | :41, :51 | `cannot lower op=Call` — file I/O |
| `<try>` | :43, :52 | `cannot lower op=Call` — readline |
| `-c '/dev/null'` | :48 | `cannot lower op=Call` — stat |
| `$#x` on a PACKAGE array | :27 | `Assign(Subscript-lvalue) container has repr=Str` — package arrays unmodeled |
| `$x \| 1` | :37 | `cannot lower op=BitOr` |

`BEGIN { chdir 't' if -d 't' }` and `chr(10)` already lower.

That is process spawning and filesystem I/O in a backend with no libc file support —
four separate subsystems, each a design decision about what the runtime IS, not a
lowering gap. **term.t should not be picked up as an iteration target.** It is the
wrong file to measure runtime-surface decisions against; when those subsystems are
built for their own reasons, term.t follows for free.

## F2: translate.t needs TWO unbuilt control-flow features, not one

Everything else in it already lowers — `for my $i (0 .. 255)`, BOTH
`utf8::native_to_unicode` and `utf8::unicode_to_native`, and
`print $i + 1 . " - x"` all PASS standalone. What remains:

1. **A void-effect statement modifier inside an if/else arm.** This is the blocker
   both files reported. `FromOptree.pm:3902`.
2. **A postfix modifier inside a foreach body.** `_body_has_modifier_andor`,
   `FromOptree.pm:2896` / `:2951`, zhi 019f5a27. Only reachable AFTER (1), and
   translate.t needs both — (1) alone does not unblock it.

Measured: a trailing `elsif` with NO `else` compiles its guard to a void `and` op,
where the identical code WITH an `else` stays a `cond_expr`. That is why (1) is
reachable from an ordinary-looking elsif chain at all.

## F3: ATTEMPTED AND REVERTED — routing (1) through the top-level If+Proj+merge

The GAP comment at `:3884-3895` says the top-level `and`/`or` handler (`:307`,
`$mem_branch`) already builds real control flow for exactly this shape, gated on the
same `_arm_has_void_call` predicate — so the in-arm site appears to need only to
reach it. **It is not sufficient. Measured, it silently drops the guarded effect.**

Outer arm taken, modifier guard TRUE, so the effect MUST fire:

| shape | result |
|---|---|
| `if(C){ print "hi" if G }` — modifier is the arm's ONLY statement | **FAIL, effect dropped** |
| `if(C){ print "hi" unless G }` — same, unless polarity | **FAIL, effect dropped** |
| `if(C){ print "hi" if G } else { $x=1 }` | **FAIL, effect dropped** |
| `if(C){ print "hi" if G } else { print "z" }` | PASS |
| `if(C){ print "A"; print "hi" if G }` | PASS |
| `if(A){print} elsif(B){print}` (no else) | PASS |
| `print "hi" if G` at top level (corpus L5) | PASS |

The boundary is sharp: it fails when the arm contains NOTHING BUT the guarded
effect. The mechanism is **[UNKNOWN — do not guess]**. A plausible story is that the
outer merge takes the arm's pre-branch control rather than its final control, but
three mechanism guesses were already wrong in this session's earlier work and this
one is not measured.

Separately, routing an ELEMENT STORE through the same path also miscompiles:
`my @a=(1,2); if(...){ $a[0]=7 } elsif(...){ $a[0]=9 } print $a[0]` compiled and ran
but printed NOTHING where perl printed `9`. Element stores need the memory-Phi the
value merge does not build.

Both reverted. The producer GAP stands, and the two producer tests that pin it —
`t/from-optree-nested-if.t:138` ("a void-effect statement modifier inside an arm
still GAPs loudly") and `t/from-optree-void-direct-call.t:63` ("a nested branch in
the arm stays a loud GAP") — were RIGHT and must not be relaxed as part of a future
attempt. They go green only when the effect actually fires.

**Ready-made RED for the next attempt:** the seven rows above. A fix that turns rows
1-3 green while keeping 4-7 green is correct; one that only makes the GAP go away is
the miscompile this entry exists to prevent.

---

# Part G — num.t / lex.t priced, and three miscompiles found doing it (2026-08-10)

Pricing these two files per-construct through `ProgramRunner` turned up more
live silent miscompiles than blockers. All measured against perl on committed
HEAD.

## G1: num.t and lex.t are both gated on SUBSYSTEMS, not lowering gaps

**num.t is a float↔string exactness suite.** `$a = 0.1; $a eq "0.1"`,
`1e34 eq "1e+34"`, denormal comparisons. Measured: every float case dies at
`Assign(StashAccess-lvalue) rhs repr=Num; only Int and Str package scalars are
lowered`. Behind that sits correct shortest-round-trip float formatting (dtoa)
in a backend with no libc float printing. Also needs `pack` and `$^O`.
Integer stringification, float arithmetic, and the `print C ? "ok\n" : "not
ok\n"` idiom already PASS.

**lex.t is a lexer suite whose second construct is `eval 'STRING'`** — runtime
compilation, i.e. embedding the compiler in the emitted executable. Heredocs and
`length()` already lower; `int()` GAPs (`cannot lower op=Call`).

Neither is an iteration target. With term.t (Part F) that makes **every
remaining t/base file gated on a subsystem decision**: process/file I/O, float
formatting, or runtime eval. The t/base drain is finished as a source of
incremental lowering work.

## G2: FIXED — `$#x` on a package array answered `1` for every array

See perl5-son 91b5097. `gv` pushes a global's NAME as a string Constant and
nothing replaced it for an AGGREGATE, so `$#x` became `Length(Constant("x"))` —
the length of the variable's NAME.

    @x unset        perl -1    chalk 1
    @x 1 element    perl  0    chalk 1
    @x 2 elements   perl  1    chalk 1    <-- agrees, by coincidence

The only agreeing case is a two-element array, which is exactly what term.t's
`$#x` check uses. A test asserting one array length could not have caught this.

Now a producer GAP. `@_` and `%ENV` stay exempt (they have real sources).
Package ELEMENT reads already GAPped one layer later in the backend, verified
before and after — the guard only moves that refusal earlier.

## G3: OPEN — `print` TRUNCATES a string at an embedded NUL

    print "a\0b"     perl: a\0b     chalk: a

Silent data loss. `length("a\0b")` is correct (3), so the length table is right
and the emission is wrong.

`lib/Chalk/Target/LLVM/Context.pm:5875` documents the path as:

    #   Str  -> printf("%.*s", (i32)len, ptr)  — exactly len bytes, embedded-NUL safe;

**That comment is false.** C's `%s` conversion stops at the first NUL;
precision is a MAXIMUM, not an exact count. The claim was written and never
tested. The same construct backs the `Str:` epilogue (`:47`).

The fix is not a one-liner, which is why it is filed rather than done:
`fwrite`/`write` would emit exact bytes, but print currently shares `printf`'s
buffering with the epilogue, and mixing buffered `printf` with unbuffered
`write` can REORDER output. Whatever replaces it has to move both, together.

## G4: OPEN — a Str constant containing a HIGH byte produces NO output at all

    my $p = "\xf0\x3f"; print length($p), "\n";
      perl: "2"     chalk: "" (nothing, exit 0)

Not a truncation — the program runs to completion and prints nothing, including
the trailing newline. NUL bytes alone are fine (`length("\0\0\0")` is 3), so the
boundary is bytes >= 0x80, consistent with the producer being ASCII-only.

This is what `pack("d", 1)` actually hits: perl CONSTANT-FOLDS it before the
producer sees anything, so there is no `pack` call in the graph at all — just a
`Constant` holding the 8 raw bytes of the IEEE754 double, and a `Length` over
it. Any fix belongs in Str constant handling, not in a `pack` builtin.
