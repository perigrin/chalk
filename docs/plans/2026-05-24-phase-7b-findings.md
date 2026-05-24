# Phase 7b Probe Findings

**Date:** 2026-05-24
**Branch:** `fixup-audit-baseline`

## Question

The Target::C migration audit (§1e, risk #1) flagged that
`script/build-chalk-so-generated` calls `$target->generate_c_files(...)` at
lines 140 and 289 but no public method by that name exists on Target::C —
indeed `t/bootstrap/mop/codegen-no-backchannel.t:17` explicitly asserts
`!can('generate_c_files')`. Either the build script is broken, there is
hidden indirection, or it is an aspirational stub.

## Probe

Direct probe via Perl:

```
$ perl -Ilib -e 'use Chalk::Bootstrap::Perl::Target::C;
                my $t = Chalk::Bootstrap::Perl::Target::C->new(module_name => "Foo");
                say "can(generate_c_files): ",  ($t->can("generate_c_files")  ? "yes" : "no");
                say "can(_generate_c_files): ", ($t->can("_generate_c_files") ? "yes" : "no");'
can(generate_c_files): no
can(_generate_c_files): yes
```

Confirmed: `generate_c_files` does not exist. The build script would die
at the first call:

```
Can't locate object method "generate_c_files" via package "Chalk::Bootstrap::Perl::Target::C"
```

## Conclusion

The build script is broken. Every other caller in the codebase uses the
underscored `_generate_c_files`:

- `t/bootstrap/c-type-aware-dispatch.t` (2 sites)
- `t/bootstrap/c-xs-wrapper-gen.t` (2 sites)
- `t/bootstrap/c-data-model-classes.t` (4 sites)
- `t/bootstrap/c-target-boolean.t` (1 site)
- `t/bootstrap/xs-isa-inheritance.t` (1 site)

The build script is the only outlier. The breakage has gone undetected
because CI/regression does not run the build script — see the baseline
doc (`docs/plans/2026-05-24-phase-7-baseline.md`): every test that
*requires* `chalk.so` is `1..0 # SKIP chalk.so not built (...)`.

## Fix (this commit)

Rename `generate_c_files` → `_generate_c_files` in two call sites and the
error message at script/build-chalk-so-generated:140, :146, :289.

No method-rename in lib/. The underscore-prefixed name stays as the
real method until Phase 7d migrates the body emission to the schedule
path and the public surface becomes `generate($mop)`.

## Secondary finding: dead Phase 3b metadata loop

`script/build-chalk-so-generated:207, 221, 251` walks for Constructor
IR shapes that no longer exist (Actions.pm produces only Info-structs):

- Line 206: `$_ isa Chalk::Bootstrap::IR::Node::Constructor && $_->class() eq 'ClassDecl'`
- Line 220: `$child isa Chalk::Bootstrap::IR::Node::Constructor`
- Line 221: `$child->class() eq 'FieldDecl'`
- Line 251: `$child->class() eq 'MethodDecl'`

This is the type-aware-dispatch metadata loop that populates
`%class_metadata`. With current parser output, every `grep` returns
empty, so `class_metadata` is `{}`, the `keys %class_metadata` check at
line 270 is false, and Phase 3b silently no-ops. The second-pass
type-aware Earley regeneration is dead code in production.

Not fixed in this commit — it requires either:

1. Rewriting Phase 3b's metadata extraction to walk Info-structs
   (ClassInfo/FieldInfo/MethodInfo + their accessors); or
2. Concluding that type-aware-dispatch metadata extraction is properly
   a job for the MOP-driven entry path in Phase 7d, not for the
   transitional Program-IR path.

Deferred to Phase 7d with a tracking note here, since option (2) is
likely correct and the path is being replaced anyway.

## Mop entry point shape — decision

The audit asked: is the MOP-driven entry `generate($mop)` (filling in
the current stub at C.pm:1466) or a new method?

Decision: keep `generate($mop)` as the future public entry. The
existing stub stays a stub during 7b. Phase 7d (schedule-driven body
emission) is where it gets filled in by analogy with Target::Perl's
`_generate_from_schedule`. Until then `_generate_c_files` remains the
real path and the build script + tests target it directly.

This matches the audit's preferred-form recommendation and keeps 7b
mechanical.
