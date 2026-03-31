# Generic Polymorphic Dispatch for Compiled Classes

**Date**: 2026-03-31
**Status**: Design
**Issue**: #678

## Problem

When Target/C.pm generates a `call_method("foo", ...)` call, it crosses the
Perl/C bridge: push args onto the Perl stack, invoke method dispatch, pop the
return value. Each crossing costs ~20 instructions. In FilterComposite's hot
loop, `is_zero` alone crosses the bridge 11+ times per parse position across
550,000+ positions — millions of wasted cycles.

Existing optimizations handle two cases:

1. **Self-call**: `$self->method()` becomes `${slug}_method(aTHX_ self, ...)`.
2. **Known-typed field**: `$field->method()` with `field_types` becomes
   `${target_slug}_method(aTHX_ field, ...)`.

Neither fires for FilterComposite's `$semirings` array. The field is `:param`
(type varies per instance), so the codegen cannot resolve a single target class
at compile time. Each element could be Boolean, Precedence, TypeInference,
Structural, or SemanticAction.

## Solution

Add a third dispatch tier to `_emit_method_call_expr`: **speculative
polymorphic dispatch**. When `compiled_class_metadata` contains classes that
implement the called method, emit a stash-compare chain with direct C calls
and a `call_method` fallback:

```c
HV *_stash = SvSTASH(SvRV(invocant));
if (_stash == _boolean_stash) {
    _mcr = boolean_is_zero(aTHX_ invocant, vi);
} else if (_stash == _precedence_stash) {
    _mcr = precedence_is_zero(aTHX_ invocant, vi);
} else if (_stash == _typeinference_stash) {
    _mcr = typeinference_is_zero(aTHX_ invocant, vi);
} else if (_stash == _structural_stash) {
    _mcr = structural_is_zero(aTHX_ invocant, vi);
} else if (_stash == _semanticaction_stash) {
    _mcr = semanticaction_is_zero(aTHX_ invocant, vi);
} else {
    _mcr = /* call_method fallback */;
}
```

The stash comparison is a single pointer compare per candidate — fast and
predictable. The `call_method` fallback preserves correctness for any
uncompiled class.

## When the Optimization Fires

All conditions must hold:

1. The invocant is **not** `self` (self-calls already dispatch directly).
2. The invocant is **not** a known-typed field via `field_types` (already
   dispatches directly).
3. The `$_method_dispatch` table did **not** already resolve this method
   (that handles unambiguous single-owner methods).
4. The method name appears in `compiled_class_metadata` for **at least one**
   compiled class.

This is the last tier — a fallback upgrade from generic `call_method` to
speculative direct calls. It requires no knowledge of the invocant's type
at compile time.

## Implementation

### 1. Method-to-candidates map

At codegen init (alongside `$_method_dispatch`), build a second map from
`compiled_class_metadata`:

```perl
# $_polymorphic_dispatch: method_name => [ { slug, class_name }, ... ]
# Unlike $_method_dispatch (single-owner only), this includes ALL compiled
# classes that implement the method, for use in stash-compare chains.
```

Methods already handled by `$_method_dispatch` (single-owner) are excluded —
that tier is cheaper (no stash compare needed).

### 2. Stash pointer statics

For each class in any polymorphic dispatch chain, emit:

```c
static HV *_boolean_stash = NULL;
```

Populate in `init_statics`:

```c
_boolean_stash = gv_stashpvn("Chalk::Bootstrap::Semiring::Boolean",
                              strlen("Chalk::Bootstrap::Semiring::Boolean"),
                              GV_ADD);
```

### 3. Dispatch emission in `_emit_method_call_expr`

After the existing dispatch tiers fail to match, check
`$_polymorphic_dispatch` for the method name. If candidates exist, emit
the stash-compare chain.

The chain preserves argument pre-evaluation (`_mca` temporaries for nested
`dSP` expressions) and the `call_method` fallback pattern from the existing
generic path.

### 4. Header includes

The generated `.c` file must `#include` headers for all classes referenced
in its polymorphic dispatch chains. These headers provide the function
prototypes (`boolean_is_zero`, etc.).

Track required headers alongside the dispatch map and emit them in the
`#include` block.

## What This Does Not Change

- No changes to FilterComposite's Perl source, IR, or grammar.
- No loop unrolling. The `for my $i (0..4)` loop remains; each iteration
  dispatches through the stash-compare chain instead of `call_method`.
- No special-casing for semirings. Any compiled class's methods become
  candidates.
- No changes to the existing self-call or known-typed-field dispatch tiers.

## Testing

1. **Codegen inspection**: generate C for FilterComposite, verify stash-compare
   chains appear for `is_zero`, `add`, `multiply`.
2. **Behavioral correctness**: compile and load FilterComposite via XS,
   verify parse results match pure-Perl.
3. **Fallback safety**: add a method call on an uncompiled class, verify
   `call_method` fallback fires.
4. **Benchmark**: time a full-semiring parse before and after; measure
   reduction in `call_method` count.

## Scope

This design covers only the polymorphic dispatch optimization. Loop unrolling
(replacing `for` over known-length arrays with sequential statements) is a
separate, independent optimization that can be layered on top later.
