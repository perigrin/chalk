# XS Target: Feature Class Redesign

## Problem

The XS target (`lib/Chalk/Bootstrap/Perl/Target/XS.pm`) generates blessed
hashref OO: `package` declarations, `our @ISA`, hand-rolled constructors
with `bless`, and field access via `hv_fetch`. This prevents the Chalk
optimizer from performing DCE, inlining, or whole-program analysis on
generated classes because the class structure is opaque at compile time.

Perl 5.42.0 provides a C API for the `feature class` system:
`class_setup_stash`, `class_add_field`, `class_seal_stash`, and
`ObjectFIELDS` for direct indexed field access. These APIs let us build
classes entirely from XS, giving the compiler full visibility into class
structure.

## Spike Results

Six spikes validated the approach (spike code in `/tmp/tmp.spike_hybrid2/`):

| Feature | Status | Mechanism |
|---------|--------|-----------|
| Class creation from C | Works | `class_setup_stash` + `class_seal_stash` with `PL_curstash` set |
| Field creation | Works | `class_prepare_initfield_parse` + `pad_add_name_pvs(padadd_FIELD)` |
| Constructor with params | Works | `class_seal_stash` auto-generates `new()`; shadow it for defaults |
| Field defaults | Works | Shadow `new()` XSUB applies defaults after auto `new()` allocates |
| `:reader` / `:writer` | Works | Generate accessor XSUBs using `ObjectFIELDS(SvRV(self))[index]` |
| Inheritance (`:isa`) | Works | `class_apply_attributes` with `OP_CONST "isa(ClassName)"` |
| `isa` operator | Works | Feature class objects support `$obj isa Foo` natively |
| Field mutation | Works | `sv_setsv` on `ObjectFIELDS` slots; visible across Perl/XS boundary |
| `dl_*` loading | Works | Bypasses DynaLoader; no `@ISA` pollution on sealed stashes |

## Design

### What the XS Target Emits

For each class, the target generates two files:

**`Foo.pm`** — A minimal loader stub:

```perl
use 5.42.0;
use utf8;
package Foo;
require DynaLoader;
my $so = "auto/Foo/Foo.so";  # path relative to @INC
my $libref = DynaLoader::dl_load_file($so, 0)
    or die "dl_load_file: " . DynaLoader::dl_error();
my $boot = DynaLoader::dl_find_symbol($libref, "boot_Foo")
    or die "dl_find_symbol: " . DynaLoader::dl_error();
DynaLoader::dl_install_xsub("Foo::_bootstrap", $boot, $so);
Foo->_bootstrap();
```

No `class` keyword, no `field`, no `method`. The `.pm` exists only so
`require Foo` finds something to load.

**`Foo.xs`** — The complete class definition and all methods:

```c
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

extern void Perl_class_setup_stash(pTHX_ HV *stash);
extern void Perl_class_seal_stash(pTHX_ HV *stash);
extern void Perl_class_prepare_initfield_parse(pTHX);
extern void Perl_class_apply_attributes(pTHX_ HV *stash, OP *attrlist);

static CV *Foo_original_new = NULL;

MODULE = Foo  PACKAGE = Foo

SV *
new(class, ...)
    SV *class
  CODE:
    /* Call auto-generated new() to allocate PVOBJ */
    /* Extract named params from @_ */
    /* Apply defaults for missing optional params */
  OUTPUT:
    RETVAL

SV *
name(self)
    SV *self
  CODE:
    RETVAL = newSVsv(ObjectFIELDS(SvRV(self))[0]);
  OUTPUT:
    RETVAL

SV *
greet(self)
    SV *self
  CODE:
    SV *name = ObjectFIELDS(SvRV(self))[0];
    RETVAL = newSVpvf("Hello, %s", SvPV_nolen(name));
  OUTPUT:
    RETVAL

BOOT:
{
    HV *stash = gv_stashpv("Foo", GV_ADD);
    HV *old_stash = PL_curstash;
    PL_curstash = stash;

    /* 1. Create class */
    Perl_class_setup_stash(aTHX_ stash);

    /* 2. Apply :isa if any */
    /*    OP *attr = newSVOP(OP_CONST, 0, newSVpvs("isa(Bar)")); */
    /*    OP *list = newLISTOP(OP_LIST, 0, attr, NULL);           */
    /*    Perl_class_apply_attributes(aTHX_ stash, list);         */

    /* 3. Add fields */
    Perl_class_prepare_initfield_parse(aTHX);
    pad_add_name_pvs("$name", padadd_FIELD, NULL, NULL);

    /* 4. Seal — generates auto new() */
    Perl_class_seal_stash(aTHX_ stash);

    /* 5. Grab auto new(), clear GV, install shadow */
    GV *gv = gv_fetchmethod(stash, "new");
    Foo_original_new = GvCV(gv);
    SvREFCNT_inc((SV*)Foo_original_new);
    GvCV_set(gv, NULL);
    newXS("Foo::new", XS_Foo_new, __FILE__);

    PL_curstash = old_stash;

    /* 6. eval_pv fallbacks for unsupported methods */
    /*    eval_pv("sub Foo::complex { ... }", TRUE); */
}
```

### BOOT Block Sequence

The BOOT block runs after ParseXS auto-installs XSUBs via `newXS_deffile`.
`class_seal_stash` then overwrites `new()` with its auto-generated
constructor. The BOOT block saves that auto constructor, clears the GV to
suppress the redefined warning, and re-installs the shadow `new()`.

```
ParseXS: newXS_deffile("Foo::new", XS_Foo_new)       # our XSUB
ParseXS: newXS_deffile("Foo::greet", XS_Foo_greet)    # our XSUB
BOOT:    class_setup_stash(stash)
BOOT:    class_prepare_initfield_parse + pad_add_name  # x N fields
BOOT:    class_seal_stash(stash)                       # overwrites new()
BOOT:    original_new = GvCV(gv)                       # save auto new()
BOOT:    GvCV_set(gv, NULL)                            # clear to avoid warning
BOOT:    newXS("Foo::new", XS_Foo_new)                 # re-install shadow
BOOT:    eval_pv("sub Foo::method { ... }")            # fallbacks
```

Other XSUBs (`greet`, `name`, etc.) survive `class_seal_stash` because
it only overwrites `new()`.

### Shadow Constructor

The shadow `new()` XSUB:

1. Calls the auto-generated `new()` with just the class name (no params).
   This allocates a `SVt_PVOBJ` with the correct number of field slots.
2. Iterates `@_` key-value pairs, matching keys to field indices via
   `strEQ` and assigning with `sv_setsv`.
3. Validates required params (croak if missing).
4. Applies defaults for optional params (`sv_setiv`, `sv_setpv`, etc.).

The compiler knows all params, indices, requirements, and defaults at
compile time. The constructor is pure mechanical codegen.

### Field Access

All field access uses indexed arrays instead of hash lookups:

```c
/* Old: hv_fetch on blessed hashref */
SV **svp = hv_fetch((HV*)SvRV(self), "name", 4, 0);

/* New: indexed ObjectFIELDS on PVOBJ */
SV *name = ObjectFIELDS(SvRV(self))[0];
```

Field indices follow declaration order, with parent fields first.
A class `Dog :isa(Animal)` where Animal has `$name` (index 0) gets
`$breed` at index 1.

### XS Loading

Each `.pm` uses the raw `dl_*` API to load its `.so`:

```perl
require DynaLoader;
my $libref = DynaLoader::dl_load_file($so, 0);
my $boot   = DynaLoader::dl_find_symbol($libref, "boot_Foo");
DynaLoader::dl_install_xsub("Foo::_bootstrap", $boot, $so);
Foo->_bootstrap();
```

This bypasses the DynaLoader OO layer, which pollutes `@ISA` and
conflicts with sealed class stashes. The `dl_*` functions are documented
in `perldoc DynaLoader` as the C-level primitives that `bootstrap()` wraps.

### Unsupported Methods: eval_pv Fallback

Methods the XS emitter cannot yet handle (coderef invocation, `isa`
operator in expressions, complex control flow) are emitted as Perl subs
via `eval_pv` in the BOOT block:

```c
eval_pv("sub Foo::complex_method {"
        "  my $self = shift;"
        "  ..."
        "}", TRUE);
```

Every class goes through the new path. No class uses the old bless-based
system. As the XS emitter learns new constructs, `eval_pv` methods
become XSUBs one at a time.

### Inheritance

The BOOT block sets inheritance via `class_apply_attributes` between
`class_setup_stash` and `class_seal_stash`:

```c
Perl_class_setup_stash(aTHX_ stash);

OP *attr = newSVOP(OP_CONST, 0, newSVpvs("isa(Animal)"));
OP *list = newLISTOP(OP_LIST, 0, attr, NULL);
Perl_class_apply_attributes(aTHX_ stash, list);

/* add fields, then seal */
```

`class_apply_attributes` sets `xhv_class_superclass`, configures `@ISA`,
and adjusts field index offsets so the child's fields start after the
parent's. `class_seal_stash` produces a constructor that allocates
enough field slots for both parent and child fields.

## Changes to Target/XS.pm

### Replace

| Current | New |
|---------|-----|
| `_emit_xs_class_definition`: `package` + `our @ISA` | BOOT block with `class_*` API calls |
| `_emit_xs_constructor`: `bless \%args, $class` | Shadow `new()` XSUB with param extraction + defaults |
| `_emit_xs_field_access`: `hv_fetch(hash, "name", ...)` | `ObjectFIELDS(SvRV(self))[index]` |
| `_emit_xs_method`: `(HV*)SvRV(self)` hash access | `SvRV(self)` dereference, field access by index |

### Add

| Function | Purpose |
|----------|---------|
| `_emit_xs_boot_block` | Class setup, fields, seal, method installation |
| `_emit_xs_loader_pm` | The minimal `dl_*` `.pm` stub |
| `_emit_xs_reader` | `:reader` accessor XSUB |
| `_emit_xs_writer` | `:writer` accessor XSUB |
| `_emit_xs_eval_fallback` | `eval_pv` for methods the emitter cannot handle yet |

### Remove

- All `hv_fetch` / `hv_store` field access patterns
- `our @ISA` generation
- `bless` constructor generation
- The blessed hashref assumption throughout

### Field Index Mapping

The IR tracks field declarations in order. The emitter builds a map from
field name to index, respecting inheritance: parent fields occupy indices
0 through N-1, child fields start at N. This matches the layout that
`class_prepare_initfield_parse` + `class_seal_stash` produce.

## Future: Single-SO Compilation

This design emits one `.xs` per class. A future revision compiles all
classes into a single `.xs` / `.so`, with a single BOOT block that
creates every class in dependency order. A tiny `Chalk.pm` stub calls
`dl_*` once to bootstrap the entire program.

This enables whole-program optimizations: cross-class DCE, method
inlining, and field layout optimization across the inheritance hierarchy.

## Forward Declarations

All `class_*` functions require `extern` forward declarations in the
`.xs` file because the convenience macros in `class.h` are guarded by
`#if defined(PERL_IN_CLASS_C)` and friends. The underlying
`Perl_class_*` symbols are exported from `libperl.so` and callable.

```c
extern void Perl_class_setup_stash(pTHX_ HV *stash);
extern void Perl_class_seal_stash(pTHX_ HV *stash);
extern void Perl_class_prepare_initfield_parse(pTHX);
extern void Perl_class_apply_attributes(pTHX_ HV *stash, OP *attrlist);
```

## PL_curstash Requirement

`class_setup_stash` and `class_seal_stash` read `PL_curstash` to
determine the package context. The BOOT block must save, set, and restore
`PL_curstash` around these calls:

```c
HV *old_stash = PL_curstash;
PL_curstash = stash;
/* ... class_setup_stash, fields, class_seal_stash ... */
PL_curstash = old_stash;
```

Without this, the auto-generated `new()` gets `CvSTASH` set to `main::`
and method dispatch fails with "Cannot invoke a method of 'main'".
