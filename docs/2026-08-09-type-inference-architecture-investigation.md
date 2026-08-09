# Type-inference architecture investigation

ABOUTME: Characterises Chalk's repr-inference failure model, measures the root
ABOUTME: causes behind untyped IR nodes, and lays out design options with trade-offs.

Date: 2026-08-09
Status: INVESTIGATION — characterisation + options. **No implementation plan.**
Scope: read-only. Nothing in `lib/`, `t/`, or the producer was modified.
Chalk: `phase5-capstone` @ `a16ddc80`. Producer: `~/dev/perl5-son` @ `pu`.

---

## HEADLINE — the trigger does not fire

The investigation was commissioned around `lib/Chalk/IR/Serialize/JSON.pm:1105`:

```perl
next if grep { !exists $_REPR_RANK{$_} } @reprs;
```

**Measured: this bail fires ZERO times across every case examined** — all 182
mdtest corpus cases, all 4 named ring files, and `fib`.

It is not dead code. A positive control proves the instrumentation is live:

```
=== POSITIVE CONTROL: Bool + Int ===        # sub __main__ { my $b = (1 == 1); my $x = $b + 1; $x }
value nodes: 4   untyped: 1
  BAIL  JOIN_UNRANKABLE:Add:Bool,Int = 1
```

So the site is reachable — arithmetic on a boolean reaches it — but nothing in
the corpus or the worklist does that. **The judgement that this `next` should be
loud is right in principle, and making it loud would change nothing measurable.**
It is not the cause of any observed failure, and a slice built on it would be a
slice against a shape no measured input produces.

The instinct behind the trigger is nevertheless correct, and generalises: the
mechanism is real, it is just sited one bail-point over. See §F.

---

## Corrections to the given facts

Three of the six measured facts I was handed are wrong or materially understated.
All three were verified independently.

**Fact 1 is wrong: the TypeInference semiring is NOT orphaned.**
`lib/Chalk/Bootstrap/Perl/Actions.pm:895-902` makes it a hard production
dependency of the Chalk self-hosting frontend — it *dies* without it:

```perl
        # TypeInference is the sole authority for method return types.
        my $ti_ctx = Chalk::Bootstrap::Semiring::SemanticAction::current_type_context();
        die "MethodDefinition: TI context unavailable for '$method_name_str'"
            unless defined $ti_ctx;
```

And the consumer set is not 4 test files:

```
$ grep -rl "TestPipeline" t/ | wc -l
109
```

There are not two type systems where one is dead. There are **two live paths**:
the Earley/MOP frontend (which uses the semiring) and the B::SoN→JSON→LLVM
executable path (which does not). Neither is an orphan; they are disjoint.

**Fact 1's "~38 lines of ad-hoc repr stamping" is a ~16x undercount.** The repr
machinery in `Serialize/JSON.pm` spans lines 606-1427 — 14 subs and 4 tables,
roughly **635 lines**, including a genuine fixpoint (`_propagate_computed_reprs`,
1025-1118) and interprocedural return-type resolution that walks the MRO
(`_stamp_method_call_reprs`, 1369-1427). This is not ad-hoc stamping. It is a
second, independently-grown inference engine, and it is the more capable of the two.

**Facts 2, 3, 5, 6, 7 confirmed.** `_require_repr`: 27 sites in `Context.pm` + 4
in `LLVM.pm` = **31**. `Scalar` die-guards in `Context.pm`: **15**. `Scalar`
produced: **0** sites, in either repo.

---

## F. How many root causes? (answered first — it drives everything else)

**Measurement method.** I copied the loader to a scratch dir, instrumented all
five bail sites in `_propagate_computed_reprs` to record which one each node last
hit, then reported the bail for every node still untyped at the end. CFG ops
(`Start Return Unwind If Proj Region Loop Mem MemStart`) are excluded — they
legitimately carry no repr. Positive control above confirms the instrumentation
discriminates.

### Corpus-wide (182 mdtest cases, real producer, real backend, real `lli`)

```
cases with JSON: 182   lowered+ran OK: 162   failed: 13

BAIL SITE                   on OK cases      on FAILED
NO_RULE                               3              7
```

**Exactly one bail site fires corpus-wide.** `JOIN_UNRANKABLE` (the trigger),
`SAME_MISMATCH`, `INPUT_UNTYPED` and `SUBSCRIPT_NO_ELEM_REPR` are all zero.

The per-case detail is the important part:

```
  FAIL conditional string append (.= guarded by a postfix if)   Call
  OK   L3 defined-or                                            DefinedOr
  OK   L3b defined-or undef-left                                DefinedOr
  FAIL R11 hash keys sorted order                               Call
  OK   R12 aliased element store (store via ref, read via name)  Ref
  FAIL Pragma with import list: compile-time GAP                Call
  FAIL F2 anonymous sub                                         Call
  FAIL F3 chained sub calls                                     Call
  FAIL F4 sub returning a list flattens into caller's list assign Call
  FAIL F7 list-assign of @_ into named params GAPs              Call
```

Two facts fall out, and they point in opposite directions:

1. **Every FAILED case is `Call`.** One op, one family.
2. **Three cases carry untyped nodes and lower and run perfectly** — `DefinedOr`
   ×2, `Ref` ×1. The backend does not need a repr on those; it handles them
   structurally.

Point 2 is the constraint that kills the obvious fix. See §C and §E.

### The 4 ring files and `fib`

```
=== fib ===                                   === cmdopt ===
value nodes: 14   untyped: 6                  value nodes: 210  untyped: 15
  NO_RULE:Call = 3                              SAME_MISMATCH:And:Bool,Int = 6
  NO_RULE:StashAccess = 1                       SAME_MISMATCH:Or:Bool,Int  = 6
  INPUT_UNTYPED:Add = 1                         NO_RULE:Xor = 2
  INPUT_UNTYPED:Phi = 1                         NO_RULE:PadAccess = 1

=== colon ===                                 === decl ===
value nodes: 24   untyped: 5                  value nodes: 36   untyped: 2
  NO_RULE:PadAccess = 2                         NO_RULE:StashAccess = 1
  SUBSCRIPT_NO_ELEM_REPR = 1                    NO_RULE:Call = 1
  NO_RULE:AnonSub = 1
  NEVER_REACHED_PROPAGATE = 1                 === package_block ===
                                              value nodes: 40   untyped: 2
                                                NO_RULE:StashAccess = 1
                                                NO_RULE:PadAccess = 1
```

### Verdict on F

**This is a campaign, not a slice — but a shallow one, and it has a spine.**

Distinct root causes, honestly enumerated:

| # | Cause | Where | Evidence |
|---|---|---|---|
| 1 | **`Call` result repr never computed for a recursive/unresolvable callee** | `_resolve_direct_calls`, JSON.pm:577-586 | fib ×3; all 7 corpus FAILs; decl |
| 2 | **Ops with no rule at all** — `PadAccess`, `StashAccess`, `Xor`, `AnonSub` | `%_COMPUTED_REPR` JSON.pm:882-911 | cmdopt, colon, decl, package_block |
| 3 | **`And`/`Or` `'same'` rule cannot reconcile `Bool` with `Int`** | JSON.pm:1100 | cmdopt ×12 |
| 4 | **`Subscript` over an unresolvable aggregate** | `_element_repr` JSON.pm:1154 | colon ×1 |
| 5 | **A node the propagation never visits** | — | colon ×1 |
| 6 | *(the commissioned trigger — reachable, never reached)* | JSON.pm:1105 | 0 occurrences |

Six holes, not one. But causes 1, 3 and 6 share a single mechanism, and that
mechanism is the finding:

> **The lattice has no total join, and stamping is write-once, so every rule must
> be pessimistic — it may only assign when it is already certain. A pessimistic
> rule has nowhere to put "I don't know yet", so it does the only thing it can:
> it skips silently.**

Cause 3 is exactly cause 6 wearing a different hat. `Bool` and `Int` have no
join because `%_REPR_RANK` covers only `Int < Num < Str`; at the `'join'` site
that silence is line 1105, at the `'same'` site it is line 1100. Cause 1 is the
same disease at the interprocedural scale: `_resolve_direct_calls` will only
stamp a `Call` when the callee's `Return` is *already* typed, so a recursive
callee — whose `Return` is a `Phi` over a base case and a recursive `Call` — can
never bootstrap. Write-once stamping forbids the standard fix (start at bottom,
iterate, widen), because widening requires re-stamping.

Cause 2 is genuinely unrelated: a missing table entry, nothing deeper.
Causes 4 and 5 are singletons and I did not chase them further.

---

## A. Is the orphaned engine reusable?

**It is not orphaned (see corrections), and for the SoN path the verdict is
REPLACE — with one narrow, genuinely valuable ADOPT.**

The 924 lines implement: *a single bottom-up pass over an Earley derivation tree
that looks up per-rule constants and searches subtrees for the nearest type tag.*
Against the SoN path's requirements it is missing, structurally:

- **No fixpoint, no worklist.** `grep -niE "fixpoint|worklist|iterate|unif"` over
  both files returns nothing.
- **No join.** Not in the semiring, and — critically — not in `TypeLibrary.pm`
  either. Verified: its complete API is `get_builtin, has_builtin,
  type_satisfies, type_bitset, is_subtype, narrow_type, get_binary_op,
  get_unary_op`. No `join`/`lub`/`meet`/`unify`.
- **No merge handling.** `TernaryExpression` returns `{ valid => true }` with no
  type (`TypeInferenceActions.pm:320-322`). There is no `Phi`, `If`, or loop
  handler anywhere. The production path treats precisely these as the centre of
  the problem (`Phi => 'join'`, JSON.pm:887).
- **No interprocedural inference.** `%_method_returns` is written but never read
  in production — `lookup_method_return` has no caller outside its own definition.
- **The tree walker has no visited set** (`TypeInference.pm:83-103`). It is
  correct only because its input is a tree. On a SoN graph with a loop Phi it
  does not degrade; it fails to terminate.

That last point is the mechanical form of "the data structures don't carry over"
— but the more damaging finding is that **there is no algorithm underneath worth
carrying**. Roughly 100-130 of the 924 lines are portable (~12%), and nearly all
of it is thin wrapping over `TypeLibrary`, whose content the production tables
already duplicate.

**Do not delete it.** It is the right shape for its actual job — Earley
disambiguation, where permissive-unknown and single-pass are correct — and
`Actions.pm` dies without it.

**The narrow ADOPT: `lib/Chalk/Grammar/Perl/TypeLibrary.pm`** (316 lines, *not*
part of the 924). It is graph-agnostic, has no Context dependency, is O(1) via
bitsets, is well tested, and its `Int <: Num <: Str` chain is already exactly what
`%_REPR_RANK` hardcodes. It is the one asset that would stop two divergent type
vocabularies being hand-maintained. It would need a `join` added (absent today)
and a vocabulary reconciliation first — `Slot` does not exist in it, and `Scalar`
means something incompatible on each side (§B).

---

## B. What is `Scalar` for?

**Measured — it is unreachable by construction, in both repos.**

The producer's lattice defines it (`SoN/IR/Stamp.pm:15-27`), with `Unknown` above
it as true top. But across **54 `Stamp->new` construction sites** in the producer:

```
     18 type => 'Int'        5 type => 'Undef'       1 type => 'Unknown'
     11 type => 'Str'        5 type => 'Num'         1 type => 'None'
      7 type => 'Boolean'    2 type => 'Object'      4 dynamic
```

`Scalar`: **zero**. And `%STAMP_TO_REPR` (JSON.pm:24-31) maps only the six
concrete types, so even `Unknown` and `None` would be dropped to `undef` at the
boundary. Chalk-side: **0** sites assign `representation => 'Scalar'`. Backend:
**15** die-guards refuse it.

My initial hypothesis — that the boundary drops a `Scalar` the producer knew
about — is **falsified**. Measured stamp inventory across fib + the 4 ring files:

```
STAMP (none) = 350   STAMP Str = 129   STAMP Boolean = 13
STAMP Int = 6        STAMP Undef = 5
```

350 of 503 nodes arrive with **no stamp at all**. The producer is not losing
`Scalar`; it never had it. The gap is upstream of the boundary.

There is also a **name collision that must be resolved before `Scalar` can mean
anything**. To the semiring, `Scalar` means "a scalar variable, contents unknown"
— its most common tag. To the backend, `Scalar` means "boxed SV*, cannot lower
runtime-free, GAP". Same string, opposite meanings, in one codebase.

**Answer: none of (i)/(ii)/(iii) as posed — it is currently (iii)-in-fact but
(ii)-by-design, and the 15 guards are already correct.** The guards are not
defending against a value that should not exist; they are the correctly-sited
loud failure for "inference produced top". What is missing is that **nothing ever
produces it**. Reading (i) — an explicit tracked dynamic type requiring a boxed
runtime — is a different and much larger project, and is squarely against the
runtime-free constraint the backend is built on.

The cheapest coherent reading: `Scalar` is *the result of a join that succeeded
but landed above the machine-lowerable region*. Under that reading the 15 guards
become live and correct, and the silent bails become `Scalar` assignments that
GAP loudly at lowering. That is a real design option, and it is §E option 3.

---

## C. What is the right failure model?

Today an untyped node GAPs at lowering via `_require_repr` (31 sites), whose own
comment says it "guards a present node whose representation field was never set,
which is always a TypeInference gap". The message reads:

```
die "GAP: $where reached LLVM backend with NO representation (undef) — "
  . "fix TypeInference so this node carries an explicit repr before lowering."
```

Two problems with this, one known and one not.

**Known: the error is far from the cause.** It names the lowering site, not the
node whose type could not be derived, and not the rule that declined.

**Not previously known, and it constrains everything: "untyped" is not an error
condition.** Measured — 3 corpus cases carry untyped nodes (`DefinedOr` ×2,
`Ref` ×1) and lower and run correctly. The backend does not require a repr on
every value node; it handles some structurally. `_require_repr` is therefore the
*correct* enforcement point in one specific respect: it fires only on nodes that
lowering actually reads. A loader-level "every value node must be typed"
assertion is not equivalent and would be **wrong** — it would redden at least 3
currently-green cases.

**So the failure model cannot be "untyped is fatal".** It has to be one of:

- **"This rule was asked for an answer and declined"** — loud at the bail, in the
  loader. Precise about cause, but fires on nodes nobody will ever ask about
  (the 3 green cases).
- **"This node is needed and has no type"** — what `_require_repr` already does.
  Correctly scoped, badly located.
- **"This node's type is top"** — an explicit `Scalar`, which converts a silent
  skip into a value that the existing 15 guards reject loudly at lowering. This
  keeps `_require_repr`'s correct scoping *and* records the cause, because a
  `Scalar` on the node says "inference ran and gave up here" rather than "nobody
  looked".

Only the third preserves both properties. Note it also needs a real join to
produce, which is why §B and §E converge.

**What can actually be enforced given write-once stamping:** very little that is
monotone. Write-once is not merely an implementation detail — it is what forces
every rule to be pessimistic, because a rule that guesses early can never be
corrected. Any option that wants optimistic iteration (which is what cause 1
needs) must relax write-once first, at least within the fixpoint.

---

## D. Is `undef` vs `Scalar` a real distinction?

**Yes, and it is exactly the distinction the code currently destroys.**

- `undef` = *no rule was applied* — the node was never visited, or the op has no
  entry, or a rule declined. Absence of an answer.
- `Scalar` = *a rule ran, joined its inputs, and the answer is top*. Presence of
  an answer that happens not to be lowerable.

These have different fixes. The first is a missing rule or an unvisited node; the
second is a genuine dynamic value needing a boxed representation or a GAP. Today
both present as `undef`, and the 31 `_require_repr` sites cannot tell them apart —
hence the message blaming "TypeInference", which on the executable path has never
run.

The pvm comparison is instructive here and is the strongest external evidence in
this report. pvm keeps **three** distinct things, not two:

- `None` (bit 31) — bottom, an unreachable branch.
- `Unknown` (= 0) — *no rule handled this node kind*. Silently dropped; a hole.
- `Scalar`/`Any` — *tracked, narrowable, joinable* top for a value whose type is
  not yet known.

And the payoff is measurable in its behaviour: for **variables** pvm never lands
on `Unknown` at all, because the sigil supplies a real lattice element as the
fallback (`infer.go:161-168`, `lookupNarrowedType` at `:705-711`). Guard
narrowing even promotes `Unknown` to top before intersecting, with the comment
*"Unknown means no type information — treat as Any (top type)"*
(`narrowing.go:129-135`).

Chalk has the `Scalar` element and never produces it, so it gets pvm's `Unknown`
behaviour — the silent hole — everywhere.

---

## E. The smallest slice

**Ground rules from the measurements.** Corpus floor is 161 (verified in
`son-corpus-wide.t:220`); executable gate 4/5. Three currently-green cases carry
untyped nodes, so any blanket loader-level assertion reddens the gate. And the
commissioned trigger fires zero times, so a slice built on it moves nothing.

Four options, honestly costed. **I am not recommending one; the choice depends on
whether the goal is diagnosis or capability.**

### Option 1 — Make the bails loud, scoped to nodes lowering actually reads
Record *why* each node was left untyped (the bail site + the input reprs), keep
it on the node, and have `_require_repr` report it instead of the generic
message.

- **Corpus risk: none.** `_require_repr`'s firing set is unchanged; only the
  message changes. The 3 green cases stay green because nothing asks them.
- **Payoff:** every one of the 7 failing corpus cases and all 4 ring files get an
  error naming the op and the rule that declined, at the node that lost the
  information.
- **Cost:** small. A diagnostic field plus a message change.
- **Honest limit:** this fixes *no* case. It is pure diagnosis. It is the only
  option here that is unambiguously a slice rather than a campaign, and it makes
  the other three cheaper to scope. It does not satisfy "loud at the point where
  information was lost" in the strict sense — the error still *surfaces* at
  lowering — but it now *names* that point.

### Option 2 — Give `Call` an optimistic fixpoint (attacks cause 1 only)
Let a `Call` to a recursive callee start at bottom and iterate: type the callee's
`Return` from the arms that *are* known (fib's base case is `Int`), stamp the
`Call`, re-propagate, repeat until stable.

- **Payoff: the largest by case count.** All 7 failing corpus cases are `Call`;
  `fib` and `decl` are `Call`. This is the single highest-yield cause.
- **Cost: high, and it is the one that breaks an invariant.** It requires
  relaxing write-once *within* the fixpoint, because optimistic iteration means
  widening a value already assigned. That invariant is currently load-bearing
  across ~635 lines of passes that assume a stamp is final. **Fact 7's "no pass
  invalidates downstream consumers of a stale value" is the whole risk**: widen a
  `Call` from `Int` to `Num` and every node already stamped from it is stale.
- **Corroborating evidence, and a warning:** pvm fails `fib` for *exactly this
  reason* and has no fixpoint either. Its probe p3 shows that recursion **with a
  base case in the same body** resolves in one round, because the recursive edge
  contributes the identity element — but its probe p4 (call before declaration)
  shows that one round is not a fixpoint. Do not mistake "fib works" for
  "recursion works".

### Option 3 — Make the join total; produce `Scalar` at the top
Add a real `join` (absent from `TypeLibrary`), so `Bool ⊔ Int` = `Scalar` rather
than a silent skip. Untypable nodes get `Scalar`; the existing 15 guards fire.

- **Payoff:** closes causes 3 and 6 *by construction* — there is no longer a
  "join undefined" case to skip at. Converts 12 silent skips in `cmdopt` into a
  loud, correctly-located GAP. This is the option that most directly honours the
  original instinct.
- **This is the pvm lesson, and it is the strongest architectural finding in this
  report.** pvm's join is `|` over a bitset and is therefore **total** — it
  always has an answer, worst case a wider union. Chalk's join is a rank lookup
  over a 3-element chain and is **partial** — which is precisely why it needs a
  `next` at all. The bail exists because the lattice is incomplete, not because
  the code is careless.
- **Cost: medium, and the vocabulary must be reconciled first.** `Scalar` means
  two incompatible things (§B); `Slot` is in neither lattice; `Code`/`List` are
  meaningless to the backend.
- **Corpus risk: low but non-zero** — `And`/`Or` currently leaves `Bool,Int`
  untyped, and the backend may today lower some of those structurally. Needs
  measuring before it is called safe.

### Option 4 — Adopt `TypeLibrary` as the single lattice
Unify `%_REPR_RANK`, `%STAMP_TO_REPR`, `%_SEED_REPR`, `%OP_REQUIRED_REPR` and
`%OP_PER_POSITION_REPR` onto one vocabulary.

- **Payoff:** removes the "nothing checks they agree" hazard (fact 6, confirmed:
  `%OP_REQUIRED_REPR` says `Add => 'Int'` while `%_COMPUTED_REPR` says
  `Add => 'join'`, which can yield `Str` — these have never been reconciled;
  `TypedInvariant` has no `lib/` consumer, so the disagreement is currently only
  visible to the corpus harness).
- **Cost: campaign-sized.** Prerequisite for option 3 done properly.
- **Not a first slice.**

### The honest shape of it

**Option 1 is the only true slice.** It is zero-corpus-risk, it makes the silence
loud, and it is the measurement instrument for everything else — after it lands,
the remaining causes report themselves by name instead of needing an instrumented
loader copy to find.

**Option 2 has the most payoff and the most risk**, and its risk is concentrated
in exactly the invariant (write-once) that makes the current design tractable.

**Option 3 is the one that matches the original instinct** and is the right
long-run architecture, but it is gated on a vocabulary reconciliation that is not
small.

Sequencing them 1 → 3 → 2 is defensible. So is 1 → 2 if the goal is capability
rather than correctness-of-diagnosis. What is *not* defensible is doing option 3
or 4 first and calling it a slice.

---

## Reproduction

Instrumented-loader probes (scratchpad, not committed):

```bash
D=/tmp/claude-1001/-home-perigrin-dev-chalk--claude-worktrees-pu/9124e70a-21cb-4b26-bf13-8d44ac903753/scratchpad
# copy loader, wrap each bail site to record $main::BAIL{$node->id}
cp lib/Chalk/IR/Serialize/JSON.pm $D/inst/Chalk/IR/Serialize/JSON.pm   # + 5 edits
$PERL -I$D/inst -Ilib -It/lib $D/probe2.pl       <wire.json>   # per-file bails
CHALK_G7_TEST=hostval $PERL -I$D/inst -Ilib -It/lib $D/probe_corpus2.pl   # corpus-wide
```

Bail sites instrumented, all in `_propagate_computed_reprs`:
`JSON.pm:1066` (SUBSCRIPT_NO_ELEM_REPR), `:1086` (NO_RULE), `:1094`
(INPUT_UNTYPED), `:1100` (SAME_MISMATCH), `:1105` (JOIN_UNRANKABLE — the trigger).

Corpus probe runs the real producer, the real `Target::LLVM->lower`, and real
`lli`, so "lowered+ran OK" is genuine execution, not a static check.

---

## What I could not confirm

- **Whether the full corpus gate is green at 161 right now.** I did not run
  `son-corpus-wide.t`; my 162/182 figure comes from my own probe, which composes
  cases differently from the gate (no preamble handling, no GAP-declared
  skipping, no behavior comparison) and is **not** the gate number. Do not quote
  162 as a gate figure.
- **Causes 4 and 5** (`SUBSCRIPT_NO_ELEM_REPR`, `NEVER_REACHED_PROPAGATE`, one
  occurrence each in `colon`) were not investigated beyond classification.
- **Whether the semiring/production divergence was deliberate.** The dates are
  suggestive — the semiring last changed substantively 2026-04-29, `TypeLibrary`
  2026-04-27, `Serialize/JSON.pm` 2026-08-04 — but "abandoned in favour of" and
  "stable because finished" cannot be distinguished from `git log` alone.
- **Option 3's corpus risk** was reasoned about, not measured. Whether the
  backend today lowers any `And`/`Or` node that the `'same'` rule leaves untyped
  needs a probe before option 3 is called low-risk.
- The Raku comparison named in the brief was **not** investigated; the pvm,
  Hindley-Milner and TypeScript/Flow comparisons were.
