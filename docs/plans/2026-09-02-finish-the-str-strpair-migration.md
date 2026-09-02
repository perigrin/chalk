# ABOUTME: %StrPair and %Str are the same type with different arity; finish collapsing them.
# ABOUTME: Measured scope, why it stalled, and the order that keeps each step verifiable.

# Finish the %Str / %StrPair migration

perigrin, 2026-09-02: "I thought we had deprecated %StrPair and replaced it
with only %Str" — half true, and the half that is not is a live hazard. The
VALUE type moved; the HEAP CELL did not.

## What is actually true today

Two types, and the code says outright that they are mid-flip
(`Context.pm:277-283`):

    @_STRPAIR_FIELDS = ( ptr i8*, len i64 )
        # NOTE: this is the BOXED HEAP CELL, deliberately still two fields.
        # The THREE-field %Str below is the VALUE type. They are being
        # reconciled; see the %Str block for why the value type moved first.

    @_STR_FIELDS     = ( ptr i8*, len i64, enc i32 )

So:

- **`%Str`** is the SSA VALUE type. It replaced the old "bare `i8*` plus a
  `_str_len_table` side channel" scheme, and **that table is gone** — the
  migration perigrin remembers really did happen, on the value side.
- **`%StrPair`** is what a Str looks like when BOXED into a `%Slot` payload:
  the payload word is a pointer to a heap cell.

## The measured difference is `enc`, and `enc` is DEAD

    grep -rn "_str_idx('enc')" lib/ --include=*.pm
      Context.pm:942:   ... insertvalue %Str $s1, i32 $enc, ... ; %Str.enc

ONE site, and it is a WRITE. Nothing reads index 2 of a `%Str` anywhere, and no
caller passes a non-default `enc` (measured: zero `enc =>` arguments in lib/).

**So the two types are functionally identical today**, and `%StrPair` is a
strict prefix of `%Str`. That is what makes finishing this mechanical rather
than a redesign: there is no behaviour to preserve on the third field, only a
layout to widen.

## Scope

    99 mentions across 2 files:  Context.pm 72, LLVM.pm 27
    ~18 boxing sites, ~13 unboxing sites
    10+ test files reference it by name

## Why it is safe to widen now (and was not before)

`t/bootstrap/ir/strpair-layout-single-source.t` exists FOR this step. Its own
prose:

    That is a live trap for the {ptr, len, enc} widening ... adding an i32
    makes the struct 24 bytes with padding, so the two hardcoded 16s would
    under-allocate and corrupt the heap. No corpus case would catch it --
    every corpus string is ASCII, so `enc` is always 0 and a short write may
    not visibly break anything.

Those hardcoded `malloc(i64 16)` sites are GONE (only a comment at
`Context.pm:264` still mentions them). Both allocation sites now compute
`$pair_bytes`, and `_sizeof_llvm_type` derives it from the type declaration, so
the emitted size cannot drift from the emitted struct. **The prerequisite the
test was written to guard is met.**

## Order

Each step is independently verifiable, and none of them is "rename 99 sites".

1. **Widen `@_STRPAIR_FIELDS` to three fields**, matching `%Str`. Sizes are
   derived, so allocations follow automatically. Every boxing site must write
   the third field; every unboxing site keeps reading indices 0 and 1 and is
   unaffected. Gate + IR suite here: this step alone should be behaviour-neutral,
   and if it is not, the size derivation is not as complete as measured.

2. **Make the boxing sites emit `%Str`** and delete `_strpair_type_decl`,
   `render_strpair_type_once`, `_need_strpair`, `_strpair_emitted`. At this
   point `%StrPair` is a second name for a type with identical layout, so the
   substitution is textual and the tests that pin the NAME are the ones to
   update.

3. **Delete the `_need_strpair` pre-scan plumbing** in `LLVM.pm` — the
   declaration-ordering machinery (the class-registry pre-scan, the post-class
   re-emit at I3) exists only because `%StrPair` is conditionally declared while
   `%Str` is declared UNCONDITIONALLY (`_emit_class_registry_ir`, "an unused type
   declaration is inert"). Collapsing the types removes the condition, and with
   it a whole class of "declared after first use" bugs.

4. **Give `enc` a reader, or delete it.** It is write-only today. If the
   encoding is going to carry non-ASCII (currently a tracked GAP), that is the
   step that makes it real; if not, a field nothing reads should not be in the
   layout. THIS IS A SEPARATE DECISION and does not block 1-3.

## What forced this to be written down

A fix for `classes/field-str-default` (a Str field reading back as undef)
needed the method-return path to box a Str into a Slot. Doing that with
`%StrPair` — the encoding the constructor already writes — added a FIFTH
producer of a type we intend to delete, and made 11 IR test files red because
the ABI now disagreed across three sites (field read, method return, call site).

The fix is right and the encoding is wrong. Step 3 above is what makes the same
fix a one-liner instead of a three-site ABI negotiation, which is the argument
for doing the migration first rather than after.

The WIP is stashed as `d5ebb065` ("strfield-wip"), not lost.
