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

---

# Part H — package scalars are not in SSA form (2026-08-10)

## H1: the defect

A lexical assignment is a DEFINITION: `$x = 1` does not store into `$x`, it
defines a new value that later uses of `$x` refer to. That is not a rule Chalk
adopts, it is what SSA IS, and the producer already implements it for pads via
the scope-binding map (`$sim->define` / `$sim->lookup`, Phis at merges).

Package scalars are routed elsewhere — to a `StashAccess` node plus an `Assign`
— and are therefore NOT in SSA form. Every consequence below is downstream of
that single omission.

## H2: measured, the same program passes as `my` and cannot compile as `our`

    my  $x = "hello"; $x = 1; $x = 0.5;   ->  PASS  (and reads between each
                                                store are correct: "hello 1 y")
    our $x = "hello"; $x = 1; $x = 0.5;   ->  GAP

Identical semantics in perl. The dataflow-modeled path handles three definitions
with three representations; the cell-modeled path cannot express it.

## H3: the slot kinds are perl's SV union, rebuilt one type at a time

Because a package scalar is modeled as storage, the storage needs a type, and
because a perl scalar can hold several, the backend grew one slot KIND per
representation:

    Int   one i64 module global          @pkg_<s>_<v>
    Str   a (ptr, len) pair               @pkg_<s>_<v>_ptr / _len
    Num   one double module global        @pkg_<s>_<v>_num   (added 04b7853e)

That is the SV union being reassembled. A ref would want a fourth kind, a
DualVar a fifth. A DualVar is in fact the ONLY case where one scalar genuinely
carries two representations at once — and that is a property of the VALUE, not
a question about storage.

## H4: what it cost — four silent miscompiles, two of them mine

The lvalue node is hash-consed, so every store and read of `$g` share ONE node
carrying ONE representation, while each store carries its own. When they
disagree the store writes a slot family no read loads from, and it is lost:

    our $g = 1;     $g = "hi";  print $g    perl: hi   chalk: 1
    our $g = "hi";  $g = 7;     print $g    perl: 7    chalk: hi
    our $g = 1;     $g = 2.5;   ...         perl: y    chalk: n
    our $g = 2.5;   $g = 1;     ...         perl: y    chalk: n

The first two predate this work. **The last two are a regression I introduced in
04b7853e**: before it they GAPped loudly ("only Int and Str package scalars are
lowered"); adding the Num slot kind turned two honest refusals into two silent
wrong answers. Adding a kind to this model does not extend it, it widens the
window in which the model is wrong. All four now GAP
(`Target/LLVM/Context.pm`, Assign(StashAccess-lvalue)).

## H5: the fix

Put package scalars in SSA form, like every other variable. They are not a
different kind of thing — `our` and `my` differ in visibility and lifetime, not
in typing — so they belong in the same binding map, with the same Phis at
merges, and no slot at all in the common case.

Storage remains only where a value must outlive the unit's dataflow: genuine
cross-unit visibility, a reference taken, `local`, runtime symbol-table access.
Those are memory effects and belong in memory-SSA, which already exists ("full
memory-value + MemPhi, one global memory"). Even there the storage holds a
VALUE; it does not need a per-representation kind.

Deleting the slot kinds is the test of whether this landed. While
`_pkg_globals` / `_pkg_str_globals` / `_pkg_num_globals` still exist as three
parallel families, the SV union is still being maintained by hand.

**Do not add a fourth slot kind.** A ref-valued or DualVar package scalar is not
the next kind to add; it is more evidence for this entry.

## H6: LANDED — perl5-son 38af599 + chalk e82dfce3

Package scalars are bound in the same scope map as lexicals. All four
miscompiles in H4 now produce CORRECT answers, not GAPs, and
`our $x = "hello"; $x = 1; $x = 0.5` behaves exactly like the `my` form,
including reads between definitions.

`StackSim` needed no changes: `%scope` takes any key, so a qualified name works
like a pad index and `merge()` builds Phis over it unchanged. Three routing
sites moved — the gvsv/rv2sv read (mirroring padsv's OPf_MOD lvalue/rvalue
split), the sassign store (mirroring the PadAccess branch), and the implicit
`$_` match subject, which built a fresh StashAccess and so bypassed the binding.

`StashAccess` keeps ONE role: the ENTRY DEFINITION, naming a variable's incoming
value before any assignment in this unit.

Corpus: 168 with all four legs agreeing. 12 ir blocks were transcribed to the
new shape, each carrying a note — the package variable no longer appears in the
graph at all, because a constant-valued binding folds. `our $g = 5; $g` is now
`Constant(5) + Return`, constant propagation the slot model actively prevented
by forcing the value through memory.

## H7: the slot machinery is now DEAD CODE — deletion is the remaining cleanup

Measured after H6, on committed HEAD:

    our $g = 5; print $g          PASS   no @pkg_ slot emitted
    our $g; $g = 5; ... read      PASS   no @pkg_ slot emitted
    our $g; read before write     GAP    (never reaches the slot)
    $main::nope read, no write    GAP    (never reaches the slot)

No compiling case reaches `_lower_stash_access` or the `Assign(StashAccess-
lvalue)` arm. Only an ENTRY DEFINITION would, and it GAPs earlier with "Add node
has no representation" because nothing stamps an unassigned variable.

So `_pkg_globals`, `_pkg_str_globals` and `_pkg_num_globals` — with their
per-representation slot kinds, the SV union rebuilt by hand — are unreachable.

**Two things to know before deleting them:**

1. `StashAccess` nodes still EXIST in graphs and must not be removed as a node
   type. `shift @_` is identified structurally by a Call whose operand is
   `StashAccess(*, _)` (`Target/LLVM/Context.pm:4664`), and `@_` is built as
   `StashAccess(main, _)` by the producer's `_args_source`. Deleting the slot
   LOWERING is safe; deleting the node type is not.

2. The entry definition needs an answer, not just a deletion. Its GAP message
   currently blames the consumer ("Add node has no representation") rather than
   naming the real cause, which is a package scalar read before any assignment.
   Per the lowering rule — pick the Chalk type's LLVM type and add a coercion —
   an unassigned package scalar at unit entry is `Undef`, and needs no slot at
   all. That is correct for a whole-program compile, which is what chalk does
   today; a separately-compiled sub would instead be reading the outside world's
   value, and that is the same boundary F3 (real define+call) has to answer.

## H8: package-scalar SSA is currently sound BECAUSE everything is inlined

Worth stating before it is discovered the hard way. `_lower_call_direct` GAPs on
recursion with "inlining is the only direct-call mechanism and cannot terminate
on a cycle. Real define+call emission is required to lower this." With every
call inlined, the whole program is ONE dataflow region, so a package variable's
definitions and uses are all visible and SSA is sufficient.

When F3 lands, a package variable read inside a real callee has no reaching
definition in that graph. It needs a parameter, or genuine storage. This work
and F3 are coupled, and H7's deletion should not be read as "package scalars
never need storage" — only as "they do not need a typed cell per representation
in a single-region compile".

## H9: the grouping was wrong — the axis is ESCAPE, not package-vs-lexical

"Package scalar" is not the right category for any of this. A LEXICAL escapes
just as readily — `sub { my $x = 5; \$x }`, or a closure capturing it — and an
ANONYMOUS reference has no NAME whose later reads must observe writes, so it
does not raise the demotion question at all. Where its storage lives is a
separate, open question: an anonymous aggregate that never escapes need not be
heap-allocated, and perl's heap-and-refcount model is evidence about perl, not
a requirement on chalk.

The axis is whether a variable's uses are all visible in the region being
compiled. `our` vs `my` is irrelevant to it.

Likewise, "chalk has no memory representation for scalars" (as H7 put it) is
wrong. An EPHEMERAL scalar — an SSA value in the graph — needs none. A STORED
one has a static Chalk type, which maps to an LLVM type, which IS its memory
representation. The `@pkg_*` globals were already that; what made them wrong was
being applied to every package scalar, typing the VARIABLE rather than its
dataflow, so one variable could need several kinds. What is genuinely missing is
narrower: the decision of which variables escape, and scalar load/store on the
memory chain (which threads aggregate ELEMENTS today).

Note the asymmetry that falls out: an SSA value carries its own type per
definition, while a demoted variable is a CELL and therefore has ONE type — the
join over its stores, with a coercion at each. The "join-typed slot" idea is
wrong for an SSA variable and right for a genuinely stored one.

**Recurring failure mode, second instance this session.** The first draft of
this entry said an anonymous reference "needs heap allocation", which is an
implementation choice asserted as a requirement — the same error as the
"array-extending coercion mutates a heap object" claim recorded above, which was
also retracted. Storage strategy is an L3 decision; perl's heap-and-refcount
model is evidence about perl. Design notes should state what must be OBSERVABLE
(a later read sees an earlier write) and leave where the bytes live open.

## H10: MY REGRESSION, OPEN — a package variable defined in a sub is dropped

    our $g = 5;  sub bump { $g = 9 }  bump();  print $g
      perl: 9     chalk: 5      -- silent, no GAP

Introduced by package-scalar SSA (38af599), verified by measurement against
38af599~1, where it was a loud GAP. The old Assign(StashAccess) was an EFFECT on
the callee's control chain and the inliner refused a callee with effects; a
definition carries no node, so the callee now looks clean and the inliner
accepts it while the definition vanishes.

This also FALSIFIES H8. Inlining does not make package-scalar SSA sound: each
sub is translated as its OWN graph, with its own binding map, BEFORE any
inlining happens. Cross-graph visibility was never covered.

**The fence is written and works** — `_translate_from` computes `is_program`
(only `translate_root` passes `program_root`), and refusing a package-scalar
definition when it is false turns the case back into a loud GAP. It is NOT
switched on, for one reason:

> the chalk corpus harness wraps every case in `sub corpus_case { ... }`, so a
> fragment is indistinguishable from a real sub, and all 12 package-scalar cases
> GAP (measured: gate-green 168 -> 156).

So the corpus cannot currently represent a package-scalar case honestly: the
wrapper decides whether the variable escapes. This is the same harness wrapper
recorded at the end of the wrapped-contract removal — `son-corpus-wide.t:51`
re-implements the `sub` wrap, and `:88` duplicates the exit-status defect.

`is_program` is left computed-but-unused with a comment, so the fence is one
line away once the harness question is settled.

**Decision needed before this can close:** either the corpus compiles a case as
a PROGRAM (matching what `executable-gate` already does for real files), or
package-scalar cases move to a harness that does. Real programs are unaffected
by the fence — `__PROGRAM__` is the entry — so this is purely a corpus-shape
question.

## H11: escape routes, audited

    \$lexical, \$package        FENCED (address-taken, 1b34be6)
    closure captures a lexical  GAPs on unresolved callee — NOT by an escape rule
    named sub writes a package  **H10, MISCOMPILE**
    named sub reads a package   GAPs (StashAccess with no representation)
    anonymous ref               correctly unaffected — no name to observe

Only the address-taken route is fenced by design. The closure routes are covered
incidentally by the callee-resolution GAP, which is not an escape check and
should not be relied on as one.

## H12: sharper still — the axis is REFERENCES, not escape

H9 said the axis is escape. That is a symptom, not the trigger.

    my $x = 5; my $r = \$x; $$r = 9; print $x;

Nothing escapes: every use is inside the compiled region and visible to the
dataflow. `$x` still cannot be a pure SSA value, because a write reaches it
through an alias. An escape analysis would have called this case safe.

**A variable that is REFERENCED cannot be a pure SSA value.** Escape is a
separate question — it governs WHERE the storage lives and HOW LONG, not
WHETHER storage is needed.

This matches the prior art more exactly than "escape" did. LLVM's mem2reg
promotes an alloca only when it is *used solely by loads and stores* — i.e. no
pointer is taken. An address-taken-but-non-escaping alloca is still not
promoted. GCC's split is the same: an aliased variable gets virtual operands
regardless of whether it leaves the function.

It also explains why the fence that landed (1b34be6) is correct: it triggers on
the reference being TAKEN, not on any escape judgement, so the non-escaping case
above is refused too. Had it been built as escape analysis it would have passed
that case and miscompiled it.

The routes in H11 unify under this reading — each is a way for something other
than a named use in this dataflow to reach the variable:

    \$x                     an explicit reference
    closure capture         the closure reaches the variable, not a copy
    package var from a sub  reached through the symbol table, not this dataflow
    local                   saves and restores the referenced cell

**Not asserted:** the exact mechanism perl uses for closure capture. It is
recorded here as a route that must be handled, not as a claim about pads or
globs — H11 already notes those routes are only covered incidentally today, by
an unresolved-callee GAP that is not a reference check.

So the demotion question to answer per variable is "is this variable
referenced?", and only then "and does the reference outlive the region?", which
decides placement. The second question is where escape analysis belongs.

## H13: H10 diagnosed — the lookup never consults a PACKAGE scope

H10 framed the cross-sub drop as "escape needs demotion". The proximate cause is
narrower and is a SCOPING bug: inside `bump`, `$g` is not declared in the
lexical scope, and the lookup has nowhere else to go. `%scope` is flat and
per-graph; there is no package scope to fall through to.

### The package is a scope, and its symbol table is that scope as a hash

VALIDATED, not assumed (perl 5.42):

| probe | result |
|---|---|
| `our $g = 5` creates a stash entry | yes, a glob |
| a `my` variable appears in the stash | **no** |
| writing THROUGH the stash entry changes `$g` | yes, 5 -> 99 |
| replacing the glob replaces the variable | yes, 5 -> 42 |
| a sub reaching an `our` variable compiles to | `gvsv`, not `padsv` |
| fully-qualified access compiles to | `gvsv` |

Rows 3 and 4 are the load-bearing ones: the stash entry IS the storage, not a
view or an index — writing through it writes the variable, and replacing it
replaces the variable. Row 2 confirms it holds package bindings specifically.

Row 5 also disposes of a plausible objection: `our` does NOT turn a later use
into a lexical access. It compiles to `gvsv` exactly like a fully-qualified one,
so there is one access mechanism, not two.

REFINEMENT the probe produced: what is exposed is a hash of GLOBS, and a glob is
a multi-slot container — `$g`, `@g` and `%g` share ONE stash entry. So a name
maps to a SLOT SET, not to a single binding. A Chalk Scope modelling this binds
a name to per-sigil slots rather than to one value.

The model this points at: a package is a SCOPE like any other, and its symbol
table is that Scope object exposed as a hash. A name lookup walks the chain —
lexical, then enclosing, then package — with no special case for globals. Chalk
has the innermost link of that chain and nothing beyond it.

Measured, `our $g = 5; sub bump { $g = 9 } bump(); print $g`:

    main::bump          Start; Constant(9); Return(9)
    main::__PROGRAM__   Constant(5) -> Stringify -> Concat -> Call(bump) -> Print

`$g = 9` became a binding in `bump`'s own map. Nothing in `bump` reads it
afterwards, so it survives only as the return value — that it wrote to `$g` is
recorded NOWHERE. `__PROGRAM__`'s read resolves against its own map to 5, with
no edge to the callee.

### A shared package-scope map is NOT the fix

Worth stating because it is the obvious next move and it is order-dependent:

- translate `__PROGRAM__` first → its read sees 5; `bump` has not been walked
- translate `bump` first → `__PROGRAM__`'s own `= 5` overwrites the 9

Neither is execution order. Translation order is not program order, so a mutable
map shared across graphs produces a different wrong answer rather than a right
one.

### The call is the definition site

What makes it correct: a `Call` whose callee assigns `$g` PRODUCES a new
definition of `$g` in the caller — the same shape as a call that writes memory
producing a new memory value on the existing chain. The callee's graph has to
carry which package names it defines, so the call site can bind them.

This is where the scoping framing and the reference axis (H12) meet — and it
also corrects H11, which listed "reached through the symbol table" as a distinct
reference route.

**The symbol table is not a separate mechanism. It is the package's Scope object
exposed as a hash.** So a package lookup is the SAME lookup a lexical does, just
terminating one scope further out; there is one mechanism (Scope), not two. What
distinguishes the package scope is that it is SHARED BETWEEN GRAPHS.

That sharing is what forces the H12 conclusion here: a name reachable from more
than one graph cannot be pure value-SSA in either, for the same reason a
referenced variable cannot be — something outside this dataflow can reach it.

Exposing that Scope as a hash is an ADDITIONAL capability. When a program
actually uses it (`*main::g`, a symbolic ref, `no strict 'refs'`), bindings
become reachable dynamically, by a name computed at runtime — which is a
strictly harder case than the static sharing above and is not what H10's
`bump()` needs.

### Consequence for the fence

The `is_program` fence (H10) refuses a package definition inside any sub, which
is broader than this diagnosis warrants — it would refuse a sub that assigns a
package variable nothing else ever reads. It is the right STOPGAP because it
restores the loud GAP the SSA change removed, but it is not the fix, and it
should not be mistaken for one when the corpus-shape question is settled.

---

# Part I — corpus-as-programs migration: piloted, blocked, tool committed (2026-08-11)

## I1: what the migration is

A corpus case is wrapped by the harness in `sub corpus_case { ... }` and scored
on its RETURN VALUE, read back through the `Int:`/`Str:` type-tag epilogue. The
target shape is a real PROGRAM whose value is observable as stdout, scored on
(stdout, exit) — the contract `ProgramRunner` and `executable-gate` already use.

The wrapper is not just a name: it supplies a **value context**. A program's top
level is void context, so perl discards a bare trailing expression before the
producer sees it — `1 + 2` as a program compiles to `enter; nextstate; leave`,
nothing at all (measured). That is why `say` had to land first (perl5-son
96d2df6): it is the operator that makes a case's value observable.

## I2: the migration is SAFE to do incrementally — sources first, harness last

Measured, and this is the key enabler. Under the CURRENT harness,
`sub corpus_case { say 1 + 2 }` prints `3\n` and returns say's Bool, so the perl
oracle and lli BOTH produce `3\nBool:1` and the case still passes its behavior
leg. Only the shape leg needs its ir block updated per case.

So case sources can migrate one file at a time with the gate staying green, and
the harness flips at the END. A big-bang harness flip would instead compare
EMPTY stdout to EMPTY stdout on every unmigrated case — 194 vacuous passes,
which is far worse than failures.

## I3: the transform (committed: `tools/migrate-corpus-to-programs.py`)

Per case: wrap the trailing value expression in `say(...)`; rewrite
`return: X` to `stdout: X\n` + `return: Bool:1`; thread the ir block's returned
value through `%nl = Constant("\n")` + `%p = Print(<value>, %nl)` and
`return %p`.

Two things it must get right, both learned by measurement:

- The value is the last STATEMENT, not the last LINE. Sources routinely put
  several statements on one line (`my $c = 1; if (...) {...} else {...} 1`), and
  wrapping the line produces `say(my $c = 1; if ...)`, which is not valid perl.
  The transform scans back to the last top-level `;` or `}` and wraps only what
  follows. This single defect accounted for 16 of the failures.
- A GAP-declared case is skipped: it is `pass()`ed without running, so its
  source shape does not matter and rewriting it would only add noise.

## I4: measured state of a full run — 172 -> 146, NOT landable yet

    script migrated      164 of 194 cases
    gate after           gate-green=146 (floor 172), worklist 26

    19  no loaded graph        transform still mangles these sources
     4  Print of a Bool arg is not lowered runtime-free
     2  Print of a Num arg  is not lowered runtime-free
     1  Region.Phi with no representation
     1  foreach with a runtime high bound

## I5: THE BLOCKER — only Str and Int can be printed

`Print` lowers only Str and Int list args. Measured: `say 0.75` GAPs with
"Print of a Num arg is not lowered runtime-free (only Str and Int list args are
emitted)", and Bool and Slot GAP the same way.

This is a hard dependency, not a nuisance: the harness cannot flip until EVERY
case migrates, so six cases that cannot print their value block the whole
migration. The type-tag epilogue hid this — it formatted a Num on the ORACLE
side and printed the tag from a known repr on the lli side, so no runtime
float-to-string ever ran.

Printing a Num is the same dtoa subsystem recorded as t/base/num.t's blocker
(Part G1). So the corpus migration and num.t are gated on one piece of work.
Bool and Slot are much smaller — a Bool prints as "1" or "", a Slot is the
Maybe[word] pair — and could land independently.

## I6: remaining work, in order

1. `Print` of Bool (4 cases), then Slot (1). Small, and unblocks most of I4.
2. `Print` of Num — the dtoa subsystem, shared with num.t.
3. Iterate the transform over the 19 sources it still mangles.
4. Flip both harnesses: `son-corpus-wide.t`'s `run_through_bson`/`perl_oracle`
   and `MdtestCorpus::_run_expr_under_perl`, to compile as a program and compare
   (stdout, exit).
5. Add a NON-VACUITY check at the same time: after the flip, a case whose oracle
   stdout is empty must fail rather than pass, or an unmigrated case silently
   reads as covered.
6. Delete the `Int:`/`Str:` epilogue's last consumer, and with it the
   `son-corpus-wide.t:88` exit-status defect (Part D / the wrapped-contract
   removal), which is the point of the exercise.

---

# Part J — operators inject coercions; Stringify IS Coerce(X->Str) (2026-08-11)

## J1: the rule

**Operators are rarely polymorphic. An operator states its operand types, and a
non-conforming operand is bridged by an explicit coercion node — the operator
does not learn a representation.**

Three operators were fixed this way in one session, and each fix DELETED code:

| operator | was | now |
|---|---|---|
| `Print` | lowered Str and Int itself, GAPped Bool/Num/Slot | `Print(Str...)`; producer injects `Stringify` |
| `Add`/`Subtract`/`Multiply` | required exactly Int | `(Num,Num)->Num`; mixed application gets `Coerce(Int->Num)` |
| `StrEq`/`StrNe` | called `_emit_int_to_str` itself | `(Str,Str)`; producer injects `Stringify` |

The pattern each time: a per-type case in the operator turned out to be a
coercion in disguise, and the same conversion existed in TWO places — so a new
type had to be taught to both, and one of them was always behind. `eq` still
declared Num "unbuilt" after `Stringify` could already render one.

## J2: Stringify and Coerce are the same function with different name tags

Measured overlap, not inferred: the backend implements `Coerce(Bool->Str)` at
`Target/LLVM/Context.pm:1151` AND `Stringify(Bool)` at `:970`. The SAME edge,
twice. `Stringify(X)` is exactly `Coerce(X -> Str)`.

`Coerce`'s implemented pairs: Int->Num, Num->Int, Bool->Int, Bool->Num,
Bool->Bool, Bool->Str, Str->Num, Str->Bool.
`Stringify`'s: Bool->Str, Num->Str, Int->Str.

Only `Stringify` has Num->Str and Int->Str; only `Coerce` has the numeric pairs;
Bool->Str is in both.

### A latent divergence the duplication already produced

`Coerce(Bool->Str)` selects the POINTER only and records NO length in
`_str_len_table`. `Stringify(Bool)` selects the pointer AND the length, because
a false Bool is the empty string — zero bytes — and a Str value is a
`(ptr, len)` pair.

Measured: NOT currently reachable. Concat and interpolation route a Bool through
`Stringify`, not `Coerce`, so all five probes (say/concat/interp over both
polarities) pass. Latent, not live — recorded rather than fixed, because a fix
with no failing case to justify it is a guess.

That divergence is the argument for merging: two implementations of one edge
drift, and this pair already has.

## J3: doing the merge

Blast radius, measured: 49 `Stringify` references in chalk lib/, 15 in the
producer, 26 `ir`-block lines across three corpus files, plus
`lib/Chalk/IR/Node/Stringify.pm`, a NodeFactory entry, and the wire format
(`_extract_fields` emits Coerce's `from_repr`/`to_repr`; Stringify carries
neither).

Order that keeps the gate green throughout:

1. Give `Stringify` `from_repr`/`to_repr` on the wire, defaulted to
   `(<operand repr>, 'Str')` — no behaviour change, but the two node types now
   carry the same fields.
2. Fold `Stringify`'s three arms into `_lower_coerce` as the `X -> Str` cases,
   taking `Stringify(Bool)`'s length-selecting version (it is the correct one).
   Have `_lower_stringify` delegate.
3. Switch the producer's injection sites (print/say args, StrEq/StrNe operands)
   to build `Coerce(X->Str)`.
4. Rewrite the 26 corpus `ir` lines, then delete `Stringify` and its node class.

Step 2 is where the latent Bool defect closes, and it closes as a side effect of
the merge rather than as a separate fix.

## J4: what is NOT polymorphism

Not every repr branch is an operator learning types. These are correct as they
stand and must not be swept into the rule:

- `Constant` (`:597`) — materializing a literal per representation IS its job.
- `Coerce`/`Stringify` — dispatching on representation is the whole point.
- `_method_fn_type` (`:17`) — an ABI signature, not an operand rule.

The suspects are operators that inspect an operand and choose behaviour.
`_lower_divide` still calls `_lower_as_double` on its operands, but measured,
every Divide that REACHES the backend already carries a `Coerce` on each Int
operand — `3/4`, `$a/$b` over Int package scalars, mixed Num/Int, and lexicals
all show `Divide(Coerce, Coerce)` or `Divide(Constant/Num, Coerce)`. So that
call is dead defence, not a live implicit coercion, and can go when the merge
lands.

The compound form `$x /= 2` shows an uncoerced `StashAccess` operand in the
graph, but it does NOT reach Divide's operand handling: measured, it GAPs
earlier with "StashAccess reached LLVM backend with NO representation". It is
an unstamped-operand problem, not a coercion one — do not read the graph shape
as evidence that `_lower_as_double` is load-bearing.

---

# Part K — an aggregate element can only hold an Int (2026-08-11)

## K1: the defect

    %Slot      = type { i1, i64 }                 array elements, object fields
    %Array     = type { i64, i64, %Slot* }
    %HashEntry = type { i8*, i64, i32, i1, i64 }  key_ptr, key_len, key_enc,
                                                  val_def, val_pay
    %Hash      = type { i64, i64, %HashEntry* }

One `i64` payload. Measured:

    my @a = (10, 20);        print $a[1]   PASS
    my @a = ("hi", "there"); print $a[1]   GAP: ArrayRef element repr=Str cannot be stored
    my @a = (1.5, 2.5);      print $a[1]   GAP: ArrayRef element repr=Num cannot be stored
    my %h = (k => "val");    print $h{k}   GAP: HashRef value repr=Str cannot be stored
    my %h = (k => 7);        print $h{k}   PASS

`my @a = ("hi", "there")` is unremarkable Perl and cannot be represented. A Str
is a `(ptr, len)` pair and does not fit in one word; a Num is a double and would
need a bitcast that is not emitted.

## K2: the design is NOT wrong — fields already solve it

An object field is declared `%Slot` too, and `field $s :param = "hi"` WORKS
(measured). `_store_field_payload` (`Target/LLVM/Context.pm:4300`) boxes a Str
into a heap `%StrPair { i8*, i64 }` and stores `ptrtoint %StrPair*` in the
payload. The `i64` is a machine WORD: it carries an Int directly, or a pointer
to anything wider.

So the cell is adequate and arrays/hashes simply never learned the boxing that
fields already do. Part J's pattern again — one idea, several implementations,
and the ones that were not exercised fell behind.

## K3: a third spelling of the same cell

`%HashEntry` inlines `{ ..., i1 val_def, i64 val_pay }` rather than nesting a
`%Slot`, presumably to keep an entry in one allocation. Structurally it IS a
Slot. So the optional-value cell has three spellings: `%Slot` in arrays, `%Slot`
in object fields, and an inlined pair in hashes.

Consequence already observed: a hash value read does NOT carry the `Slot`
REPRESENTATION, so `Coerce(Slot -> Str)` does not serve it. A missing key still
prints empty correctly, by its own path (measured, both polarities) — so this is
duplication, not a live defect.

## K4: what closing it needs

Reuse `_store_field_payload`'s boxing at the ArrayRef and HashRef construction
sites, and the matching unbox on the read side. The read must know WHICH face
the payload holds, so the element repr has to be carried on the container (an
`Array[T]`-style element type) rather than inferred per access — which is the
`_element_repr` question already in flight.

Not attempted here. It is a capability gap, not a regression, and it is larger
than the migration errand that surfaced it.

## K5: where this leaves the corpus-as-programs migration

Re-measured after `Coerce(Slot -> Str)` and the `DefinedOr` join landed
(b0762b43): **177 green against a floor of 182**, worklist 5. Down from a
6-case shortfall, so both fixes bought exactly what they should.

The five remaining, and none is a transform defect:

| case | needs |
|---|---|
| arithmetic OOB read, references R9 | the Slot-Int epilogue: these print a Slot whose value is an Int, and the migrated form disagrees with perl on the tag |
| L3b defined-or undef-left | an `undef` LHS reaches the backend untyped — distinct from the DefinedOr join fixed in b0762b43 |
| L3c defined-or early-return | a Region Phi over an early-return merge arrives untyped |
| D4 postfix if | the pre-existing 2b-3 mixed-effect GAP (scalar rebind + void effect in one and-arm) — the same blocker t/base/term.t and translate.t sit behind |

Two of the five are one capability (untyped merges), and D4 is a blocker already
tracked for t/base. The migration is closer to parity than the raw number
suggests, but it is still a net loss and must not land as one.


## K6: DONE for literals; element STORES are a separate, narrower gap (2026-08-12)

Built. One rule, `_box_payload($val, $repr, $what)` in `Target/LLVM/Context.pm`,
replaces the per-site repr dispatch at every aggregate construction site: Str
allocates a heap `%StrPair` and stores its ADDRESS in the payload word, Num
bitcasts, Bool zero-extends, refs `ptrtoint`, Int passes through. The read side
is the exact inverse, added to both `_lower_array_read` and `_lower_hash_read`;
the Str arm also re-registers `_str_len_table`, without which `length()` on an
element reads whatever length was tracked last.

The unbox is not optional polish. Boxing WITHOUT it is strictly worse than the
GAP it replaces: the store is correct, the read loads the address as an Int, and
the program prints a heap pointer. Measured mid-build, `$a[1]` of `("hi","there")`
printed `94799381086576`. That is the GAP-to-miscompile inversion, self-inflicted;
it is why both halves land in one commit.

K4 predicted the read "must know WHICH face the payload holds, so the element
repr has to be carried on the container rather than inferred per access." Half
right, and the half that is wrong is the useful half. For a LITERAL aggregate
`_element_repr` already computes exactly that — it joins the initializers, and
the read is stamped with the result — so literals needed no new mechanism at all.

Element STORES are where the prediction bites, and they stay a GAP:

    my @a = (1,2); $a[0] = "zz"; print $a[0];   # GAP, deliberately

`_element_repr` reads the container's literal INITIALIZERS only. A store that
changes the element type is invisible to it, so the read is still stamped `Int`
while the payload now holds a `%StrPair*`. Both sides are individually correct
and together they are a miscompile. The store sites therefore admit only
Int/ArrayRef/HashRef/CodeRef/Object — the reprs whose face cannot change what
the read expects — and refuse Str and Num with a GAP naming the reason.

Closing THAT needs inference, not codegen: the element repr must be the join
over the literal elements AND every value stored into the container, with a
coercion bridging any element that does not conform — the Part J operator rule
applied to a container. It is the same shape as the package-scalar work: a store
is a definition, and the container's element type is the join over all of them.

Measured: gate-green 184 → 189, all four legs, worklist 0. Five new GREEN cases,
references R16-R20, covering both containers across Str and Num plus `length()`.
Executable gate unchanged at 7/8.

---

# Part L — the migration is 4 short, and 2 of those are a harness defect (2026-08-11)

## L1: measured, after the inference fixes

    gate-green=180  behavior=180  shape=182  invariant=183   floor 184

Four short, down from six (Part I5) and then five (Part K5). `Coerce(Slot->Str)`,
the `DefinedOr` join, the `Undef` declaration type and the lattice-derived join
each bought exactly what they should. L3b is closed outright.

| case | what it actually is |
|---|---|
| arithmetic OOB read | **harness defect** — see L2 |
| references R9 | **harness defect** — see L2 |
| L3c defined-or early-return | a Region Phi over an early-return merge is untyped |
| D4 postfix if | the pre-existing 2b-3 mixed-effect GAP, the same blocker t/base/term.t and translate.t sit behind |

So ONE capability gap (L3c) and one already-tracked blocker (D4) actually stand
between the migration and parity.

## L2: a FOURTH harness defect — the oracle captures perl's WARNINGS

`son-corpus-wide.t:101` runs the perl oracle as `qx($PERL $tmp 2>&1)`, so
anything perl writes to STDERR becomes part of the expected output. Chalk emits
no warnings, so a case whose perl side warns can never match.

Measured on R9 (`my @a = (1,2,3); say($a[9])`):

    perl oracle : "Use of uninitialized value in say at ...\n\nBool:1"
    chalk lli   : "\nBool:1"

The LOWERING IS CORRECT. The graph is `Subscript :Slot -> Coerce :Str -> Print`,
the out-of-bounds read prints the empty string, and the epilogue tags `Bool:1` —
verified by loading the wrapped case and reading the reprs, and by running the
emitted module directly. Only the warning text differs.

This mattered only once the migration made these cases PRINT an undefined value.
In the pre-migration form the undef never reached `say`, so perl never warned.

That is the fourth defect in this harness, alongside the three already recorded:
the `sub corpus_case` wrap (which supplies a value context, Part I1), the
`Int:`/`Str:` epilogue, and `:88` reading any nonzero lli exit as
failure-to-lower. The wrap and the epilogue are what the migration exists to
remove; this one is independent and should be fixed on its own terms.

**The fix is not simply dropping `2>&1`.** A GENUINE runtime error on the perl
side must still be visible, or a case whose oracle dies would silently compare
empty-to-empty. Capturing stderr separately and comparing only stdout, while
failing loudly on a nonzero perl exit, is the shape — the same split
`ProgramRunner` already uses.

## L3: order to reach parity

1. Fix the oracle's stderr capture (L2). Closes 2 of the 4 with no compiler
   change, and removes a class of false failure the migration would otherwise
   keep hitting.
2. Type the early-return merge (L3c). One capability, the same family as the
   `DefinedOr` join.
3. D4 is the 2b-3 mixed-effect GAP. Already tracked, already has a ready-made
   RED in Part F3, and blocks t/base files too — worth doing for its own sake
   rather than for the migration.

Only after those does the migration land at or above parity, at which point
steps 3-4 of Part I6 (flip both harnesses, add the non-vacuity check) can run.
