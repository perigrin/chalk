# Num representation boundaries: where two Num-typed values would have to meet

Date: 2026-08-31
Scope: `lib/Chalk/Target/LLVM/Context.pm` (8930 lines), `lib/Chalk/Target/LLVM.pm` (1416 lines),
`lib/Chalk/Target/LLVM/ElaboratedContext.pm` (51 lines).
Method: measurement only. No file under `lib/` was modified.

## The question

The T2 functor maps Chalk types to machine types. Today `Num |-> double`, unconditionally
(`%_REPR_LLVM_TYPE`, Context.pm:1151-1173). Since Z is a subset of R, a Num whose values are
all integral could be represented by an integer machine type. If the functor became
per-site -- Num lowering as `i64` here and `double` there -- then two values that are BOTH
stamped `Num` could have different machine types, and every point where such values MEET
would need a conversion that does not exist today.

Unlike a type error, a missing conversion at such a meet does NOT fail loudly. LLVM would
reject `phi i64 [%a_double, ...]` -- but only when the two sides carry *different* LLVM
types in the same instruction. The dangerous cases are the ones where the backend
*derives* both sides' machine types from the same repr NAME and so cannot see the
disagreement at all. This document enumerates those.

## Headline answer

**A per-site Num representation is NOT feasible as a local change.** It requires a
whole-program agreement: one representation per Num-typed VALUE, decided once, before
lowering.

The blocking reason is not the phi count. It is that **three separate coherence checks in
the backend compare representation NAMES, and would all silently pass on a machine-type
disagreement**:

| Site | Check | What it compares | Behaviour if Num were per-site |
|---|---|---|---|
| Context.pm:7589 | vtable ABI cross-check | `$result_repr ne $abi_repr` | Two `Num`s pass. Call site reads i64 bits through a double slot -- the exact failure this guard was WRITTEN to catch (measured 2026-08-28: printed `1.48219693752374e-323` for perl's `3`). |
| Context.pm:3529 | `_shortcircuit_phi_repr` | `$lhs_repr eq $rhs_repr` | Two `Num`s pass. Emits `phi <one type>` over two arms of different machine types. |
| Context.pm:4796 | `_coerce_arm` | `$arm_repr ne $phi_repr` | Two `Num`s compare equal, so `_emit_coercion` is SKIPPED. The one conversion hook on the merge path is bypassed precisely when it is needed. |

Every one of these is a **name comparison standing in for a machine-type comparison**.
They are correct today only because the map from name to machine type is a total function
-- one repr, one machine type. Per-site Num breaks that function, and each of these three
becomes a silent-miscompile channel.

A fourth, structural, blocker: **`%Slot`'s tag is one `i8` keyed on the repr name**
(`%_SLOT_TAG`, Context.pm:410-421: `Num => 2`). Every boxed value records its reading as
that tag. There is no room in the encoding to say WHICH Num. See category 5.

## Category 1: phi nodes

38 `= phi ` emission sites in Context.pm (`grep -c "= phi "`), of which 3 are comment
lines (:3283, :3537, :3981) and one is a comment fragment (:6460). **34 real emission
sites.** Four more live in hand-written IR in LLVM.pm (:137, :138, :167, :168 -- the
whitespace-skip helper; fixed `i8*`/`i64`, no repr involvement).

Split by how the type is chosen:

### 1a. Type derived from a repr (7 sites) -- THE REAL SURFACE

| Line | Function | Type source |
|---|---|---|
| 2360 | `_emit_read_slot_as` | `_repr_to_llvm_type($to)` |
| 3706 | `_emit_shortcircuit_phi` (And/Or) | `_repr_to_llvm_type($repr)` from `_shortcircuit_phi_repr` |
| 3877 | `_lower_defined_or` | `_repr_to_llvm_type($phi_repr)` |
| 4634 | `ElaboratedContext` elab merge phi | `_repr_to_llvm_type($var_repr)` from `{_vd_repr}{$vd_id}` |
| 4780 | `ElaboratedContext` Region phi | `_repr_to_llvm_type($repr)` from the Phi node |
| 5443 | Loop header phi | `_repr_to_llvm_type($repr)` from the Phi node |
| 5498 | Loop-exit multi-exit merge phi | `_repr_to_llvm_type($repr)` from the Phi node |

These 7 are where "arms of a merge must agree on a machine type" actually lives. Each
emits ONE type string and applies it to N arms. Each would need, per arm: compare the
arm's machine type against the phi's, and insert `sitofp`/`fptosi` where they differ.

Only ONE of the seven has any such hook today: sites 4780 (and its pass-1 partner)
route arms through `_coerce_arm` (Context.pm:4791-4807), which calls `_emit_coercion`
into the ARM's block. That is structurally the right shape -- and it is gated on
`$arm_repr ne $phi_repr`, so it does nothing when both sides are `Num`.

The other six have **no per-arm conversion hook at all**. Sites 5443 and 5498 (loop phis)
are the most exposed: a loop-carried accumulator is exactly the shape that motivates
integral-Num (`my $s = 0; $s = $s + $x`), and the header phi's arms are the preheader
init and the back-edge value -- two independently lowered values.

### 1b. Type is a structural literal (27 sites) -- NOT representation decisions

`i64` loop counters and indices (:2196, :2198, :2218, :3073, :6518, :8148, :8184, :8261,
:8300, :8303), match/compare flags in `i1` (:3360, :8352), regex capture offsets
(:8354, :8356, :8363, :8365), string result pointer/length (:8763, :8765), and the
array/hash payload phis (:6249, :6256, :6269, :6449, :6588, :6597, :6608) which merge the
**raw i64 payload word** before unboxing. Plus the two `%Slot` aggregate phis (:6305,
:6634).

Per the brief's correction, these are correctly `i64`/`i1` regardless of any Chalk type
and must NOT be converted. Note particularly :6269 and :6608: these phi the raw payload,
and the `bitcast i64 ... to double` happens AFTER the merge (:6273, :6612). That ordering
is already representation-agnostic on the merge itself.

**Category 1 count: 7 sites needing per-arm agreement; 1 of the 7 has a conversion hook,
and that hook is name-gated.**

## Category 2: call boundaries

Two distinct mechanisms, with very different exposure.

### 2a. Method calls (vtable, indirect) -- 6 sites, HARD boundary

The return machine type is decided by `_method_fn_llvm_ret_type` (LLVM.pm:212-226), the
single authority. Consumers:

| Line | File | Role |
|---|---|---|
| 51 | Context.pm (`_method_fn_type`) | derives the fn-POINTER type: `<ret> (i8*)` |
| 700 | LLVM.pm | `define internal <ret> @Cls__method(i8*)` |
| 925 | LLVM.pm | same, for subs (behind `CHALK_EMIT_SUB_DEFINES`) |
| 1033 | LLVM.pm | `bitcast (<fntype>* @fn to i8*)` into the vtable global |
| 7616 | Context.pm | call-site `bitcast i8* %opaque to <fntype>*` |
| 7639 | Context.pm | the `call <ret> %typed_fn(i8* %obj)` itself |

There are NO argument types to reconcile: every method is `(i8*)` -- the invocant only.
Parameters ride as `:param` field stores (category 3). So the call boundary is a
**return-type-only** boundary.

The vtable slot is `i8*` and each fn pointer is bitcast into it individually
(LLVM.pm:1033), so an Int-returning and a Num-returning method on one vtable do not
collide -- this was measured and written up in the comment at Context.pm:7556-7575. That
comment's conclusion holds ONLY because repr determines machine type globally. The
guard that keeps it honest is:

```perl
if ($result_repr ne $abi_repr) {
    die "GAP: Call(method) '$method_name' node repr=$result_repr disagrees "
      . "with class '$class_name' vtable ABI return_repr=$abi_repr — "
      . "a mismatched indirect call would be silently wrong.";
}
```
Context.pm:7589-7593.

Its own comment (Context.pm:7539-7545) states the stakes exactly: *"The i8* fn-ptr bitcast
means lli ACCEPTS a mismatch — the silent-garbage channel."* Under per-site Num, node
repr `Num` and ABI repr `Num` compare equal while naming `i64` and `double`. lli accepts
it. This is a direct, verified-in-comment silent miscompile channel.

What it would need: compare `_method_fn_llvm_ret_type($result_repr)` against
`_method_fn_llvm_ret_type($abi_repr)` -- i.e. compare in the TARGET category, not the
source category. That is a one-line change *given* that the two sides can be resolved to
machine types independently, which is precisely what per-site Num denies: the repr name
`Num` would no longer determine the answer.

There is already one precedent for a boundary-honouring conversion here: Context.pm:7644,
where an ABI of `Scalar` (`%Slot`) is `extractvalue`'d down to the node's narrower repr.
Its comment states the governing rule: *"the callee has ONE emitted body at ONE machine
type."* That rule is the whole answer to the headline question, stated by the backend
about itself.

### 2b. Direct sub calls -- 0 boundary sites

`_lower_call_direct` (Context.pm:7087) **inlines**; it does not emit a `call`. Recursion
is a loud GAP (:7105). `CHALK_EMIT_SUB_DEFINES` is off by default (LLVM.pm:921). So a
direct call has no ABI: the callee body is lowered into the caller's blocks, and the
argument/return meeting points become ordinary value meets already counted in categories
1 and 3.

This is a **transitional property, not a durable one.** The comment at LLVM.pm:915-920
says define+call emission "becomes live in the step that retires the inliner (plan step
5)". When that lands, every sub gains a real ABI with real parameter types, and category
2 grows argument positions it does not have today. **COULD NOT CONFIRM** how many, since
the parameter-type emission does not exist to count.

**Category 2 count: 6 sites, one guard (7589) that would silently pass. Argument
positions: 0 today, unbounded after the inliner is retired.**

## Category 3: field stores and reads

Three functions, and they are explicitly documented as one encoding written from both
ends.

| Function | Line | Num behaviour |
|---|---|---|
| `_box_payload` | 6723 | `bitcast double %v to i64` (:6757) |
| `_unbox_payload_as` | 2370 | `bitcast i64 %p to double` (:2377) |
| `_store_field_payload` | 6819 | `bitcast <ty> %v to i64` where `<ty> = _repr_to_llvm_type($repr)` (:6867-6868) |

Call sites: `_box_payload` x6 (:2260, :3018, :3112, :5934, :6014 -- shared with cat. 4),
`_unbox_payload_as` x1 (:2338), `_store_field_payload` x3 (:2882, :6987, :7027).
**10 call sites over 3 definitions.**

The payload cell is ONE i64 (`%Slot` field 2). For Num it holds the double's BITS -- a
reinterpretation, not a conversion. The comment at Context.pm:6858-6866 is worth quoting
because it already anticipates a movable functor:

> REINTERPRET the bits into the cell; do NOT convert. `fptosi` would truncate 1.5 to 1 and
> silently lose the value [...] The machine type comes from `%_REPR_LLVM_TYPE` rather than
> being named here: what Num encodes AS is that table's decision and revisable per
> context, so a second literal at this site would be a parallel authority that could drift.
> Only the KIND of move -- a reinterpretation -- is fixed here.

`_store_field_payload` is therefore ALREADY functor-clean: it asks the table. `_box_payload`
(:6757) and `_unbox_payload_as` (:2377) are NOT -- they name `double` literally. Under a
per-site Num those two would silently disagree with `_store_field_payload`, which is the
one asking the table.

But even after fixing those two literals, the deeper problem stands: **box and unbox are
separated in time and space.** `_box_payload` runs at the store; `_unbox_payload_as` runs
at a read that may be in a different method. The only thing carried across is the i8 tag
(category 5), which records `Num` and not *which* Num. So the read cannot recover the
store's choice. A store as i64-Num read back as double-Num is a bit reinterpretation of an
integer -- exactly the `1.48219693752374e-323` failure class, but now at a field rather
than a vtable slot.

`_field_store_is_coherent` (Context.pm:6790) is the existing guard on this pair; its own
documentation says it checks the KIND (DIRECT vs BOXED), not the machine type. Two Nums
are both DIRECT, so it passes.

**Category 3 count: 3 definitions, 10 call sites, 2 hardcoded `double` literals; the
store/read pair is separated in time and carries no channel for a per-site choice.**

## Category 4: array/hash element stores and reads

Stores go through `_box_payload` -- already counted: :5934 (array element), :6014 (hash
value), :3018 / :3112 (Assign array-lvalue / hash-lvalue). Reads are OPEN-CODED rather
than going through `_unbox_payload_as`:

| Line | Path | Num arm |
|---|---|---|
| 6273 | `_lower_array_read` | `bitcast i64 %raw to double` |
| 6612 | `_lower_hash_read` | `bitcast i64 %raw to double` |

Both sit after a raw-`i64` payload phi (:6269, :6608), which -- as noted in 1b -- is the
right ordering: the merge is on the untyped word, and the interpretation happens once
after.

**These are the same encoding as category 3, implemented a third and fourth time.** The
`_box_payload` docstring (Context.pm:6714-6721) records that this duplication has already
caused a real bug once: *"They used to decide separately, and the ones that were not
exercised fell behind: a field could hold a Str [...] while an array element could not."*
The read side is still in the pre-consolidation state the write side was rescued from.

**Category 4 count: 2 read sites (6273, 6612) with hardcoded `double`, plus 4 store sites
sharing `_box_payload`. 4 total independent implementations of the Num<->i64 payload
encoding across categories 3+4 (box, unbox, store_field, and the two open-coded reads --
counting the two reads as one duplicated shape).**

## Category 5: the %Slot payload -- how a double survives one i64

Answer: **by bit reinterpretation, and it survives correctly today.**

`%Slot = { i1 defined, i8 tag, i64 payload }` (Context.pm:_SLOT_FIELDS / `_slot_type_decl`).
A double is exactly 64 bits, so `bitcast double -> i64` at the store and `bitcast i64 ->
double` at the read is lossless and round-trips exactly. The 5 bitcast sites:

```
2377: bitcast i64 %payload to double     ; _unbox_payload_as
6273: bitcast i64 %raw_pay to double     ; ArrayRead :Num
6612: bitcast i64 %raw_pay to double     ; HashRead :Num
6757: bitcast double %val to i64         ; _box_payload
6868: bitcast %num_ty %val to i64        ; _store_field_payload (via the table)
```

Verified by `grep -n "bitcast i64\|bitcast double"` -- exactly these 5, no others.

**The tag is the blocker.** `%_SLOT_TAG` (Context.pm:410-421) assigns `Num => 2`: one i8
value per representation NAME. The tag's stated job is to record *the reading the payload
carries* (`_slot_tag_for_repr`, Context.pm:451). Under a per-site Num, `Num => 2` no
longer determines a reading -- the same tag would mean "these 64 bits are a double" at one
store and "these 64 bits are an i64" at another, and `_emit_read_slot_as` (:2286) would
pick the wrong `_unbox_payload_as` arm with no way to detect it.

The tag table's own comment already states the invariant being broken:

> The vocabulary must be TOTAL over what `_box_payload` boxes. It boxes eight
> representations; a four-value table mapped five of them onto Undef, which makes a live
> heap pointer indistinguishable from an undefined cell -- **not a type error LLVM would
> catch, but a wrong value read at runtime.**

A per-site Num makes the tag non-total in exactly the same way: one tag value covering two
distinct readings.

Fixing this would mean either (a) splitting the tag -- `NumInt` and `NumFloat` as separate
tag values, which is admitting the two are different representations and not one Num; or
(b) widening the tag to carry a machine type alongside the reading. Both are changes to
the runtime cell layout, i.e. whole-program by construction: every store and every read in
every compiled unit must agree on the encoding.

**Category 5 count: 5 bitcast sites (sound today); 1 tag table that cannot express the
distinction.**

## Totals

| Category | Sites | Have a conversion hook | Notes |
|---|---|---|---|
| 1. phi (repr-derived) | 7 | 1 (`_coerce_arm`, name-gated) | 27 further phis are structural i64/i1 -- do not touch |
| 2. call boundaries | 6 | 1 (`extractvalue` for Scalar ABI, :7644) | guard :7589 compares NAMES; 0 argument positions today |
| 3. field store/read | 3 defs / 10 calls | `_field_store_is_coherent` (checks KIND only) | 2 hardcoded `double` |
| 4. array/hash elem | 2 reads + 4 stores | none | duplicates cat. 3's encoding |
| 5. %Slot payload | 5 bitcasts | n/a | tag table has one value for Num |

Cross-checks against the brief, all confirmed:
- 41 float-instruction matches in Context.pm (brief said "~40"). Confirmed.
- `_repr_to_llvm_type` call sites: the brief said 12. **I measure 8**, all in Context.pm
  (:2358, :3705, :3831, :4631, :4778, :5442, :5488, :6867), plus the definition at :4232
  and a comment header at :4069. Zero in LLVM.pm. **The brief's "12" could not be
  reproduced.** LLVM.pm reaches machine types through
  `_method_fn_llvm_ret_type` instead, which is a SECOND, parallel repr->machine-type
  authority (LLVM.pm:212) with its own literal chain -- and its own header comment records
  that it has already drifted from `_method_fn_type` once. That parallel authority is
  itself a finding: see below.

## Finding not in the brief: a second repr->machine-type authority

The brief names `%_REPR_LLVM_TYPE` (Context.pm:1151) as "the DECLARED authority". It is
not the only one. `_method_fn_llvm_ret_type` (LLVM.pm:212-226) answers the same question
-- repr to machine type -- from an independent literal chain:

```perl
return 'i64'      if !defined $repr || $repr eq 'Int';
return '%StrPair' if $repr eq 'Str';
return 'i1'       if $repr eq 'Boolean';
return 'double'   if $repr eq 'Num';
return 'i1'       if $repr eq 'Undef';
return '%Slot'    if $repr eq 'Scalar';
```

It disagrees with `%_REPR_LLVM_TYPE` for `Str` on purpose (`%StrPair` by value at an ABI
vs `%Str` as a value), so it is not simply a duplicate to delete. But it names `double`
for Num independently, and the comment block immediately above it (LLVM.pm:205-209)
records that this pair HAS already drifted:

> A SECOND copy of this function lived here and answered from its own literal chain. It
> had already drifted [...] Two functions with the same name in different packages is how
> that stayed invisible.

Any functor work must treat this as a second site of the same decision, or it will drift
a third time.

## Verdict: per-site or global?

**Global. One representation per Num-typed value, chosen once, before lowering.**

The argument is not "there are too many sites". 7 phis + 6 call sites + ~15 payload sites
is a tractable diff. The argument is that **the backend has no channel to carry a per-site
choice across the places where values meet**:

1. **The coherence checks compare names.** :7589, :3529, :4796 all treat "same repr name"
   as "same machine type". That equivalence IS the current functor being total. Per-site
   Num deletes the function and leaves three guards silently vacuous.

2. **The %Slot tag is one i8 per repr name.** A value stored into a field, array element,
   or hash value loses everything except its tag. If `Num` maps to two machine types, the
   tag no longer says which, and the read cannot recover it. This is a data-layout
   constraint, not a codegen one -- and it is shared by every compiled unit.

3. **The callee has ONE emitted body at ONE machine type.** The backend states this rule
   about itself at Context.pm:7649-7651, in the comment explaining why a refined node repr
   is honoured by unpacking AT the boundary rather than by calling at the narrower type. A
   method body is emitted once. If a Num-returning method could be i64 at one call site
   and double at another, there would have to be two bodies -- which is monomorphisation,
   a whole-program transformation by definition.

What IS feasible, and is a strictly smaller change: make the functor **explicit and
single-authority** without making it per-site. That is:

- Route the 2 hardcoded `double` literals in `_box_payload` (:6757) and
  `_unbox_payload_as` (:2377), and the 2 in the array/hash reads (:6273, :6612), through
  `_repr_to_llvm_type` -- exactly as `_store_field_payload` (:6867) already does, and for
  the reason its comment already gives.
- Route `_lower_binop_int`'s Num arm (:1818-1826) and `_lower_as_double` (:1840) through
  the table rather than naming `double`.
- Change the three name-comparisons (:7589, :3529, :4796) to compare machine types
  (`_repr_to_llvm_type($a) ne _repr_to_llvm_type($b)`). Under today's total functor this
  is behaviour-preserving; it is also the change that makes those guards keep working if
  the functor ever becomes non-total.
- Reconcile `_method_fn_llvm_ret_type` with `%_REPR_LLVM_TYPE` (or document the `Str`
  divergence as the sole intended difference).

After that, choosing a different global representation for Num -- or introducing a
genuinely separate repr for integral-Num, which is the honest way to express "this Num's
values are all in Z" -- becomes a change to ONE table plus the coercion arrows, which is
what "making the functor explicit" buys.

## What I could NOT verify

- **The composed-route miscompile was not re-measured here.** The brief reports
  `Int -> Num -> Str` yielding `1.23457e+14` against perl's `123456789012345` under lli 15.
  I did not re-run that probe; this document is a static enumeration. The claim is
  consistent with what I read (`_emit_coercion` Num->Str at Context.pm:2442+ and the `%g`
  formatting path), but I did not confirm it empirically.
- **Post-inliner call argument positions.** `CHALK_EMIT_SUB_DEFINES` is off and
  `_lower_call_direct` inlines, so there is no argument-passing ABI to count. The number
  of argument meeting points after "plan step 5" retires the inliner is unknown.
- **The brief's "12 calls to `_repr_to_llvm_type`".** I measure 8 calls plus 1 definition
  in Context.pm and 0 in LLVM.pm. Either the count included the definition and the
  `%_REPR_LLVM_TYPE`/`%_REPR_NO_MACHINE_TYPE` lookups inside it, or it was taken against a
  different revision. Flagged rather than reconciled.
- **Whether any producer currently emits two Num-stamped values that a per-site scheme
  would separate.** That is a question about the wire (perl5-son) and the TypeInference
  pass, not about the backend, and is out of this document's scope.
- **`_emit_coercion`'s full arm inventory.** I read the Num-relevant arms (Int<->Num,
  Boolean->Num, Undef->Num, Str->Num, and the Num->Str path referenced by the brief). I
  did not audit every arm of the function for machine-type literals.

## Files touched

`docs/research/2026-08-31-num-representation-boundaries.md` (this file, new).
Nothing under `lib/` was modified.
