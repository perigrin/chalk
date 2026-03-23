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
boolean.c       → boolean.o       ─┐
earley.c        → earley.o        ─┤
structural.c    → structural.o    ─┼─→ link → chalk.so  (loaded with RTLD_GLOBAL)
filtercomposite.c → filtercomposite.o ─┤
...                                ─┘

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
/* XSUB.h is required even in .c files: on threaded perls it redefines
   aTHX to PERL_GET_THX, which is needed for the pTHX_/aTHX_ macros
   used in every function signature. */
#include "XSUB.h"

/* Field access macro — wraps ObjectFIELDS for readability */
#define CHALK_FIELD(self, idx) ObjectFIELDS(SvRV(self))[idx]

/* Perl 5.42 class C API is declared in proto.h (included via perl.h).
   No additional forward declarations needed here. */

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

All `_emit_xs_*` methods that emit C code for expressions, statements, and
method bodies move to C.pm and are renamed to `_emit_c_*`. This includes ~40
methods covering the full IR-to-C translation: expression emitters
(`_emit_c_expr`, `_emit_c_const_expr`, `_emit_c_binary_expr`,
`_emit_c_subscript_expr`, `_emit_c_method_call_expr`, etc.), statement emitters
(`_emit_c_if_stmt`, `_emit_c_for_stmt`, `_emit_c_return_stmt`, etc.), and the
top-level function emitter (`_emit_c_function`, extracted from
`_emit_xs_complex_method`'s body emission). Cross-class method calls simplify
to direct `classname_method(aTHX_ ...)` calls.

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
# Compilation flags MUST match how Perl was built (struct packing, ABI, etc.)
PERL_CFLAGS=$(perl -MConfig -e 'print "$Config{ccflags} -I$Config{archlib}/CORE"')

# 1. Compile C files into chalk.so
cc -shared -fPIC $PERL_CFLAGS \
    boolean.c earley.c structural.c ... \
    -o chalk.so

# 2. For each class, compile XS wrapper
xsubpp Boolean.xs > Boolean.c
cc -shared -fPIC $PERL_CFLAGS \
    Boolean.c -o Boolean.so
# No explicit -lchalk needed — symbols resolved at runtime via RTLD_GLOBAL
```

### Runtime Loading

`Chalk::Runtime` loads chalk.so first. chalk.so lives in
`auto/Chalk/Runtime/` under `@INC`, following standard XS module conventions:

```perl
package Chalk::Runtime;
use 5.42.0;
use utf8;
require DynaLoader;

# Search @INC for chalk.so (same pattern as current PM stubs)
my $so;
for my $inc (@INC) {
    my $try = "$inc/auto/Chalk/Runtime/chalk.so";
    if (-f $try) { $so = $try; last; }
}
die "Cannot find chalk.so in \@INC" unless $so;

# RTLD_GLOBAL makes C symbols visible to subsequently loaded .so files.
# 0x01 is RTLD_GLOBAL on Linux. For portability, use POSIX::RTLD_GLOBAL
# if available, or DynaLoader::dl_load_flags() | 0x01 as a Linux default.
my $flags = 0x01;  # RTLD_GLOBAL (Linux)
my $libref = DynaLoader::dl_load_file($so, $flags)
    or die "Cannot load chalk.so: " . DynaLoader::dl_error();
```

Each per-class `.pm` stub:

```perl
package Chalk::Bootstrap::Semiring::Boolean;
use 5.42.0;
use utf8;
require Chalk::Runtime;  # ensures chalk.so loaded first

# Search @INC for Boolean.so (same pattern)
my $so;
for my $inc (@INC) {
    my $try = "$inc/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.so";
    if (-f $try) { $so = $try; last; }
}
die "Cannot find Boolean.so in \@INC" unless $so;

my $libref = DynaLoader::dl_load_file($so, 0)
    or die "Cannot load Boolean.so: " . DynaLoader::dl_error();
my $boot = DynaLoader::dl_find_symbol($libref, "boot_Chalk__Bootstrap__Semiring__Boolean")
    or die "Cannot find boot symbol: " . DynaLoader::dl_error();
DynaLoader::dl_install_xsub("Chalk::Bootstrap::Semiring::Boolean::_bootstrap", $boot, $so);
Chalk::Bootstrap::Semiring::Boolean->_bootstrap();
```

### Development Workflow

Changed `boolean.c`? Rebuild:
```bash
cc -shared -fPIC $PERL_CFLAGS boolean.c earley.c ... -o chalk.so
# Only changed .c recompiles; all .o relink
```

Changed `Boolean.xs`? Rebuild just:
```bash
xsubpp Boolean.xs > Boolean.c && cc ... Boolean.c -o Boolean.so
```

Build orchestration lives in `script/build-chalk-so-generated`, not Module::Build.

### Error Handling

- **chalk.so load failure**: Fatal with descriptive `die` message. If chalk.so
  cannot be found in `@INC` or `dl_load_file` fails (missing symbols, ABI
  mismatch), the error propagates immediately.
- **Load ordering**: Enforced by `require Chalk::Runtime` in every per-class PM
  stub. Loading a per-class `.so` before chalk.so would cause unresolved
  symbols; the require chain prevents this.
- **Circular C dependencies**: Not a problem — all `.c` files are linked into
  one `chalk.so`, so mutual references between classes (e.g., `earley.c` calls
  `boolean_is_zero()` and `boolean.c` calls `earley_something()`) resolve at
  link time.
- **Partial compilation**: If a class cannot compile to C, it stays as pure
  Perl. The PM stub auto-require mechanism ensures pure Perl dependencies are
  loaded. No eval_pv fallback within compiled code.

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

### Phase 4: Direct Cross-Class Calls (Boolean-Only Benchmark)

Now that Earley and Boolean are both in `chalk.so`, change `earley.c` to call
`boolean_is_zero()` directly instead of `call_method("is_zero", ...)`.

This phase targets the **Boolean-only parsing path** used in benchmarks like
`earley-boolean.t`. Since we know the semiring type is Boolean at compile time,
we can hardcode direct calls. This proves the performance thesis: eliminating
`call_method` overhead in the hot loop delivers a measurable speedup.

The full production use case (FilterComposite wrapping 5 semirings) requires
polymorphic dispatch, which is Phase 5.

### Phase 5: Vtable Dispatch (Production Hot Path)

When FilterComposite needs to dispatch polymorphically across semirings in C,
add a vtable mechanism. Each semiring class registers a struct of function
pointers at init time:

```c
typedef struct {
    SV * (*is_zero)(pTHX_ SV *self, SV *value);
    SV * (*add)(pTHX_ SV *self, SV *a, SV *b);
    SV * (*multiply)(pTHX_ SV *self, SV *a, SV *b);
} chalk_semiring_vtable;
```

Earley extracts the vtable once at construction, then calls `vt->is_zero(...)`
in the hot loop — one pointer indirection + indirect function call, no Perl
bridge crossing. This is the same pattern as C++ vtables and Perl's internal
GvCV method cache.

Deferred until Phase 4 benchmarks confirm the architecture works and measured
data shows FilterComposite dispatch is the next bottleneck.

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
