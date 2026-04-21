# Target Interface — generate($mop) → HashRef[Str]

## Overview

Code generation targets accept a `Chalk::MOP` and return a
`HashRef[Str]` mapping output file paths to their content. This is
the only entry point a target exposes. Distribution packaging
(CPAN-shape output: Build.PL, MANIFEST, pm stubs) is a separate
higher layer that consumes the target's output.

## Current state

The base class `Chalk::Bootstrap::Target` defines two abstract
methods:

- `generate($ir)` — emit source code from IR
- `generate_distribution($ir)` — emit a CPAN-shaped distribution

Concrete targets diverge from this interface:

- `Target/Perl.pm` adds `generate_with_cfg($ir, $sa, $ctx)` — a
  backchannel that passes the SemanticAction and parse-time Context
  so codegen can recover `cfg_state` annotations.
- `Target/C.pm` exposes `generate_c_files($ir, $sa, $ctx)` and
  `generate_xs_wrapper($ir, $exported_functions,
  $anon_sub_registrations)` — different signatures, different
  concerns mixed together.

The `($sa, $ctx)` arguments exist because `cfg_state` lives on the
parse-time Context tree and codegen needs to walk it. The
`generate_distribution` method conflates code emission with packaging.

## Target interface

With `Chalk::MOP` as the compilation-unit owner, both problems
resolve:

```
method generate($mop) → HashRef[Str]
```

- **Input:** a `Chalk::MOP` holding all classes, methods, fields,
  subs, imports, phasers, and their per-method graphs.
- **Output:** a hashref mapping relative file paths to string
  content. Each key is a path (`lib/Point.pm`, `src/point.c`,
  `src/point.xs`); each value is the file's complete content.
- **No backchannel.** `cfg_state` lives on the MOP-owned graphs.
  Codegen reads the MOP, not the parse-time Context.
- **No distribution packaging.** The target emits source files. A
  separate packaging layer assembles them into a CPAN distribution,
  an XS build tree, or whatever output shape is needed.

`generate_distribution`, `generate_with_cfg`, `generate_c_files`,
and `generate_xs_wrapper` all collapse into `generate($mop)`.

## Packaging layer

Distribution packaging consumes `generate`'s output and adds:

- `Build.PL` / `Makefile.PL`
- `MANIFEST`
- `META.json` / `META.yml`
- pm stubs for XS modules (auto-require pure-Perl deps)
- Directory structure (lib/, src/, t/)

This layer is not a target — it does not read IR or the MOP. It
reads the `HashRef[Str]` from `generate` plus configuration (module
name, version, author, dependencies). It can be shared across
targets: a CPAN packager works the same whether the source files
came from `Target/Perl.pm` or `Target/C.pm`.

The packaging layer does not exist yet. Its design is separable from
the target interface and can land independently.

## Per-target output shapes

Each target's `generate($mop)` returns a different set of paths:

**Target/Perl.pm:**
```
{
    'lib/Point.pm' => '...',
    'lib/Line.pm'  => '...',
}
```

**Target/C.pm:**
```
{
    'src/point.c'      => '...',
    'src/point.h'      => '...',
    'src/point_xs.xs'  => '...',
    'src/line.c'       => '...',
    'src/line.h'       => '...',
    'src/line_xs.xs'   => '...',
}
```

The packaging layer knows how to arrange each shape into the
appropriate distribution format.

## Migration

Existing targets migrate incrementally:

1. Add `generate($mop)` alongside existing methods.
2. Implement `generate($mop)` by delegating to the existing
   implementation (extract `$ir` / `$sa` / `$ctx` from the MOP's
   graphs and annotations).
3. Migrate callers from `generate_with_cfg` / `generate_c_files` to
   `generate($mop)`.
4. Delete the old methods once no callers remain.

The `($sa, $ctx)` backchannel removal is blocked on the polymorphic
migration completing (cfg_state must live on the graph, not on
parse-time Context). The `generate($mop)` signature can land before
that — the initial implementation can still internally extract
Context from the MOP's parse-time state as a transitional step.

## Scope boundaries

- The target interface design covers the `generate` method signature
  and its contract (MOP in, HashRef[Str] out).
- The packaging layer is separate future work.
- BNF targets (`BNF/Target/Perl`) follow the same interface. They
  receive a MOP built from the BNF grammar rather than from Perl
  source, but the contract is identical.
