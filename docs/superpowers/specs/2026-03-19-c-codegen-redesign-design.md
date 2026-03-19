# C Codegen Redesign: chalk.so + Thin XS Wrappers

## Problem

All XS compilation approaches so far suffer from Perl/C bridge overhead in hot
paths. `_run_parse` calls `is_zero()` 11+ times per iteration. Even when both
sides are compiled to C, the dispatch goes through Perl's `call_method` —
negating any XS speedup.

Multi-class XS (one giant .xs) was abandoned: no faster than pure Perl.
Per-class XS (separate .so per class) fixes compilation issues but not the
bridge problem.

**Root cause:** We leaned into the XS API as the implementation layer. XS is
glue, not an implementation language. Core logic belongs in C with direct
function calls.

## Architecture

```
boolean.c  → boolean.o  ─┐
earley.c   → earley.o   ─┤
scope.c    → scope.o    ─┼─→ link → chalk.so  (loaded with RTLD_GLOBAL)
context.c  → context.o  ─┤
...                      ─┘

Boolean.xs  → Boolean.so  ─┐
Earley.xs   → Earley.so   ─┼─→ thin XSUB wrappers (link against chalk.so symbols)
...         → ...          ─┘
```

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Field access | ObjectFIELDS | Keeps `feature class` compatibility; real win is eliminating `call_method`, not faster field access |
| Function signatures | SV* everywhere | Existing `_impl_` bodies already work with SV*; optimize selectively later |
| BOOT block | Lives in .xs | xsubpp generates scaffolding; class registration uses Perl API macros natural in XS; each .xs independently loadable |
| Linking | chalk.so + per-class XS .so | Allows recompiling single classes during development without rebuilding everything |
| Symbol resolution | RTLD_GLOBAL | chalk.so loaded first makes C symbols visible to subsequently loaded XS .so files |
| Headers | chalk.h (shared) + per-class .h (prototypes) | Minimizes recompilation on API changes; mirrors Perl core pattern |
| Codegen split | Target/C.pm + slimmed Target/XS.pm | C.pm owns implementation emission; XS.pm owns thin wrappers + BOOT |
| Polymorphic dispatch | Deferred | Direct calls for Boolean proof of concept; vtable dispatch layered on later when needed |
| Migration | Bottom-up from Boolean | Proves pipeline end-to-end on simplest class before tackling complex ones |

## Component Details

### chalk.h — Shared Boilerplate

Common header included by every `.c` file:

```c
#ifndef CHALK_H
#define CHALK_H

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* Field access macro — wraps ObjectFIELDS for readability */
#define CHALK_FIELD(self, idx) ObjectFIELDS(SvRV(self))[idx]

/* Forward declarations for Perl 5.42 class C API */
extern void Perl_class_setup_stash(pTHX_ HV *stash);
extern void Perl_class_prepare_initfield_parse(pTHX);
extern void Perl_class_set_field_defop(pTHX_ PADNAME *pn, OPCODE type, OP *defop);
extern void Perl_class_apply_field_attributes(pTHX_ PADNAME *pn, OP *attrdata);
extern void Perl_class_apply_attributes(pTHX_ HV *stash, OP *attrdata);
extern void Perl_class_add_ADJUST(pTHX_ HV *stash, CV *cv);

#endif
```

### Per-Class .c File (e.g., boolean.c)

```c
#include "chalk.h"
#include "boolean.h"

/* File-scope statics (regex, anon CVs) */
static SV *_rx_boolean_0 = NULL;

/* Implementation functions — non-static, exported from chalk.so */
SV * boolean_is_zero(pTHX_ SV *self, SV *value) {
    /* Body from current _impl_boolean_is_zero */
    /* Uses CHALK_FIELD(self, idx) for field access */
    /* Cross-class calls are direct: earley_some_func(aTHX_ arg) */
    ...
}

SV * boolean_add(pTHX_ SV *self, SV *a, SV *b) { ... }
SV * boolean_multiply(pTHX_ SV *self, SV *a, SV *b) { ... }
```

Key differences from current `_impl_` helpers:
- Functions are **non-static** (externally visible, exported from chalk.so)
- Naming: `boolean_is_zero` not `_impl_boolean_is_zero`
- File-scope statics live naturally in each `.c` — solves per-class scoping issue
- No XS macros except Perl API (SvTRUE, newSViv, ObjectFIELDS, etc.)

### Per-Class .h File (e.g., boolean.h)

```c
#ifndef CHALK_BOOLEAN_H
#define CHALK_BOOLEAN_H
#include "chalk.h"

SV * boolean_is_zero(pTHX_ SV *self, SV *value);
SV * boolean_add(pTHX_ SV *self, SV *a, SV *b);
SV * boolean_multiply(pTHX_ SV *self, SV *a, SV *b);

#endif
```

### Per-Class .xs File (e.g., Boolean.xs)

```c
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "boolean.h"

MODULE = Chalk::Bootstrap::Semiring::Boolean  PACKAGE = Chalk::Bootstrap::Semiring::Boolean

SV *
is_zero(self, value)
    SV *self
    SV *value
  CODE:
    RETVAL = boolean_is_zero(aTHX_ self, value);
  OUTPUT:
    RETVAL

SV *
add(self, a, b)
    SV *self
    SV *a
    SV *b
  CODE:
    RETVAL = boolean_add(aTHX_ self, a, b);
  OUTPUT:
    RETVAL

BOOT:
{
    HV *stash = gv_stashpv("Chalk::Bootstrap::Semiring::Boolean", GV_ADD);
    ENTER;
    Perl_class_setup_stash(aTHX_ stash);

    /* Field registration with defop (same as current) */
    /* ... :param, :reader, :writer attributes ... */

    /* ADJUST registration (if present) */

    LEAVE;  /* triggers seal_stash */
}
```

Key points:
- XSUBs are mechanical: take args from Perl stack, call C function, return result
- Zero lines of implementation code in XSUBs
- BOOT block unchanged from current approach
- Varargs handling for optional params stays in XSUB
- Includes `boolean.h` for function prototypes; linker resolves against chalk.so

### Target/C.pm — The C Emitter

New module that emits `.c` and `.h` files from IR.

**What moves from XS.pm to C.pm:**
- `_emit_xs_expr` → `_emit_c_expr` (already emits C, not XS)
- `_emit_xs_if_stmt`, `_emit_xs_for_stmt`, etc. → `_emit_c_*`
- `_emit_xs_complex_method` body emission → `_emit_c_function`
- `_emit_xs_method_call_expr` cross-class dispatch → simplified to direct `classname_method()` calls

**What stays in XS.pm:**
- XSUB wrapper generation (thin, mechanical)
- BOOT block emission (class registration, field defop, ADJUST)
- PM stub generation
- Build.PL generation

### Target/XS.pm — Slimmed Thin Wrappers

**What XS.pm no longer does:**
- No `_impl_` helper emission (C.pm's job)
- No expression/statement emission
- No forward declarations of static helpers
- No eval_pv fallback methods (if a method can't compile to C, it stays pure Perl)

## Build Pipeline

### Compilation

```bash
# 1. Compile C files into chalk.so
cc -shared -fPIC -I$(perl -MConfig -e 'print $Config{archlib}')/CORE \
    boolean.c earley.c scope.c ... \
    -o chalk.so

# 2. For each class, compile XS wrapper
xsubpp Boolean.xs > Boolean.c
cc -shared -fPIC -I$(perl -MConfig -e 'print $Config{archlib}')/CORE \
    Boolean.c -o Boolean.so
# No explicit -lchalk needed — symbols resolved at runtime via RTLD_GLOBAL
```

### Runtime Loading

`Chalk::Runtime` loads chalk.so first:

```perl
package Chalk::Runtime;
use 5.42.0;
use utf8;
require DynaLoader;

my $so = _find_so('chalk');
my $flags = DynaLoader::dl_load_flags() | 0x01;  # RTLD_GLOBAL
my $libref = DynaLoader::dl_load_file($so, $flags)
    or die "Cannot load chalk.so: " . DynaLoader::dl_error();
```

Each per-class `.pm` stub:

```perl
package Chalk::Bootstrap::Semiring::Boolean;
use 5.42.0;
use utf8;
require Chalk::Runtime;  # ensures chalk.so loaded first

my $so = _find_so('Boolean');
my $libref = DynaLoader::dl_load_file($so, 0) or die ...;
# ... bootstrap as current pm stubs do ...
```

### Development Workflow

Changed `boolean.c`? Rebuild:
```bash
cc -shared -fPIC ... boolean.c earley.c ... -o chalk.so
# Only changed .c recompiles; all .o relink
```

Changed `Boolean.xs`? Rebuild just:
```bash
xsubpp Boolean.xs > Boolean.c && cc ... Boolean.c -o Boolean.so
```

Build orchestration lives in the bootstrap script (evolved from
`script/bootstrap-xs-earley`), not Module::Build.

## Migration Path

### Phase 1: Boolean Proof of Concept

1. Create `Target/C.pm` by extracting expression/statement emitters from `Target/XS.pm`
2. Emit `boolean.c` + `boolean.h` from Boolean's IR
3. Write `chalk.h`
4. Emit thin `Boolean.xs` (just XSUB wrappers + BOOT)
5. Build `chalk.so` (containing just Boolean for now)
6. Build `Boolean.so` (thin wrapper)
7. Write `Chalk::Runtime` loader
8. Test: load Boolean via new pipeline, run existing Boolean tests

### Phase 2: Simple Semirings

Add Structural, SemanticAction, FilterComposite — the other 3 classes that
already compile to per-class XS. Mechanical: run C.pm on each, add their `.o`
to `chalk.so` link step, build each thin `.xs`.

### Phase 3: Complex Classes

Add Earley, Precedence, TypeInference — the 3 that currently fail per-class XS
due to regex static scoping. Each `.c` file has its own file-scope statics, so
the scoping issue resolves naturally.

### Phase 4: Direct Cross-Class Calls

Now that Earley and Boolean are both in `chalk.so`, change `earley.c` to call
`boolean_is_zero()` directly instead of `call_method("is_zero", ...)`. This is
where the performance win happens.

### Phase 5: Vtable Dispatch (When Needed)

When FilterComposite needs to dispatch polymorphically across semirings in C,
add the vtable mechanism. Deferred until measured data shows it matters.

### What Stays Working Throughout

- Current per-class XS pipeline remains intact as fallback
- Pure Perl classes continue to work (PM stub auto-require handles deps)
- Each phase is independently testable

## Testing Strategy

### Per-Phase Validation

- **Phase 1 (Boolean)**: Load Boolean via new pipeline. Run existing
  `t/bootstrap/earley-boolean.t` and Boolean-specific tests. Verify `is_zero`,
  `add`, `multiply` produce identical results to pure Perl. Compare performance
  on large file (XS.pm, 5821 lines).

- **Phase 2 (Simple semirings)**: Run full `t/bootstrap/*.t` suite with
  new-pipeline semirings loaded. Verify no behavioral change.

- **Phase 3 (Complex classes)**: Earley loaded via new pipeline. Run
  `t/bootstrap/earley-boolean.t` with XS Earley + XS Boolean. Parse a real file
  and verify identical parse results.

- **Phase 4 (Direct calls)**: Performance milestone. Benchmark `_run_parse` on
  large file with direct C calls vs `call_method`. Existing XS Boolean benchmark
  (5821 lines in ~1s) is the baseline.

### Correctness Invariant

At every phase, the existing test suite must pass identically. The C
implementation is a transparent optimization — behavior must not change.

### Build Validation

A test that compiles `chalk.so` from C files, builds a thin XS wrapper, loads
it, and calls a function through the Perl API. Validates the entire pipeline
end-to-end.

## What's Reusable from Current Codebase

- **IR → C emission logic**: The `_impl_` helper generation in Target/XS.pm
  already emits valid C for method bodies — this is the core of what C.pm needs
- **DepChaser**: Dependency resolution for determining which classes to compile
- **PM stub auto-require**: `_emit_pm_stub_with_deps` scans call_pv targets
- **XS codegen bug fixes**: Sigil stripping, sv_setsv void handling, __sv in BOOT
- **BOOT block class registration**: setup_stash, defop, ADJUST — reused as-is in .xs files

## Prior Art

- **Perl core**: `pp.c`, `sv.c` are plain C; `universal.c` + `.xs` files expose
  Perl API. The pattern we want is exactly how Perl's own internals work.
- **DBD::SQLite**: Wraps sqlite3.c (large C library) with XS glue
- **Class::XSAccessor**: C implementation of accessors, thin XS exposure
- **Cython**: Compiles Python-like code to C, generates thin wrapper layer
- **PyPy RPython → C**: Restricted subset to C, links into single library
