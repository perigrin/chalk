# C Codegen Redesign: chalk.so + Thin XS Wrappers

## Problem

All XS compilation approaches so far suffer from Perl/C bridge overhead in hot paths.
`_run_parse` calls `is_zero()` 11+ times per iteration. Even when both sides are compiled
to C, the dispatch goes through Perl's `call_method` — negating any XS speedup.

Multi-class XS (one giant .xs) was abandoned: no faster than pure Perl.
Per-class XS (separate .so per class) fixes compilation issues but not the bridge problem.

**Root cause:** We leaned into the XS API as the implementation layer. XS is glue, not
an implementation language. Core logic belongs in C with direct function calls.

## Proposed Architecture

```
boolean.c  → boolean.o  ─┐
earley.c   → earley.o   ─┤
scope.c    → scope.o    ─┼─→ link → chalk.so
context.c  → context.o  ─┤
...                      ─┘

Boolean.xs ─┐
Earley.xs  ─┼─→ thin XSUB wrappers linking against chalk.so
...        ─┘
```

1. **One `.c` file per class** — core implementation as plain C functions
   (e.g., `boolean.c` has `boolean_is_zero()`, `earley.c` has `earley_run_parse()`)
2. **One `.h` file per class** — function prototypes for cross-class calls
3. **One `.xs` file per class** — thin XS wrappers exposing only the public API
   as XSUBs that call into the corresponding `.c` functions
4. **Link all `.o` into `chalk.so`** — one shared library for the whole compiler,
   so C functions call each other directly across classes
5. Hot path stays entirely in C — `earley_run_parse()` calls `boolean_is_zero()`
   as a direct C function call, zero bridge overhead

## Design Questions

### Field Access
- `ObjectFIELDS(SvRV(self))[idx]` is the Perl class C API for accessing fields
- Do we use it from the C layer? Or manage our own struct layout?
- Using ObjectFIELDS keeps compatibility with `feature class` but ties C code to Perl internals
- Own structs would be faster but need a synchronization strategy with the Perl objects

### feature class Integration
- The thin XS wrappers need to register classes with Perl's class system (BOOT block)
- Field declarations, :param, :reader, :writer still go through the class C API
- ADJUST blocks: emitted as C functions called from XS ADJUST registration
- How do we handle inheritance (:isa)?

### Codegen Target
- Current codegen emits XS directly (`_emit_xs`, `_emit_xs_complex_method`, etc.)
- New codegen needs three outputs per class:
  - `.c` — implementation (plain C, no XS macros except Perl API)
  - `.h` — function prototypes for cross-class calls
  - `.xs` — thin XSUB wrappers for Perl-visible methods
- The `.c` emitter is similar to current `_impl_` helper emission but without XS framing

### Build System
- Module::Build or ExtUtils::MakeMaker for the final XS compilation
- Need to compile all `.c` files, then link with the XS-generated `.c` files
- Single `chalk.so` output containing everything
- The previous per-class XS approach (`script/bootstrap-xs-earley`) has been removed;
  `script/build-chalk-so-generated` is the current build pipeline.

### Incremental Strategy
- Can we do this incrementally? e.g., start with just Earley + Boolean in C,
  keep everything else as pure Perl?
- What's the minimal viable C layer that shows a measurable speedup?
- `_run_parse` + `is_zero` + `add` + `multiply` would eliminate the hottest bridge calls

## What We Have That's Reusable

- **IR → C emission logic** — the `_impl_` helper generation in Target/XS.pm already
  emits valid C for method bodies. This is the core of what the `.c` emitter needs.
- **DepChaser** — dependency resolution for determining which classes to compile
- **PM stub auto-require** — `_emit_pm_stub_with_deps` for loading pure-Perl deps
- **XS codegen bug fixes** — sigil stripping, sv_setsv void handling, __sv in BOOT

## What Changes

- Target/XS.pm split into Target/C.pm (implementation) + Target/XS.pm (thin wrappers)
- `_impl_` helpers become the primary output, not a side effect of XSUB generation
- Cross-class calls become direct C calls instead of `call_method`/`call_pv`
- Build pipeline: parse → IR → C + H + XS → compile → link → chalk.so

## Research: Prior Art

Someone has done this before, even if not as a compilation target. Look at:

- **Class::XSAccessor** — C implementation of accessor methods, thin XS exposure
- **DBD::SQLite** — wraps sqlite3.c (a large C library) with XS glue for Perl API
- **Moose::XS** (abandoned but instructive) — attempted to compile Moose internals to C
- **ExtUtils::MakeMaker / Module::Build** — how they handle multi-file C + XS builds
  (the `c_source` and `extra_compiler_flags` options)
- **Inline::C** — how it manages C compilation units alongside XS
- **PyPy's RPython → C pipeline** — translates a restricted Python subset to C,
  links into a single shared library, exposes API via separate layer
- **Cython** — compiles Python-like code to C, generates thin Python wrapper layer
- **Perl core itself** — `pp.c`, `sv.c`, etc. are plain C; `universal.c` + `.xs` files
  expose the Perl API. The pattern we want is exactly how Perl's own internals work.

The key question for research: how do these projects handle the boundary between
"C implementation using Perl's SV*/AV*/HV* types" and "XS wrapper that registers
methods with Perl's class system"? That's our exact problem.

## Per-Class XS Status (current, pre-redesign)

From the 2026-03-19 per-class bootstrap run:
- **Compile OK:** Boolean, Structural, SemanticAction, FilterComposite (4/7)
- **Fail:** Earley, Precedence, TypeInference — regex statics (`_rx_N`) and anon
  sub CVs (`_cv__anon_N`) not emitted in per-class scope (they were module-level
  in multi-class but per-class `generate_distribution_with_cfg` doesn't emit them)
- These static variable scoping issues will be addressed naturally in the C redesign
  since each `.c` file will have its own file-scope statics
