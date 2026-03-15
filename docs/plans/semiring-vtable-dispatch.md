# Semiring Vtable Dispatch

## Problem

The semiring API is polymorphic by design — `$semiring->multiply()` dispatches
to the right implementation for Boolean, FilterComposite, or any future
semiring type. The XS compilation currently breaks this by either:

1. Using `call_method` (correct but slow — full Perl method resolution per call)
2. Hardcoding stash checks with `_impl_` direct calls (fast but destroys the
   polymorphic abstraction)

Neither approach is right. The stash check approach requires the codegen to
know all possible semiring types at compile time and generates dead fallback
branches.

## Solution: Function Pointer Vtable

Each compiled semiring class registers a vtable struct at BOOT time:

```c
typedef struct {
    SV* (*multiply)(pTHX_ SV* self, SV* left, SV* right);
    SV* (*add)(pTHX_ SV* self, SV* left, SV* right);
    SV* (*one)(pTHX_ SV* self);
    SV* (*zero)(pTHX_ SV* self);
    SV* (*is_zero)(pTHX_ SV* self, SV* value);
    SV* (*on_scan)(pTHX_ SV* self, SV* item, SV* alt_idx, SV* pos, SV* matched);
    SV* (*on_complete)(pTHX_ SV* self, SV* item, SV* alt_idx, SV* pos);
    SV* (*should_scan)(pTHX_ SV* self, SV* item, SV* alt_idx, SV* pos, SV* matched, SV* predicted);
    SV* (*on_skip_optional)(pTHX_ SV* self, SV* item, SV* alt_idx, SV* pos, SV* rule);
} semiring_vtable;
```

### Registration

Each class stores its vtable pointer in the object (e.g., as a magic or
an extra field). At BOOT time:

```c
static semiring_vtable _vt_filtercomposite = {
    .multiply = _impl_filtercomposite_multiply,
    .add      = _impl_filtercomposite_add,
    .one      = _impl_filtercomposite_one,
    // ...
};
```

### Dispatch

Earley's `_run_parse` fetches the vtable once at the start:

```c
semiring_vtable *vt = get_semiring_vtable(semiring_sv);
// ... in the inner loop:
SV *result = vt->multiply(aTHX_ semiring_sv, left, right);
```

One pointer dereference + indirect function call. No method resolution,
no stack manipulation, no scope enter/leave. Fully polymorphic.

## Why This Is Better

- **Preserves polymorphism**: any class that provides a vtable works
- **No compile-time type knowledge needed**: vtable is registered per-class
- **No dead fallback branches**: the function pointer IS the dispatch
- **Fast**: one indirection (same as C++ virtual methods)
- **Composable**: FilterComposite's vtable functions internally dispatch
  to their component vtables
- **Works with variable-size FilterComposite**: the 2-component BNF
  pipeline and 5-component Perl pipeline both provide vtables

## Precedent

This is exactly how C++ vtables work, and how Perl's internal method
cache (GvCV) optimizes dispatch — but without the overhead of the
full Perl method resolution protocol.

## Implementation Notes

- vtable pointer could be stored via Perl SV magic (sv_magicext)
- Or as an additional ObjectFIELDS slot (requires the class to declare it)
- Or looked up from a global hash keyed by SvSTASH pointer
- The simplest approach: hash from stash pointer to vtable struct, looked
  up once per parse in _run_parse, cached in a local variable
