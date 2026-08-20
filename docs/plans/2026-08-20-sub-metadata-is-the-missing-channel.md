# Slice 2, re-scoped: the missing piece is a sub METADATA channel, not a node type

**Date:** 2026-08-20
**Status:** scoped, not started. Supersedes the ordering in
`docs/plans/2026-08-06-f3-call-as-memory-transformer-design.md` Slice 2.
**Measured on:** chalk `ddb54c62`, perl5-son `3047f35`.

## Why this doc exists

Slice 2 of the F3 design never started. Slices 0 (recursion GAP) and 1
(`program_mode`) shipped on 2026-08-06/07; 151 commits followed, **none touching
`_lower_call_direct`**. The story is distraction, not a decision: Slices 0 and 1
were the parts that *weren't* F3, they were cheap and moved the product gate
1/5 -> 4/5, and the design's own "what outranks all of this" section then gave
the next 151 commits a defensible reason to go elsewhere. Every one of those was
real work. Slice 2 was deferred to nowhere.

Re-opened at perigrin's direction. Everything below is re-measured on today's
HEAD; the August numbers are stale in F3's favour.

## What changed since August

- **The executable gate is saturated at 8/8.** The metric whose "0 programs
  unblocked" verdict de-prioritised F3 can no longer rank anything.
- **`fib` no longer fails with a call GAP.** It fails at
  `Add node has no representation` — a repr/typing failure, exactly as the v1
  refutation predicted. The call-shape blocker moved.
- **Package-scalar SSA landed** (Part H6), which narrowed `StashAccess` — but
  left `@_` on it.

## The finding that re-scopes the slice

Chalk recovers by SCANNING what the frontend already knew and discarded.

Measured — the producer's per-sub wire payload carries exactly one key:

    main::f top-level keys: fields, id, inputs, nodes, op, stash_name, var_name

`nodes`. No arity, no params, no return type, no `@_` usage. Meanwhile:

| field | where | populated? |
|---|---|---|
| `MOP::Sub::params` | `lib/Chalk/MOP/Sub.pm:13` | **never** |
| `MOP::Sub::return_type` | `lib/Chalk/MOP/Sub.pm:14` | **never** (every write in the tree is `TypeLibrary` builtins) |
| `SubInfo::params` | `lib/Chalk/IR/SubInfo.pm:9` | **never** |

**These are the receiving end of a channel that was never built.** That absence
is why `_seed_direct_call_arg_reprs` pattern-matches the callee graph for a
`shift`/`$_[0]`, and why the backend's arity check counts positional reads.

**Do not add another scan.** A "does this callee use `@_`" scan would join that
family, and this session already fixed a bug caused by exactly such a scan
bailing at a nested branch (`2026-08-20-nested-one-armed-if-is-not-a-modifier.md`).
The B::SoN CV walk knows the answer as it walks. Record it.

## `@_` is measured, and the vocabulary is inconsistent

Producer IR per spelling:

| shape | IR for `@_` |
|---|---|
| `shift` | `StashAccess(_)` — a real array source |
| `$_[0]` rvalue | `Constant("_")` + `Subscript` |
| `$_[0]` lvalue | `Constant("_")` + `Subscript` + `Assign` |
| `my ($a,$b) = @_` | **nothing — `@_` absent from the graph** |
| `scalar @_` | `Constant("_")` returned directly |

Three spellings for one array, one of them a string constant, one shape where it
vanishes. **A scan over this cannot be written reliably** — which is the second,
independent reason the fact belongs on metadata.

None of these silently miscompile today: all GAP in the backend. But they GAP via
the INLINER's arity guard, which disappears with the inliner.

## `StashAccess` has TWO contradictory roles

After H6 it was meant to be entry definitions only. It is not:

1. **Entry definition** — a name token for a value defined outside the unit. No
   value, folds away when constant.
2. **`@_`** — `_args_source` (`FromOptree.pm:4554`) builds
   `StashAccess(main,'_')`, described by the producer's own comment at `:1477`
   as *"a real array source rather than a name string."*

A name token and a value source, same node type, same `(main,'_')` key,
hash-consed. **`$_` and `@_` therefore share identity** — H6 explicitly routed
the implicit `$_` match subject through the binding map, and `@_` stayed behind.

The name is part of the damage: "StashAccess" reads as *symbol-table lookup*, so
anything needing a global reached for it. Under the real meaning, an argument
array obviously does not belong.

## "Already working" is coincidence, not coverage

Measured call shapes: no-arg, one-arg `shift`, one-arg `$_[0]`, effectful callee
all lower. Two+ args, recursion, and list return GAP.

That boundary is **not a feature ladder**. There is no direct-call
implementation — there is body substitution, which coincides with a call on the
easy shapes. Two `shift`s hash-cons because there is no frame to make them
distinct; `_seed_direct_call_arg_reprs` carries a `ponytail:` note admitting the
callee is stamped by the FIRST caller and shared across sites. Both are
substitution artifacts.

Consequence: **the green `subs` corpus cases are not evidence the call path is
right.** The August argument for keeping the inliner ("a fallback ships
exercised") rests on treating them as coverage. Retiring the inliner is what
makes them test call semantics at all.

## Calling convention: params by default, `@_` on demand

perigrin's decision, matching perl's NoSnails direction: **materialise `@_` only
if the sub uses it.** `@_` is the semantics; setting it up is an implementation
cost, and Chalk is L3 — "always materialise" imports perl's implementation into
the layer that is supposed to be ours.

Two corrections folded in:

- **`@_` is not sub-exclusive.** It is dynamically scoped to the innermost
  enclosing sub call; a bare block or `if` inside a sub sees the same one, file
  scope has its own (usually empty), and `goto &f` reuses the caller's. The
  top-level `__PROGRAM__` case needs a decided answer, not an accident.
- **Usage is a CALLEE property**, not a call-site decision. One `define` per sub;
  every call site conforms. (Return CONTEXT is per-call-site — a different axis,
  see below.)

## The MOP is a deliberate divergence from classic Sea of Nodes

perigrin: the MOP is one of the places Chalk differs from other SoN
implementations. Classic SoN (C2) is one flat graph per unit — declarations
dissolve into it, and per-sub facts live outside the IR in the VM. Chalk keeps a
MOP alongside the graph, which is why `Call.pm` can say codegen should "read the
callee's graph/params/return-type directly without going through the symbol
table at emit time."

That reframes every scan hit in this session. `_seed_direct_call_arg_reprs`, the
backend's arity check, the proposed `@_` scan, the three-spelling `@_`
vocabulary — **all are the flat-graph model asserting itself where the MOP
should have answered.** The B::SoN frontend skips the MOP layer entirely (the
loader builds a bare `$graphs{name}` hash of `Chalk::IR::Graph`), so facts that
should be metadata get recovered by pattern-matching the graph.

### Everything is a CLASS

perigrin's design call: rather than "everything is a package", everything is a
class. Packages and classes are synonymous in Perl, so the lean is free —
`sub f` at file scope genuinely lands in `main::`, and `class` in 5.38+ builds
on the same namespace machinery.

This is load-bearing here, not stylistic. It means **`main` is a class**, a
file-level sub is a sub of class `main`, and `MOP::Sub`'s REQUIRED `class` field
is already correct — nothing needs to become optional, and no second "unit"
metaobject is invented. The model stays total: there is no "top-level sub"
category.

### What `Call` actually carries (corrected by reading, not memory)

Two fields, deliberately split:

| field | holds | used for |
|---|---|---|
| `target` | "a MOP::Method/Sub handle" | method dispatch |
| `resolved_graph` | "the callee `Chalk::IR::Graph`" | direct sub calls |

`resolved_graph`'s own comment states the reason: *"a top-level sub is not a MOP
class method, so it rides here."* It is a **documented flat-graph fallback**,
adopted because a file-level sub had no metaobject to point at — not an
accident.

**Under everything-is-a-class that premise is simply false.** The field is not a
fallback to tolerate until something better exists; it is a fallback for a case
that does not exist in the model. Same root as the `class`-field problem and the
scans: one missing piece — a metaobject for file-level subs — with three
symptoms.

Note `target` itself has NO backend consumer today (measured in step 1 below).
That is a consequence of the inliner, not a reason to distrust the field.

## Ordering

### 1. B::SoN emits sub metadata; the loader replays it into the MOP

**Correction to an earlier claim in this doc.** I wrote that step 1 was "a
convergence onto an existing proven contract — `target` already works for method
dispatch." Measured, it does not:

| | count |
|---|---|
| `target` setters | **1** (`Bootstrap/Perl/Actions.pm:845`, self-hosted parser only) |
| `target` readers | **2**, both in that same file (a `next if defined` guard and a comment) |
| `target` reads anywhere in `lib/Chalk/Target/` | **0** |

perigrin's explanation, and it is the right one: **the backend still inlines, so
a resolved-callee handle has no consumer** — and `MOP::Sub` has no readers
because the B::SoN path bypasses the MOP entirely. Confirmed by contrast:
`MOP::Method` IS read by the backend (2 sites) because methods go through the
registry, while `MOP::Sub` is 0.

So `target` is not a dead field to be wary of reviving. It is a field **whose
consumer was never built because the inliner made one unnecessary** — the same
category as `MOP::Sub::params`. Waiting on the call path, not evidence against
it.

#### What already exists (measured — the gap is narrower than it looks)

- **`Chalk::MOP`'s ADJUST already seeds an implicit `main` class**, with the
  comment *"all code belongs to a class"* — perigrin's design principle already
  in the code. No new container is needed.
- **The loader already replays a MOP.** `_replay_classes` (`JSON.pm:1039`)
  builds a `Chalk::MOP`, declares each class in parent order, declares fields,
  and seals it.
- **The wire already has the slot.** `to_json($named_graphs, $classes)` accepts a
  classes section; `from_json` replays it when present.
- **The backend already reads the MOP for classes.**
  `_build_registry_from_mop` (`LLVM.pm:320`) takes structure from a SEALED
  `MOP::Class`/`MOP::Method`/`MOP::Field`.

**What is missing is subs, at every one of those points.** The producer emits no
sub metadata; `_replay_classes` declares fields and methods but never calls
`declare_sub`; and `_build_registry_from_mop` **deliberately skips `main`** —
*"never instantiated via `Call(new)`"*. That skip is correct for instantiation
and wrong for subs: `main` is never `new`'d, but its subs still need emitting.

#### The work

**1a — producer: emit a sub record.** For each named CV, `to_json`'s `$classes`
section gains a `subs` list under its owning class (`main` for a file-level
sub). Recorded from the CV walk, which already knows: `name`, arity/`params`,
and `uses_args` (whether the body touches `@_`). This is the metadata channel;
it is what removes the reason for every scan.

**1b — loader: `declare_sub`.** `_replay_classes` gains the sub arm, attaching
each sub's already-loaded graph to a `MOP::Sub` and populating `params` /
`uses_args`. Note `MOP::Sub` requires `class` — under everything-is-a-class that
is satisfied by `main`, unmodified.

**1c — backend: stop skipping `main` for subs.** `_build_registry_from_mop`
keeps skipping `main` for INSTANTIATION (still never `new`'d) but must emit its
subs. The narrow change is separating "is this class instantiable" from "does
this class have callables to emit."

**1d — `target` replaces `resolved_graph`.** Once a `MOP::Sub` exists per sub,
the Call carries the metaobject rather than a bare graph, and `Call.pm`'s
two-field split collapses to one. 12 `resolved_graph` sites across 3 files
(`Target/LLVM/Context.pm`, `IR/Node/Call.pm`, `IR/Serialize/JSON.pm`).

**Ordering within step 1 is strict:** 1d cannot land before 1a-1c, because
`resolved_graph` cannot be eliminated until there is a metaobject to BE the
target.

#### Acceptance

- A file-level `sub f { }` produces a `MOP::Sub` on the B::SoN path, reachable
  from the sealed MOP as a sub of class `main`.
- `MOP::Sub::params` and the new `uses_args` are populated from the wire, not
  derived by scanning any graph.
- `resolved_graph` is deleted; `grep -rn resolved_graph lib/` returns 0.
- Corpus gate holds at its floor with all four legs agreeing, coordinator-
  self-verified on committed HEAD.
- The nine green `subs` cases stay green — but note they do NOT prove the call
  path (see "already working is coincidence"); they only prove no regression.

### 2. Retire `Chalk::IR::SubInfo` in favour of `Chalk::MOP::Sub`

perigrin's call, and already the declared direction — the Info structs are
transitional and the standing note is "do not build new permanent consumers on
[them]". 15 files, ALL on the self-hosted parser path (`Bootstrap/Perl/`,
including the parked `Target/C.pm`); none on the B::SoN path, so this is
separable from (1) and (2).

### 3. `@_` off `StashAccess`

Its own source node, gated by `uses_args`. Removes the `$_`/`@_` collision and
leaves `StashAccess` with one role.

### 4. Rename `StashAccess` -> `EntryDef`, plus the sigil decision

Only after (2), when it means one thing — renaming a node with two contradictory
roles just relabels the confusion. ~45 chalk sites plus the producer.

`EntryDef` over `DeclareName`/`DeclareBinding`: the node does not CREATE a
binding, it names one defined outside that flows in. `Declare` puts authority in
the wrong place — close to the framing error that produced the slot families.
H6's prose already says "ENTRY DEFINITION", so code and doc converge.

**Sigil decision belongs here.** `(stash_name, var_name)` gives `(main,'_')` for
both `$_` and `@_`; even after `@_` moves off, `$g`/`@g`/`%g` are three
variables with one key. Add the field or consciously decide not to.

### 5. `define` + `call`, inliner OFF

Not a fallback at the GAP sites. Per "already working" above, leaving the
inliner on leaves the real path unexercised.

Reusable: `_emit_class_registry_ir` (`LLVM.pm:625-895`) emits per-method
`define`s; `_lower_call_method` (`Context.pm:6149/6166`) emits real `call`s.
A direct call is the simpler case — **do not propose building `define` emission
from scratch.** Symbol mangling is unnecessary (`@"main::f"`, proven on lli-15).

Caveat, unpriced: `_emit_class_registry_ir` is ~270 lines coupled to
`(i8* %self)`, vtables, and the class registry. **Measure what is genuinely
reusable before estimating.**

### 6. Return context — `wantarray` is return-type polymorphism

perigrin's framing: the same mechanism Haskell resolves via typeclass instance
selection on the return type (`read`, `mempty`, `pure`, `minBound`) and Rust via
traits (`parse::<i32>`, `Default::default`, `collect::<Vec<_>>`). The difference
is WHEN: Haskell/Rust statically, Perl dynamically via reflectable context.

Measured, perl 5.42 — the same sub, two contexts:

    sub ary1 { (1,2,3) }
    my $s = ary1();          # 3        (scalar: last element)
    join(":", ary1());       # 1:2:3    (list: all three)

Both spellings appear in `t/cmd/subval.t` on the same sub. This lands on
`MOP::Sub::return_type` — the field that already exists and is empty.

Then: list return (unblocks `t/cmd/for.t`, `t/cmd/subval.t`), then recursion
(`fib`, whose blocker is now repr typing, not calls).

## Out of scope, named so it is not an unlabelled deferral

- **`%ENV`** — the other `StashAccess` exemption (`:1477`). Filed OPEN, with no
  prejudged node type: after H6 there is no symbol-table-access category, and
  whether Chalk ever needs one is undecided (nothing in the subset does
  `*foo = sub{}` or symbolic refs). What is known: **`%ENV` flows BOTH
  directions** — reads are incoming values, writes are externally visible to
  `system()` and child processes. So it needs a memory/host-interface answer,
  not a naming one. Separate from slice 1; do not fold it in.
- The kill-set lattice (no consumer — see the F3 doc).
- `$_[0] = 23` alias-write (`t/cmd/subval.t:179`). Must GAP loudly.

## Verification

Corpus gate floor 214, four legs, **coordinator-self-verified on committed
HEAD** — never a subagent report. Cross-repo work serialised: no producer
version pin (`son-corpus-wide.t:17` resolves it as a live filesystem path).

**Completion test for the MOP work:** H7 says `_pkg_globals` / `_pkg_str_globals` /
`_pkg_num_globals` are dead code. Deleting them proves the SV-union model is
gone. Re-run H7's four probes on today's HEAD first — that claim was measured
2026-08-10 and this week has expired three premises.
