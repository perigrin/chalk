# Phase 1: Boolean Proof of Concept — C Codegen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the chalk.so + thin XS wrapper architecture end-to-end by compiling Boolean to a `.c` file, linking it into `chalk.so`, exposing it via a thin `.xs` wrapper, and loading it from Perl.

**Architecture:** Hand-craft `boolean.c` + `boolean.h` + `Boolean.xs` to validate the build pipeline end-to-end before building the automated C emitter. A build script compiles `chalk.so` from the `.c` file, then compiles the `.xs` wrapper separately. `Chalk::Runtime` loads `chalk.so` with `RTLD_GLOBAL`; the per-class `.so` resolves C symbols against it. The C emitter (`Target/C.pm`) that auto-generates these files from IR is the follow-up plan after this pipeline is validated.

**Tech Stack:** Perl 5.42.0, C (gcc/cc), xsubpp, DynaLoader, Perl class C API (ObjectFIELDS, class_setup_stash)

**Spec:** `docs/superpowers/specs/2026-03-19-c-codegen-redesign-design.md`

**Skills required:** `writing-perl-5.42.0`, `test-driven-development`, `writing-perl-xs`

**Key docs to read first:**
- `docs/superpowers/specs/2026-03-19-c-codegen-redesign-design.md` — full design spec
- `lib/Chalk/Bootstrap/Semiring/Boolean.pm` — the class being compiled (68 lines, 8 methods)
- `lib/Chalk/Bootstrap/Perl/Target/XS.pm` — existing XS codegen (5933 lines) — the source of extracted logic

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `c_src/chalk.h` | Shared C header: Perl API includes, `CHALK_FIELD` macro |
| `c_src/boolean.c` | Hand-crafted C implementation of Boolean semiring |
| `c_src/boolean.h` | Function prototypes for boolean.c |
| `c_src/Boolean.xs` | Thin XSUB wrapper + BOOT block for Boolean |
| `lib/Chalk/Bootstrap/Runtime.pm` | Loads `chalk.so` with `RTLD_GLOBAL`. Thin module — just DynaLoader calls. |
| `script/build-chalk-so` | Build orchestrator: compiles `.c` into `chalk.so`, `.xs` into per-class `.so` |
| `t/bootstrap/c-build-pipeline.t` | End-to-end: compile chalk.so, load Boolean, call methods from Perl |
| `t/bootstrap/c-runtime-loader.t` | Tests Chalk::Bootstrap::Runtime loading chalk.so |
| `t/bootstrap/c-boolean-integration.t` | C-backed Boolean with Earley parser integration |

---

## Task 1: Write chalk.h

The shared header included by all `.c` files. No dependencies — start here.

**Files:**
- Create: `c_src/chalk.h`

- [ ] **Step 1: Create c_src directory and write chalk.h**

```c
/* ABOUTME: Shared header for all Chalk C implementation files.
   ABOUTME: Includes Perl API, defines CHALK_FIELD macro for ObjectFIELDS access. */
#ifndef CHALK_H
#define CHALK_H

#include "EXTERN.h"
#include "perl.h"
/* XSUB.h is required even in .c files: on threaded perls it redefines
   aTHX to PERL_GET_THX, which is needed for the pTHX_/aTHX_ macros
   used in every function signature. */
#include "XSUB.h"

/* Field access macro — wraps ObjectFIELDS for readability.
   Usage: CHALK_FIELD(self, 0) to access field at index 0. */
#define CHALK_FIELD(self, idx) ObjectFIELDS(SvRV(self))[idx]

/* Perl 5.42 class C API is declared in proto.h (included via perl.h).
   No additional forward declarations needed here. */

#endif /* CHALK_H */
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
PERL_CFLAGS=$(perl -MConfig -e 'print "$Config{ccflags} -I$Config{archlib}/CORE"')
echo '#include "chalk.h"' > /tmp/chalk_test.c
echo 'void chalk_test(void) {}' >> /tmp/chalk_test.c
cc -c -fPIC $PERL_CFLAGS -I c_src /tmp/chalk_test.c -o /tmp/chalk_test.o
```
Expected: compiles with no errors

- [ ] **Step 3: Commit**

```bash
git add c_src/chalk.h
git commit -m "feat: add chalk.h shared header for C implementation files"
```

---

## Task 2: Write a hand-crafted boolean.c + boolean.h

Before building the C emitter, write the target output by hand. This gives us a concrete compilation target to validate the build pipeline, and later serves as the reference output for C.pm's codegen.

Boolean has 8 methods. For Phase 1, implement the core 3 that matter for performance: `is_zero`, `add`, `multiply`. The remaining 5 (`zero`, `one`, `on_scan`, `on_complete`, `should_scan`, `supports_leo`) are simple and can be added after the pipeline works.

**Files:**
- Create: `c_src/boolean.h`
- Create: `c_src/boolean.c`
- Test: `t/bootstrap/c-build-pipeline.t`

- [ ] **Step 1: Write the failing build/load test**

Create `t/bootstrap/c-build-pipeline.t`:

```perl
# ABOUTME: End-to-end test for chalk.so + thin XS wrapper build pipeline.
# ABOUTME: Compiles hand-crafted boolean.c into chalk.so, validates loading and calling.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Config;

# Skip guards
my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
plan skip_all => 'No C compiler available' unless $have_compiler;

my $tmpdir = tempdir(CLEANUP => 1);
my $perl = $^X;
my $archlib = $Config{archlib};
my $ccflags = $Config{ccflags};
my $cc = $Config{cc};
my $so_ext = $Config{dlext};  # 'so' on Linux

# === Test 1: boolean.c compiles to .o ===

my $c_src = 'c_src';
my $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$c_src $c_src/boolean.c -o $tmpdir/boolean.o 2>&1";
my $out = `$cmd`;
is($? >> 8, 0, 'boolean.c compiles to boolean.o') or diag("Compile failed: $out\nCommand: $cmd");

# === Test 2: boolean.o links into chalk.so ===

$cmd = "$cc -shared -fPIC $tmpdir/boolean.o -o $tmpdir/chalk.$so_ext 2>&1";
$out = `$cmd`;
is($? >> 8, 0, 'boolean.o links into chalk.so') or diag("Link failed: $out\nCommand: $cmd");

# === Test 3: chalk.so loads with RTLD_GLOBAL ===

ok(-f "$tmpdir/chalk.$so_ext", 'chalk.so exists');

# Load chalk.so via DynaLoader and verify it has our symbols.
# Write test to a file to avoid shell quoting issues.
my $load_script = "$tmpdir/load_test.pl";
open my $lfh, '>', $load_script or die "Cannot write $load_script: $!";
print $lfh <<"END_SCRIPT";
use 5.42.0;
require DynaLoader;
my \$libref = DynaLoader::dl_load_file("$tmpdir/chalk.$so_ext", 0x01);
if (\$libref) {
    print "LOADED\\n";
    my \$sym = DynaLoader::dl_find_symbol(\$libref, "boolean_is_zero");
    print defined \$sym ? "SYMBOL_FOUND\\n" : "SYMBOL_MISSING\\n";
} else {
    print "LOAD_FAILED: " . DynaLoader::dl_error() . "\\n";
}
END_SCRIPT
close $lfh;
$out = `$perl $load_script 2>&1`;
like($out, qr/LOADED/, 'chalk.so loads via DynaLoader');
like($out, qr/SYMBOL_FOUND/, 'boolean_is_zero symbol found in chalk.so');

done_testing;
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `perl -Ilib t/bootstrap/c-build-pipeline.t`
Expected: FAIL — `c_src/boolean.c` does not exist yet

- [ ] **Step 3: Write boolean.h**

Create `c_src/boolean.h`:

```c
/* ABOUTME: Function prototypes for Boolean semiring C implementation.
   ABOUTME: Included by other .c files that call boolean functions directly. */
#ifndef CHALK_BOOLEAN_H
#define CHALK_BOOLEAN_H
#include "chalk.h"

SV * boolean_zero(pTHX_ SV *self);
SV * boolean_one(pTHX_ SV *self);
SV * boolean_is_zero(pTHX_ SV *self, SV *value);
SV * boolean_multiply(pTHX_ SV *self, SV *left, SV *right);
SV * boolean_add(pTHX_ SV *self, SV *left, SV *right);
SV * boolean_on_scan(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *matched_text);
SV * boolean_on_complete(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *on_epoch_commit);
SV * boolean_should_scan(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *matched_text, SV *is_predicted);
SV * boolean_supports_leo(pTHX_ SV *self);

#endif /* CHALK_BOOLEAN_H */
```

- [ ] **Step 4: Write boolean.c**

Create `c_src/boolean.c`. This is a hand-crafted reference implementation
matching `lib/Chalk/Bootstrap/Semiring/Boolean.pm`:

```c
/* ABOUTME: C implementation of Boolean recognition semiring.
   ABOUTME: Provides zero, one, multiply, add with reference-based zero detection. */
#include "chalk.h"
#include "boolean.h"

/* File-scope static: the unique ZERO reference (an empty AV).
   Initialized lazily on first call to boolean_zero().
   NOTE: This is a process-global static. On threaded perls with multiple
   interpreters, this would need MY_CXT for per-interpreter storage.
   Acceptable for this single-interpreter proof of concept. */
static SV *_boolean_ZERO = NULL;

static SV * _get_zero(pTHX) {
    if (!_boolean_ZERO) {
        AV *av = newAV();
        _boolean_ZERO = newRV_noinc((SV*)av);
        /* No SvREADONLY — matches Perl Boolean.pm behavior where $ZERO = [] is mutable */
    }
    return _boolean_ZERO;
}

SV * boolean_zero(pTHX_ SV *self) {
    PERL_UNUSED_ARG(self);
    return _get_zero(aTHX);
}

SV * boolean_one(pTHX_ SV *self) {
    PERL_UNUSED_ARG(self);
    return &PL_sv_yes;
}

SV * boolean_is_zero(pTHX_ SV *self, SV *value) {
    PERL_UNUSED_ARG(self);
    SV *zero = _get_zero(aTHX);
    /* Reference equality: compare refaddr */
    if (!SvROK(value)) return &PL_sv_no;
    if (!SvROK(zero)) return &PL_sv_no;
    return (SvRV(value) == SvRV(zero)) ? &PL_sv_yes : &PL_sv_no;
}

SV * boolean_multiply(pTHX_ SV *self, SV *left, SV *right) {
    /* Sequence: if either is zero, result is zero */
    if (SvTRUE(boolean_is_zero(aTHX_ self, left))) return _get_zero(aTHX);
    if (SvTRUE(boolean_is_zero(aTHX_ self, right))) return _get_zero(aTHX);
    return &PL_sv_yes;
}

SV * boolean_add(pTHX_ SV *self, SV *left, SV *right) {
    /* Alternative: if either is non-zero, result is non-zero */
    if (!SvTRUE(boolean_is_zero(aTHX_ self, left))) return &PL_sv_yes;
    if (!SvTRUE(boolean_is_zero(aTHX_ self, right))) return &PL_sv_yes;
    return _get_zero(aTHX);
}

SV * boolean_on_scan(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *matched_text) {
    PERL_UNUSED_ARG(alt_idx);
    PERL_UNUSED_ARG(pos);
    PERL_UNUSED_ARG(matched_text);
    /* multiply(item->{value}, one()) */
    HV *item_hv = (HV*)SvRV(item);
    SV **val_ptr = hv_fetchs(item_hv, "value", 0);
    SV *item_value = val_ptr ? *val_ptr : &PL_sv_undef;
    return boolean_multiply(aTHX_ self, item_value, boolean_one(aTHX_ self));
}

SV * boolean_on_complete(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *on_epoch_commit) {
    PERL_UNUSED_ARG(self);
    PERL_UNUSED_ARG(alt_idx);
    PERL_UNUSED_ARG(pos);
    PERL_UNUSED_ARG(on_epoch_commit);
    /* Return item->{value} unchanged */
    HV *item_hv = (HV*)SvRV(item);
    SV **val_ptr = hv_fetchs(item_hv, "value", 0);
    return val_ptr ? *val_ptr : &PL_sv_undef;
}

SV * boolean_should_scan(pTHX_ SV *self, SV *item, SV *alt_idx, SV *pos, SV *matched_text, SV *is_predicted) {
    PERL_UNUSED_ARG(self);
    PERL_UNUSED_ARG(item);
    PERL_UNUSED_ARG(alt_idx);
    PERL_UNUSED_ARG(pos);
    PERL_UNUSED_ARG(matched_text);
    PERL_UNUSED_ARG(is_predicted);
    return &PL_sv_yes;
}

SV * boolean_supports_leo(pTHX_ SV *self) {
    PERL_UNUSED_ARG(self);
    return &PL_sv_yes;
}
```

- [ ] **Step 5: Run the build pipeline test**

Run: `perl -Ilib t/bootstrap/c-build-pipeline.t`
Expected: All tests PASS — boolean.c compiles, links, loads, symbol found

- [ ] **Step 6: Commit**

```bash
git add c_src/boolean.h c_src/boolean.c t/bootstrap/c-build-pipeline.t
git commit -m "feat: hand-crafted boolean.c + build pipeline test"
```

---

## Task 3: Write thin Boolean.xs wrapper + BOOT

Build the thin XS wrapper that exposes Boolean's C functions to Perl via
XSUBs, with a BOOT block that registers the class with Perl's `feature class`
C API.

**Files:**
- Create: `c_src/Boolean.xs`
- Modify: `t/bootstrap/c-build-pipeline.t` — add XS compilation + method call tests

- [ ] **Step 1: Add failing tests for XS wrapper compilation and method calls**

Append to `t/bootstrap/c-build-pipeline.t`:

```perl
# === Test 4: Boolean.xs compiles via xsubpp + cc ===

# Find xsubpp
my $xsubpp = "$Config{privlibexp}/ExtUtils/xsubpp";
# Also need typemap
my $typemap = "$Config{privlibexp}/ExtUtils/typemap";

# Run xsubpp
make_path("$tmpdir/auto/Chalk/Bootstrap/Semiring/Boolean");
$cmd = "$perl $xsubpp -typemap $typemap c_src/Boolean.xs > $tmpdir/Boolean.c 2>&1";
$out = `$cmd`;
is($? >> 8, 0, 'xsubpp processes Boolean.xs') or diag("xsubpp failed: $out");

# Compile the xsubpp output
$cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$c_src $tmpdir/Boolean.c -o $tmpdir/Boolean.o 2>&1";
$out = `$cmd`;
is($? >> 8, 0, 'Boolean.c compiles to Boolean.o') or diag("Compile failed: $out");

# Link into Boolean.so
$cmd = "$cc -shared -fPIC $tmpdir/Boolean.o -o $tmpdir/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext 2>&1";
$out = `$cmd`;
is($? >> 8, 0, 'Boolean.o links into Boolean.so') or diag("Link failed: $out");

# === Test 5: Load chalk.so + Boolean.so and call methods ===
# Write test to a file to avoid shell quoting issues.

my $method_script = "$tmpdir/method_test.pl";
open my $mfh, '>', $method_script or die "Cannot write $method_script: $!";
print $mfh <<"END_SCRIPT";
use 5.42.0;
use utf8;
require DynaLoader;

# Load chalk.so with RTLD_GLOBAL
my \$chalk = DynaLoader::dl_load_file("$tmpdir/chalk.$so_ext", 0x01)
    or die "chalk.so: " . DynaLoader::dl_error();

# Load Boolean.so
my \$bool_so = "$tmpdir/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext";
my \$libref = DynaLoader::dl_load_file(\$bool_so, 0)
    or die "Boolean.so: " . DynaLoader::dl_error();

# Bootstrap the XS module
my \$boot = DynaLoader::dl_find_symbol(\$libref, "boot_Chalk__Bootstrap__Semiring__Boolean")
    or die "boot symbol: " . DynaLoader::dl_error();
DynaLoader::dl_install_xsub(
    "Chalk::Bootstrap::Semiring::Boolean::_bootstrap", \$boot, \$bool_so);
Chalk::Bootstrap::Semiring::Boolean->_bootstrap();

# Test: create instance and call methods
my \$b = Chalk::Bootstrap::Semiring::Boolean->new();
my \$zero = \$b->zero();
my \$one = \$b->one();

# is_zero on zero value -> true
die "is_zero(zero) should be true" unless \$b->is_zero(\$zero);
# is_zero on one value -> false
die "is_zero(one) should be false" if \$b->is_zero(\$one);
# add(zero, zero) -> zero
die "add(z,z) should be zero" unless \$b->is_zero(\$b->add(\$zero, \$zero));
# add(zero, one) -> non-zero
die "add(z,o) should be non-zero" if \$b->is_zero(\$b->add(\$zero, \$one));
# multiply(one, one) -> non-zero
die "mul(o,o) should be non-zero" if \$b->is_zero(\$b->multiply(\$one, \$one));
# multiply(zero, one) -> zero
die "mul(z,o) should be zero" unless \$b->is_zero(\$b->multiply(\$zero, \$one));

print "ALL_METHODS_OK\\n";
END_SCRIPT
close $mfh;
$out = `$perl $method_script 2>&1`;
like($out, qr/ALL_METHODS_OK/, 'Boolean methods work through chalk.so + thin XS wrapper')
    or diag("Method test output: $out");
```

- [ ] **Step 2: Run to verify it fails**

Run: `perl -Ilib t/bootstrap/c-build-pipeline.t`
Expected: New tests FAIL — `c_src/Boolean.xs` does not exist

- [ ] **Step 3: Write Boolean.xs**

Create `c_src/Boolean.xs`:

```c
/* ABOUTME: Thin XS wrapper for Boolean semiring C implementation.
   ABOUTME: XSUBs delegate to boolean_*() functions in chalk.so. */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "boolean.h"

MODULE = Chalk::Bootstrap::Semiring::Boolean  PACKAGE = Chalk::Bootstrap::Semiring::Boolean

SV *
zero(self)
    SV *self
  CODE:
    RETVAL = boolean_zero(aTHX_ self);
  OUTPUT:
    RETVAL

SV *
one(self)
    SV *self
  CODE:
    RETVAL = boolean_one(aTHX_ self);
  OUTPUT:
    RETVAL

SV *
is_zero(self, value)
    SV *self
    SV *value
  CODE:
    RETVAL = boolean_is_zero(aTHX_ self, value);
  OUTPUT:
    RETVAL

SV *
multiply(self, left, right)
    SV *self
    SV *left
    SV *right
  CODE:
    RETVAL = boolean_multiply(aTHX_ self, left, right);
  OUTPUT:
    RETVAL

SV *
add(self, left, right)
    SV *self
    SV *left
    SV *right
  CODE:
    RETVAL = boolean_add(aTHX_ self, left, right);
  OUTPUT:
    RETVAL

SV *
on_scan(self, item, alt_idx, pos, matched_text)
    SV *self
    SV *item
    SV *alt_idx
    SV *pos
    SV *matched_text
  CODE:
    RETVAL = boolean_on_scan(aTHX_ self, item, alt_idx, pos, matched_text);
  OUTPUT:
    RETVAL

SV *
on_complete(self, item, alt_idx, pos, ...)
    SV *self
    SV *item
    SV *alt_idx
    SV *pos
  CODE:
    SV *on_epoch_commit = items > 4 ? ST(4) : &PL_sv_undef;
    RETVAL = boolean_on_complete(aTHX_ self, item, alt_idx, pos, on_epoch_commit);
  OUTPUT:
    RETVAL

SV *
should_scan(self, item, alt_idx, pos, matched_text, is_predicted)
    SV *self
    SV *item
    SV *alt_idx
    SV *pos
    SV *matched_text
    SV *is_predicted
  CODE:
    RETVAL = boolean_should_scan(aTHX_ self, item, alt_idx, pos, matched_text, is_predicted);
  OUTPUT:
    RETVAL

SV *
supports_leo(self)
    SV *self
  CODE:
    RETVAL = boolean_supports_leo(aTHX_ self);
  OUTPUT:
    RETVAL

BOOT:
{
    HV *stash = gv_stashpv("Chalk::Bootstrap::Semiring::Boolean", GV_ADD);
    HV *old_stash = PL_curstash;
    PL_curstash = stash;
    ENTER;
    Perl_class_setup_stash(aTHX_ stash);

    /* Boolean has no fields, no ADJUST — just seal the class */

    LEAVE;  /* triggers seal_stash via SAVEDESTRUCTOR_X */
    PL_curstash = old_stash;
}
```

Note: Boolean has no fields (`:param`, etc.) and no ADJUST block. The `$ZERO`
static lives in `boolean.c` as a file-scope variable, not as a Perl field.
The BOOT block just registers the class and seals it.

- [ ] **Step 4: Run the tests**

Run: `perl -Ilib t/bootstrap/c-build-pipeline.t`
Expected: All tests PASS — XS compiles, links, loads, methods return correct values

- [ ] **Step 5: Commit**

```bash
git add c_src/Boolean.xs t/bootstrap/c-build-pipeline.t
git commit -m "feat: thin Boolean.xs wrapper + end-to-end build pipeline test"
```

---

## Task 4: Write Chalk::Runtime loader

The module that loads `chalk.so` with `RTLD_GLOBAL` so per-class XS `.so`
files can resolve C symbols against it.

**Files:**
- Create: `lib/Chalk/Bootstrap/Runtime.pm`
- Test: `t/bootstrap/c-runtime-loader.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/c-runtime-loader.t`:

```perl
# ABOUTME: Tests Chalk::Bootstrap::Runtime loading chalk.so with RTLD_GLOBAL.
# ABOUTME: Validates that C symbols are visible to subsequently loaded .so files.
use 5.42.0;
use utf8;
use Test::More;
use Config;

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
plan skip_all => 'No C compiler available' unless $have_compiler;

# Build chalk.so into a temp location
use File::Temp qw(tempdir);
my $tmpdir = tempdir(CLEANUP => 1);
my $cc = $Config{cc};
my $ccflags = $Config{ccflags};
my $archlib = $Config{archlib};
my $so_ext = $Config{dlext};

# Compile and link
my $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -Ic_src c_src/boolean.c -o $tmpdir/boolean.o 2>&1";
my $out = `$cmd`;
is($? >> 8, 0, 'boolean.c compiles') or BAIL_OUT("compile failed: $out");

$cmd = "$cc -shared -fPIC $tmpdir/boolean.o -o $tmpdir/chalk.$so_ext 2>&1";
$out = `$cmd`;
is($? >> 8, 0, 'chalk.so links') or BAIL_OUT("link failed: $out");

# Set CHALK_SO_PATH so Runtime.pm finds it
$ENV{CHALK_SO_PATH} = "$tmpdir/chalk.$so_ext";

# Now test that Runtime loads successfully
use_ok('Chalk::Bootstrap::Runtime');

# Verify the module loaded chalk.so
ok(Chalk::Bootstrap::Runtime->loaded(), 'chalk.so is loaded');

done_testing;
```

- [ ] **Step 2: Run to verify it fails**

Run: `perl -Ilib t/bootstrap/c-runtime-loader.t`
Expected: FAIL — `Chalk::Bootstrap::Runtime` module not found

- [ ] **Step 3: Write Chalk::Bootstrap::Runtime**

Create `lib/Chalk/Bootstrap/Runtime.pm`:

```perl
# ABOUTME: Loads chalk.so shared C library with RTLD_GLOBAL symbol visibility.
# ABOUTME: Must be required before any per-class XS wrapper .so files.
use 5.42.0;
use utf8;

package Chalk::Bootstrap::Runtime;
require DynaLoader;
require Config;

my $_loaded = false;

# Find chalk.so: check CHALK_SO_PATH env var first, then @INC
my $so;
if ($ENV{CHALK_SO_PATH} && -f $ENV{CHALK_SO_PATH}) {
    $so = $ENV{CHALK_SO_PATH};
} else {
    my $so_name = "chalk." . $Config::Config{dlext};
    for my $inc (@INC) {
        my $try = "$inc/auto/Chalk/Bootstrap/Runtime/$so_name";
        if (-f $try) { $so = $try; last; }
    }
}
die "Cannot find chalk.so (set CHALK_SO_PATH or install to \@INC)" unless $so;

# RTLD_GLOBAL (0x01 on Linux) makes C symbols visible to subsequently
# loaded shared libraries. This is how per-class .so files resolve
# boolean_is_zero() etc. without explicit linking.
my $flags = 0x01;  # RTLD_GLOBAL
my $libref = DynaLoader::dl_load_file($so, $flags)
    or die "Cannot load chalk.so ($so): " . DynaLoader::dl_error();

$_loaded = true;

sub loaded { $_loaded }
```

- [ ] **Step 4: Run the test**

Run: `perl -Ilib t/bootstrap/c-runtime-loader.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Runtime.pm t/bootstrap/c-runtime-loader.t
git commit -m "feat: Chalk::Bootstrap::Runtime loads chalk.so with RTLD_GLOBAL"
```

---

## Task 5: Write build-chalk-so build script

The build orchestrator that compiles `.c` files into `chalk.so` and per-class
`.xs` wrappers into individual `.so` files.

**Files:**
- Create: `script/build-chalk-so`

- [ ] **Step 1: Write the build script**

Create `script/build-chalk-so`:

```perl
#!/usr/bin/env perl
# ABOUTME: Build orchestrator for chalk.so shared C library + per-class XS wrappers.
# ABOUTME: Compiles .c files into chalk.so, then each .xs wrapper into its own .so.
use 5.42.0;
use utf8;
use Config;
use File::Path qw(make_path);
use File::Basename qw(dirname);

my $build_dir = '.build/chalk-so';
my $c_src     = 'c_src';

my $cc      = $Config{cc};
my $ccflags = $Config{ccflags};
my $archlib = $Config{archlib};
my $so_ext  = $Config{dlext};
my $perl    = $^X;
my $xsubpp  = "$Config{privlibexp}/ExtUtils/xsubpp";
my $typemap = "$Config{privlibexp}/ExtUtils/typemap";

# Phase 1: Compile all .c files to .o
print "Phase 1: Compiling C files...\n";
make_path("$build_dir/obj");

my @c_files = glob("$c_src/*.c");
my @o_files;

for my $c_file (@c_files) {
    my $base = $c_file =~ s{.*/}{}r =~ s{\.c$}{}r;
    my $o_file = "$build_dir/obj/$base.o";
    my $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$c_src $c_file -o $o_file 2>&1";
    my $out = `$cmd`;
    if ($? >> 8 != 0) {
        die "Compile failed for $c_file:\n$out\nCommand: $cmd\n";
    }
    push @o_files, $o_file;
    say "  $base.c → $base.o";
}

# Phase 2: Link all .o files into chalk.so
print "Phase 2: Linking chalk.so...\n";
my $chalk_so = "$build_dir/chalk.$so_ext";
my $o_list = join(' ', @o_files);
my $cmd = "$cc -shared -fPIC $o_list -o $chalk_so 2>&1";
my $out = `$cmd`;
die "Link failed:\n$out\nCommand: $cmd\n" if $? >> 8 != 0;
say "  chalk.$so_ext built";

# Phase 3: Compile each .xs wrapper
print "Phase 3: Compiling XS wrappers...\n";
my @xs_files = glob("$c_src/*.xs");

for my $xs_file (@xs_files) {
    my $base = $xs_file =~ s{.*/}{}r =~ s{\.xs$}{}r;

    # Determine the package name from MODULE line in .xs
    open my $fh, '<', $xs_file or die "Cannot read $xs_file: $!";
    my $pkg;
    while (<$fh>) {
        if (/^MODULE\s*=\s*(\S+)/) { $pkg = $1; last; }
    }
    close $fh;
    die "No MODULE line in $xs_file" unless $pkg;

    # Build output path matching Perl's auto/ convention
    my $pkg_path = $pkg =~ s{::}{/}gr;
    my $out_dir = "$build_dir/auto/$pkg_path";
    make_path($out_dir);

    # xsubpp → .c
    my $xs_c = "$build_dir/$base.c";
    $cmd = "$perl $xsubpp -typemap $typemap $xs_file > $xs_c 2>&1";
    $out = `$cmd`;
    die "xsubpp failed for $xs_file:\n$out\n" if $? >> 8 != 0;

    # .c → .o
    my $xs_o = "$build_dir/$base.o";
    $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$c_src $xs_c -o $xs_o 2>&1";
    $out = `$cmd`;
    die "Compile failed for $xs_c:\n$out\n" if $? >> 8 != 0;

    # .o → .so
    my $xs_so = "$out_dir/$base.$so_ext";
    $cmd = "$cc -shared -fPIC $xs_o -o $xs_so 2>&1";
    $out = `$cmd`;
    die "Link failed for $xs_o:\n$out\n" if $? >> 8 != 0;

    say "  $base.xs → $xs_so";
}

say "\nBuild complete.";
say "chalk.so: $chalk_so";
say "Set CHALK_SO_PATH=$chalk_so to use.";
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x script/build-chalk-so
perl script/build-chalk-so
```
Expected: Prints compilation steps, produces `.build/chalk-so/chalk.so` and
`.build/chalk-so/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.so`

- [ ] **Step 3: Run the pipeline test against built artifacts**

```bash
CHALK_SO_PATH=.build/chalk-so/chalk.so perl -Ilib -I.build/chalk-so t/bootstrap/c-runtime-loader.t
```
Expected: PASS

- [ ] **Step 4: Ensure .build/ is in .gitignore**

Check if `.build/` is already in `.gitignore`. If not, add it:
```bash
grep -q '^\.build/' .gitignore 2>/dev/null || echo '.build/' >> .gitignore
```

- [ ] **Step 5: Commit**

```bash
git add script/build-chalk-so .gitignore
git commit -m "feat: build-chalk-so script compiles C + XS into chalk.so + per-class .so"
```

---

## Task 6: Integration test — C-backed Boolean with Earley parser

The ultimate validation: load the C-backed Boolean semiring (without loading
the pure Perl version first — you cannot call `class_setup_stash` on an
already-registered class stash) and use it with the Earley parser to recognize
a grammar.

**IMPORTANT:** Do NOT `require Chalk::Bootstrap::Semiring::Boolean` (the pure
Perl version) before loading the C-backed one. Double class registration on the
same stash will segfault (documented in MEMORY.md under "XS BOOT Block").

**Files:**
- Create: `t/bootstrap/c-boolean-integration.t`

- [ ] **Step 1: Write the integration test**

Create `t/bootstrap/c-boolean-integration.t`. This test runs in a subprocess
to ensure a clean Perl interpreter with no prior class registrations:

```perl
# ABOUTME: Integration test: C-backed Boolean semiring via chalk.so + Earley parser.
# ABOUTME: Validates behavioral equivalence and Earley parser compatibility.
use 5.42.0;
use utf8;
use Test::More;
use Config;
use File::Temp qw(tempdir);

# Skip unless chalk.so is built
my $so_ext = $Config{dlext};
my $chalk_so = ".build/chalk-so/chalk.$so_ext";
plan skip_all => "chalk.so not built (run script/build-chalk-so first)"
    unless -f $chalk_so;

my $perl = $^X;
my $tmpdir = tempdir(CLEANUP => 1);

# === Part 1: Behavioral equivalence (subprocess — clean interpreter) ===

my $equiv_script = "$tmpdir/equiv_test.pl";
open my $fh, '>', $equiv_script or die "Cannot write $equiv_script: $!";
print $fh <<"END_SCRIPT";
use 5.42.0;
use utf8;
require DynaLoader;

# Load chalk.so with RTLD_GLOBAL
my \$chalk = DynaLoader::dl_load_file("$chalk_so", 0x01)
    or die "chalk.so: " . DynaLoader::dl_error();

# Load Boolean.so
my \$bool_so = ".build/chalk-so/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext";
my \$libref = DynaLoader::dl_load_file(\$bool_so, 0)
    or die "Boolean.so: " . DynaLoader::dl_error();
my \$boot = DynaLoader::dl_find_symbol(\$libref, "boot_Chalk__Bootstrap__Semiring__Boolean")
    or die "boot symbol: " . DynaLoader::dl_error();
DynaLoader::dl_install_xsub(
    "Chalk::Bootstrap::Semiring::Boolean::_bootstrap", \$boot, \$bool_so);
Chalk::Bootstrap::Semiring::Boolean->_bootstrap();

my \$b = Chalk::Bootstrap::Semiring::Boolean->new();
my \$z = \$b->zero();
my \$o = \$b->one();

# Core semiring operations
die "is_zero(z) fail" unless \$b->is_zero(\$z);
die "is_zero(o) fail" if \$b->is_zero(\$o);
die "is_zero(42) fail" if \$b->is_zero(42);
die "add(z,z) fail" unless \$b->is_zero(\$b->add(\$z, \$z));
die "add(z,o) fail" if \$b->is_zero(\$b->add(\$z, \$o));
die "add(o,z) fail" if \$b->is_zero(\$b->add(\$o, \$z));
die "add(o,o) fail" if \$b->is_zero(\$b->add(\$o, \$o));
die "mul(z,z) fail" unless \$b->is_zero(\$b->multiply(\$z, \$z));
die "mul(z,o) fail" unless \$b->is_zero(\$b->multiply(\$z, \$o));
die "mul(o,z) fail" unless \$b->is_zero(\$b->multiply(\$o, \$z));
die "mul(o,o) fail" if \$b->is_zero(\$b->multiply(\$o, \$o));
die "on_scan fail" if \$b->is_zero(\$b->on_scan({value => \$o}, 0, 0, 'x'));
die "on_scan zero fail" unless \$b->is_zero(\$b->on_scan({value => \$z}, 0, 0, 'x'));
die "should_scan fail" unless \$b->should_scan({}, 0, 0, 'x', sub { 0 });
die "supports_leo fail" unless \$b->supports_leo();

print "EQUIV_OK\\n";
END_SCRIPT
close $fh;

my $out = `$perl -Ilib $equiv_script 2>&1`;
like($out, qr/EQUIV_OK/, 'C Boolean: all semiring operations match pure Perl')
    or diag("Equivalence test output: $out");

# === Part 2: Earley parser integration (subprocess — clean interpreter) ===

my $earley_script = "$tmpdir/earley_test.pl";
open $fh, '>', $earley_script or die "Cannot write $earley_script: $!";
print $fh <<"END_SCRIPT";
use 5.42.0;
use utf8;
use lib 'lib';
require DynaLoader;

# Load C-backed Boolean BEFORE any pure Perl semiring
my \$chalk = DynaLoader::dl_load_file("$chalk_so", 0x01)
    or die "chalk.so: " . DynaLoader::dl_error();
my \$bool_so = ".build/chalk-so/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext";
my \$libref = DynaLoader::dl_load_file(\$bool_so, 0)
    or die "Boolean.so: " . DynaLoader::dl_error();
my \$boot = DynaLoader::dl_find_symbol(\$libref, "boot_Chalk__Bootstrap__Semiring__Boolean")
    or die "boot symbol: " . DynaLoader::dl_error();
DynaLoader::dl_install_xsub(
    "Chalk::Bootstrap::Semiring::Boolean::_bootstrap", \$boot, \$bool_so);
Chalk::Bootstrap::Semiring::Boolean->_bootstrap();

# Now load Earley (pure Perl) and use C-backed Boolean as the semiring
require Chalk::Bootstrap::Earley;
require Chalk::Grammar::BNF;

# Simple test grammar: S -> 'a'
my \$grammar = Chalk::Grammar::BNF->new(
    rules => [
        Chalk::Grammar::Rule->new(
            name => 'S',
            alternatives => [
                [Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a')],
            ],
        ),
    ],
    start => 'S',
);

my \$bool = Chalk::Bootstrap::Semiring::Boolean->new();
my \$parser = Chalk::Bootstrap::Earley->new(
    grammar => \$grammar,
    semiring => \$bool,
);

# Parse "a" — should succeed
my \$result = \$parser->recognize("a");
die "recognize('a') should succeed" unless \$result;

# Parse "b" — should fail
\$result = \$parser->recognize("b");
die "recognize('b') should fail" if \$result;

print "EARLEY_OK\\n";
END_SCRIPT
close $fh;

$out = `$perl -Ilib $earley_script 2>&1`;
like($out, qr/EARLEY_OK/, 'C Boolean + Earley parser: recognizes simple grammar')
    or diag("Earley test output: $out");

done_testing;
```

- [ ] **Step 2: Run the test**

First build chalk.so if not already built:
```bash
perl script/build-chalk-so
```

Then run:
```bash
perl -Ilib t/bootstrap/c-boolean-integration.t
```
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add t/bootstrap/c-boolean-integration.t
git commit -m "test: C Boolean integration with Earley parser via chalk.so"
```

---

## Task 7: Verify existing tests still pass

The C-backed Boolean must not break anything. Run the full test suite.

**Files:** None (verification only)

- [ ] **Step 1: Run existing Boolean-related tests**

```bash
perl -Ilib t/bootstrap/earley-boolean.t
```
Expected: All tests PASS (these use pure Perl Boolean — unchanged)

- [ ] **Step 2: Run the full bootstrap test suite**

```bash
perl -Ilib t/bootstrap/*.t 2>&1 | tail -20
```
Expected: All tests PASS. The new C pipeline is additive — it doesn't
replace pure Perl yet.

- [ ] **Step 3: Commit any fixes if needed**

If any tests needed adjustment, commit those fixes.

---

## Summary

After completing all 7 tasks:

1. `chalk.h` — shared C header with `CHALK_FIELD` macro
2. `boolean.c` + `boolean.h` — hand-crafted C implementation of Boolean semiring
3. `Boolean.xs` — thin XSUB wrapper + BOOT block
4. `Chalk::Bootstrap::Runtime` — loads `chalk.so` with `RTLD_GLOBAL`
5. `script/build-chalk-so` — build orchestrator
6. Integration test proving behavioral equivalence
7. Existing tests verified passing

This proves the architecture end-to-end. Phase 2 (simple semirings) and
Phase 3 (complex classes) follow the same pattern, adding more `.c`/`.h`/`.xs`
files. The C emitter (`Target/C.pm`) that auto-generates these from IR is
the next plan after this pipeline is validated.
