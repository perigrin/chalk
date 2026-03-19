# Target/C.pm Emitter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract IR-to-C emission logic from Target/XS.pm into a new Target/C.pm that produces `.c` + `.h` files, validated by compiling Boolean and passing the existing 48 behavioral tests.

**Architecture:** Target/C.pm is a standalone class created by copying the ~50 emission methods from XS.pm, renaming `_emit_xs_*` to `_emit_c_*`, and modifying the entry point to produce `.c` + `.h` instead of `.xs`. XS.pm retains BOOT/XSUB/PM stub generation. Validation: generated `boolean.c` compiles and passes the same tests as the hand-crafted version.

**Tech Stack:** Perl 5.42.0, C (gcc/cc), Perl class C API

**Spec:** `docs/superpowers/specs/2026-03-19-target-c-emitter-design.md`

**Skills required:** `writing-perl-5.42.0`, `test-driven-development`

**Key constraint:** XS.pm is 5933 lines. The extraction must not break XS.pm's existing functionality. Both XS.pm and C.pm must work after each task.

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `lib/Chalk/Bootstrap/Perl/Target/C.pm` | C emitter: IR → `.c` + `.h` files |
| `t/bootstrap/c-target-boolean.t` | Tests C.pm generates compilable Boolean that passes behavioral tests |

### Key Reference Files

| File | Why |
|------|-----|
| `lib/Chalk/Bootstrap/Perl/Target/XS.pm` | Source of extracted methods (5933 lines) |
| `c_src/boolean.c` | Hand-crafted reference — generated code must be behaviorally equivalent |
| `c_src/Boolean.xs` | Hand-crafted XS wrapper — used with generated `.c` for testing |
| `t/bootstrap/c-build-pipeline.t` | Existing 13 tests for compile/link/load pipeline |

---

## Strategy

The extraction follows this approach:

1. **Copy, don't move.** Create C.pm by copying methods from XS.pm. Leave XS.pm intact. This means temporary code duplication — but it keeps XS.pm working throughout and avoids a risky big-bang refactor.

2. **Rename on copy.** As methods are copied, rename `_emit_xs_*` to `_emit_c_*` and update internal calls.

3. **Modify behavior.** After copying, change cross-class/same-class calls from `call_method`/`_impl_` patterns to direct `{slug}_{method}(aTHX_ ...)` calls. Make functions non-static (exported).

4. **Validate.** Generate `boolean.c` + `boolean.h` from Boolean's IR, compile it, and run the 48 behavioral tests.

5. **Wire XS.pm to delegate** (future task, not this plan). After C.pm works independently, XS.pm can be modified to use C.pm instead of its own emission methods. That's a separate plan.

---

## Task 1: Create Target/C.pm skeleton with _analyze_class

Create the module with constructor, slug derivation, `_analyze_class` (the read-only analysis portion of `_emit_class_sections`), and `generate_c_files` stub.

**Files:**
- Create: `lib/Chalk/Bootstrap/Perl/Target/C.pm`
- Create: `t/bootstrap/c-target-boolean.t`

- [ ] **Step 1: Write failing test — C.pm exists and analyzes Boolean IR**

Create `t/bootstrap/c-target-boolean.t`:

```perl
# ABOUTME: Tests Target::C emitting .c + .h files from Boolean IR.
# ABOUTME: Validates generated code compiles and passes behavioral tests.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

# Parse Boolean.pm to IR
my $grammar = setup_xs_grammar('Chalk::Grammar::Perl::XSBootstrap');
my ($ir, $sa, $ctx) = parse_file_ir($grammar, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm');
ok(defined $ir, 'Boolean.pm parsed to IR');

# Load Target::C
use_ok('Chalk::Bootstrap::Perl::Target::C');

# Create emitter
my $c = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Chalk::Bootstrap::Semiring::Boolean',
);
isa_ok($c, 'Chalk::Bootstrap::Perl::Target::C');

# Generate C files
my $result = $c->generate_c_files($ir, $sa, $ctx);
ok(defined $result, 'generate_c_files returns result');
ok(ref $result eq 'HASH', 'result is a hashref');
ok(exists $result->{files}, 'result has files key');
ok(exists $result->{files}{'boolean.c'}, 'result has boolean.c');
ok(exists $result->{files}{'boolean.h'}, 'result has boolean.h');
ok(exists $result->{exported_functions}, 'result has exported_functions');

# Verify .h has prototypes for known methods
my $h = $result->{files}{'boolean.h'};
like($h, qr/boolean_is_zero/, 'header has is_zero prototype');
like($h, qr/boolean_add/, 'header has add prototype');
like($h, qr/boolean_multiply/, 'header has multiply prototype');
like($h, qr/boolean_zero\b/, 'header has zero prototype');
like($h, qr/boolean_one\b/, 'header has one prototype');

# Verify .c has function definitions
my $c_code = $result->{files}{'boolean.c'};
like($c_code, qr/#include "chalk\.h"/, '.c includes chalk.h');
like($c_code, qr/#include "boolean\.h"/, '.c includes boolean.h');
like($c_code, qr/boolean_is_zero\(/, '.c has is_zero definition');
like($c_code, qr/boolean_add\(/, '.c has add definition');

done_testing;
```

- [ ] **Step 2: Run to verify it fails**

Run: `perl -Ilib t/bootstrap/c-target-boolean.t`
Expected: FAIL — `Chalk::Bootstrap::Perl::Target::C` not found

- [ ] **Step 3: Create Target/C.pm skeleton**

Create `lib/Chalk/Bootstrap/Perl/Target/C.pm`. This is a large file — copy the
following from XS.pm and modify:

**From XS.pm, copy these elements:**
- Class declaration and fields (the ~15 state fields listed in the spec)
- `_class_slug` method
- `_find_class_decl` method
- `_build_field_index_map` method
- `_scan_class_methods` method
- `_build_cfg_lookup` method
- `_xs_c_type_for` lexical sub (rename concept: same logic)

**New methods to write:**
- `_analyze_class($ir)` — walks ClassDecl to populate field_map, class_methods,
  class_scope_vars, class_subs, use_constants. Extract the analysis-only parts
  from `_emit_class_sections` (lines 1606-1729 of XS.pm). Does NOT emit XSUBs,
  classify methods as simple/complex, or make eval_pv decisions.
- `generate_c_files($ir, $sa, $ctx)` — stub that calls `_build_cfg_lookup`,
  `_analyze_class`, then returns empty files for now.

The skeleton should:
```perl
# ABOUTME: C emitter: produces .c and .h files from Perl class IR.
# ABOUTME: Extracts emission logic from Target/XS.pm for the chalk.so architecture.
use 5.42.0;
use utf8;
use experimental 'class';

# No :isa — C.pm has a different API (generate_c_files, not generate).
# It is standalone, not a subclass of Target.
class Chalk::Bootstrap::Perl::Target::C {
    field $module_name :param :reader;
    field $field_map;
    field $field_sigils;
    field %_cfg_lookup;
    field $_return_context = false;
    field $_loop_depth = 0;
    field $_class_methods;
    field $_regex_counter = 0;
    field $_regex_statics;
    field %_class_scope_vars;
    field %_class_subs;  # populated by _scan_class_methods as a side effect
    field %_use_constants;
    field @_anon_sub_helpers;
    field $_anon_sub_counter = 0;
    field $_current_slug = '';
    field @_exported_functions;  # accumulated during emission
    field @_skipped_methods;
    field @_anon_sub_registrations;  # populated by _emit_c_anon_sub_expr (empty for Boolean)
    field $_sa;   # SemanticAction — stored for emit_from_cfg_state
    field $_ctx;  # Context — stored for emit_from_cfg_state

    # _xs_c_type_for must be a lexical sub at class scope (not inside a method)
    # so all copied methods can reference it.
    my sub _xs_c_type_for($ti_type) {
        return 'void' if !defined $ti_type || $ti_type eq 'Void';
        return 'SV *';
    }

    # ... methods ...
}
```

**Note on `$_sa` and `$_ctx` fields:** `emit_from_cfg_state` (called from
`_emit_c_stmt` via the CFG dispatch path) needs access to `$sa` and `$ctx`.
In XS.pm these are passed into `generate_distribution_with_cfg` and threaded
through `_build_cfg_lookup`. C.pm stores them as fields, set at the start of
`generate_c_files`, so `emit_from_cfg_state` can access them without
changing every method signature in the call chain.

**Note on `%_class_subs`:** `_scan_class_methods` populates `%_class_subs` as
a side effect (XS.pm line ~2514). `_analyze_class` is not purely read-only —
it calls `_scan_class_methods` which mutates `%_class_subs`. This is inherited
behavior from XS.pm.

At this stage, `generate_c_files` returns a result with empty `.c` and `.h`
content — just enough structure to make the test's structural assertions pass.
The content assertions (like `like($c_code, qr/boolean_is_zero/)`) will fail.
That's expected — Task 2 adds the emission methods.

- [ ] **Step 4: Run the test**

Run: `perl -Ilib t/bootstrap/c-target-boolean.t`
Expected: Structural tests PASS (module loads, returns hashref with right keys).
Content tests FAIL (no function definitions in generated code yet). This is
the expected RED state for Task 2.

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/C.pm t/bootstrap/c-target-boolean.t
git commit -m "feat: Target/C.pm skeleton with _analyze_class and generate_c_files stub"
```

---

## Task 2: Copy expression and statement emitters

Copy the ~30 expression and statement emission methods from XS.pm into C.pm.
Rename `_emit_xs_*` to `_emit_c_*`. Update all internal `$self->_emit_xs_*`
calls to `$self->_emit_c_*`.

This is the bulk of the extraction — a mechanical copy-and-rename.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm`

- [ ] **Step 1: Copy expression emitters (Group 1) from XS.pm**

Copy these methods from XS.pm into C.pm, renaming `_emit_xs_` to `_emit_c_`:

From XS.pm → C.pm (with rename):
- `_emit_xs_expr` (line 3422) → `_emit_c_expr`
- `_emit_xs_const_expr` (line 3468) → `_emit_c_const_expr`
- `_emit_xs_interp_expr` (line 3599) → `_emit_c_interp_expr`
- `_emit_xs_binary_expr` (line 3656) → `_emit_c_binary_expr`
- `_emit_xs_unary_expr` (line 3744) → `_emit_c_unary_expr`
- `_emit_xs_method_call_expr` (line 3762) → `_emit_c_method_call_expr`
- `_emit_xs_subscript_expr` (line 4176) → `_emit_c_subscript_expr`
- `_emit_xs_postfix_deref_expr` (line 4298) → `_emit_c_postfix_deref_expr`
- `_emit_xs_ternary_expr` (line 4325) → `_emit_c_ternary_expr`
- `_emit_xs_hash_ref_expr` (line 4334) → `_emit_c_hash_ref_expr`
- `_emit_xs_array_ref_expr` (line 4374) → `_emit_c_array_ref_expr`
- `_emit_xs_anon_sub_expr` (line 4392) → `_emit_c_anon_sub_expr`
- `_emit_xs_regex_match` (line 4489) → `_emit_c_regex_match`
- `_emit_xs_regex_subst` (line 4546) → `_emit_c_regex_subst`
- `_emit_xs_builtin_call` (line 4561) → `_emit_c_builtin_call`
- `_emit_xs_keys_list` (line 5083) → `_emit_c_keys_list`
- `_emit_xs_backtick_expr` (line 5102) → `_emit_c_backtick_expr`
- `_emit_xs_compound_assign_expr` (line 5110) → `_emit_c_compound_assign_expr`
- `_emit_xs_var_decl_expr` (line 5135) → `_emit_c_var_decl_expr`

After copying each method, do a find-and-replace within the method body:
`$self->_emit_xs_` → `$self->_emit_c_`

- [ ] **Step 2: Copy statement emitters (Group 2) from XS.pm**

- `_emit_xs_stmt` (line 3347) → `_emit_c_stmt`
- `_emit_xs_var_decl` (line 5173) → `_emit_c_var_decl`
- `_emit_xs_return_stmt` (line 5314) → `_emit_c_return_stmt`
- `_emit_xs_die_call` (line 5343) → `_emit_c_die_call`
- `_emit_xs_compound_assign_stmt` (line 5360) → `_emit_c_compound_assign_stmt`
- `_emit_xs_loop_jump` (line 5377) → `_emit_c_loop_jump`
- `_emit_xs_interp_return` (line 5639) → `_emit_c_interp_return`

Same rename of internal calls.

- [ ] **Step 3: Copy control flow emitters (Group 4) from XS.pm**

- `emit_cfg_if` (line 5395)
- `emit_cfg_phi_if` (line 5462)
- `emit_cfg_loop` (line 5487)
- `emit_cfg_try_catch` (line 5689)
- `_sv_true_wrap` (line 5368) — lexical sub
- `emit_from_cfg_state` (line 5891)

These keep their names (no `_xs_` prefix to rename) except for internal
`$self->_emit_xs_*` calls which become `$self->_emit_c_*`.

- [ ] **Step 4: Copy helper methods (Group 5) from XS.pm**

- `_body_contains_return` (line 3111)
- `_body_contains_bare_return` (line 3138)
- `_is_bare_return_expr` (line 3147)
- `_is_unambiguous_value_expr` (line 3166)
- `_is_single_stmt_return_expr` (line 3193)
- `_collect_var_decls` (line 3207)
- `_collect_all_var_refs` (line 3294)
- `_has_early_return` (line 3082)
- `_wrap_retval` (line 5331)
- `_escape_c_string` (line 1433)
- `_field_sigil_for_expr` (line 230)
- `_find_exists_delete_in_chain` (line 4048)
- `_build_exists_delete_native` (line 4073)
- `_is_complex_method` (line 2609)
- `_ir_default_to_perl` (line 5718)
- `_needs_eval_fallback` (line 1446)
- `_calls_uncompiled_my_subs` (line 1462)
- `_uses_class_scope_vars` (line 1480)
- `_is_stale_merge` (line 1486)
- `_repair_stale_merge` (line 1502)
- `_fixup_xs_list_destructuring` (line 2310)
- `_fixup_ternary_assignment` (line 2365)
- `_fixup_filtercomposite_add_destructuring` (line 2432)
- `_scan_field_method_calls` (line 2551)

- [ ] **Step 5: Copy function-level emitters (Group 3) from XS.pm**

- `_emit_xs_complex_method` (line 2772) → `_emit_c_complex_method`
- `_emit_xs_sub` (line 2975) → `_emit_c_sub`
- `_emit_xs_method` (line 2652) → `_emit_c_method`

These are the top-level orchestrators that call the expression/statement
emitters. Rename internal `$self->_emit_xs_*` calls.

- [ ] **Step 6: Verify C.pm compiles (syntax check)**

Run: `perl -Ilib -c lib/Chalk/Bootstrap/Perl/Target/C.pm`
Expected: `syntax OK`

If there are compilation errors, fix them (likely missed renames or missing
method references).

**Rename policy:** `_emit_xs_*` methods are renamed to `_emit_c_*`. The
`_fixup_xs_*` methods keep their names (they fixup XS-generated patterns
that persist in the C output — the name documents their origin).
`_xs_c_type_for` keeps its name (it's already a C-type mapper).

- [ ] **Step 7: Checkpoint test — generate_c_files produces non-empty output**

Run: `perl -Ilib t/bootstrap/c-target-boolean.t`
Expected: Structural tests PASS (module loads, result has .c and .h keys).
Content assertions may fail (functions might not have correct names yet) —
but the file should have SOME content. This validates the 50-method copy
didn't break the basic emission pipeline.

- [ ] **Step 8: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/C.pm
git commit -m "feat: copy emission methods from XS.pm to C.pm (rename _emit_xs_ to _emit_c_)"
```

---

## Task 3: Wire generate_c_files to emit C code

Connect the `generate_c_files` entry point to the copied emission methods.
The output should be a `.c` file with non-static function definitions and a
`.h` file with prototypes.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm`

- [ ] **Step 1: Implement generate_c_files**

Replace the stub `generate_c_files` with the full pipeline:

```perl
method generate_c_files($ir, $sa, $ctx) {
    # Reset state
    %_cfg_lookup = ();
    @_exported_functions = ();
    @_skipped_methods = ();
    @_anon_sub_registrations = ();
    $_regex_counter = 0;
    $_regex_statics = [];
    @_anon_sub_helpers = ();
    $_anon_sub_counter = 0;

    # Phase 1: Build CFG lookup
    $self->_build_cfg_lookup($sa, $ctx) if defined $sa;

    # Phase 2: Analyze class IR
    $self->_analyze_class($ir);

    # Phase 3: Emit each method as a C function
    my @functions;
    my $class_decl = $self->_find_class_decl($ir);
    my @body = $class_decl->inputs()->[2]->@*;  # class body items

    for my $item (@body) {
        next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
        my $class = $item->class();

        if ($class eq 'MethodDecl') {
            my $result = $self->_emit_c_method($item);
            if (defined $result && exists $result->{helper}) {
                push @functions, $result->{helper}->@*;
                # Track exported function signature
                my $mname = $item->inputs()->[0]->value();
                my @params = map { $_->value() } $item->inputs()->[1]->@*;
                my $param_str = join(', ', 'pTHX_ SV *self',
                    map { my $p = $_; $p =~ s/^[\$\@\%]//; "SV *$p" } @params);
                push @_exported_functions, {
                    name => "${_current_slug}_${mname}",
                    return_type => 'SV *',
                    params => $param_str,
                };
            } else {
                push @_skipped_methods, $item->inputs()->[0]->value();
            }
        } elsif ($class eq 'SubDecl') {
            my $result = $self->_emit_c_sub(
                $item->inputs()->[0]->value(),
                $item->inputs()->[1],
                $item->inputs()->[2],
            );
            if (defined $result && exists $result->{helper}) {
                push @functions, $result->{helper}->@*;
                # Subs are static (not exported) — no prototype needed
            }
        }
    }

    # Phase 4: Assemble .c file
    my $slug = $_current_slug;
    my @c_lines;
    push @c_lines, "/* ABOUTME: C implementation of $module_name (generated by Target::C). */";
    push @c_lines, '/* ABOUTME: Auto-generated from Perl source — do not edit. */';
    push @c_lines, '#include "chalk.h"';
    push @c_lines, "#include \"${slug}.h\"";
    push @c_lines, '';

    # Class-scope statics
    for my $var (sort keys %_class_scope_vars) {
        my $info = $_class_scope_vars{$var};
        push @c_lines, "static SV *_${slug}_${var} = NULL;";
    }

    # Regex statics
    for my $rx ($_regex_statics->@*) {
        push @c_lines, "static SV *$rx->{var} = NULL;";
    }
    push @c_lines, '' if %_class_scope_vars || $_regex_statics->@*;

    # Anon sub helpers
    push @c_lines, @_anon_sub_helpers;

    # Function definitions
    push @c_lines, @functions;

    my $c_content = join("\n", @c_lines) . "\n";

    # Phase 5: Assemble .h file
    my @h_lines;
    push @h_lines, "/* ABOUTME: Function prototypes for $module_name (generated). */";
    push @h_lines, '/* ABOUTME: Included by other .c files for cross-class calls. */';
    my $guard = 'CHALK_' . uc($slug) . '_H';
    push @h_lines, "#ifndef $guard";
    push @h_lines, "#define $guard";
    push @h_lines, '#include "chalk.h"';
    push @h_lines, '';
    for my $func (@_exported_functions) {
        push @h_lines, "$func->{return_type} $func->{name}($func->{params});";
    }
    push @h_lines, '';
    push @h_lines, "#endif /* $guard */";

    my $h_content = join("\n", @h_lines) . "\n";

    return {
        files => {
            "${slug}.c" => $c_content,
            "${slug}.h" => $h_content,
        },
        exported_functions => \@_exported_functions,
        skipped_methods => \@_skipped_methods,
        anon_sub_registrations => \@_anon_sub_registrations,
    };
}
```

**IMPORTANT:** This is pseudocode showing the structure. The actual implementation
needs to handle:

- **`_emit_c_method` return types:** XS.pm's `_emit_xs_method` has four return
  paths: (1) bare arrayref for simple constant/die/empty bodies (XS-only output),
  (2) `{helper => [...], xsub => [...]}` for simple helpers, (3) result from
  `_emit_xs_complex_method` with `{helper, xsub, returns}`. C.pm must normalize
  ALL paths to return `{helper => [...]}` (no XSUB output). Rewrite the simple
  return paths in `_emit_c_method` to produce `{helper => [...]}` format instead
  of bare arrayrefs. For simple constant returns (Tier A/B), emit a one-line
  non-static function body instead of an XS CODE block.

- **Function naming:** replace `_impl_{slug}_{name}` with `{slug}_{name}` and
  make non-static (remove `static` keyword)

- **Same-class `$self->method()` calls:** emit `{slug}_{method}(aTHX_ self, ...)`
  not `_impl_{slug}_{method}(aTHX_ self, ...)`

- **`$_sa`/`$_ctx` storage:** At the start of `generate_c_files`, store `$sa`
  and `$ctx` in `$_sa` and `$_ctx` fields so `emit_from_cfg_state` can access
  them without changing every method signature.

- **Exported function tracking:** Rather than reconstructing parameter strings
  in `generate_c_files`, have `_emit_c_complex_method` and `_emit_c_method`
  push to `@_exported_functions` directly when they produce a non-static function.
  This avoids fragile duplicate parameter extraction.

- [ ] **Step 2: Modify _emit_c_method_call_expr for direct C calls**

The critical behavioral change. In C.pm's `_emit_c_method_call_expr`, when
the invocant is `self` and the method is in `$_class_methods`:

Replace the `_impl_` prefix pattern with the direct call pattern:
```
# Old (XS.pm): _impl_boolean_is_zero(aTHX_ self, ...)
# New (C.pm):  boolean_is_zero(aTHX_ self, ...)
```

Find the section that generates same-class direct calls (around line 3815
in XS.pm) and change the output from `_impl_{slug}_{method}` to
`{slug}_{method}`.

- [ ] **Step 3: Modify _emit_c_complex_method for non-static output**

In C.pm's `_emit_c_complex_method`, the function declaration must be:
```c
SV * boolean_is_zero(pTHX_ SV *self, SV *value) {
```
Not:
```c
static SV * _impl_boolean_is_zero(pTHX_ SV *self, SV *value) {
```

Find where the `static` keyword and `_impl_` prefix are prepended (around
line 2900 in XS.pm) and remove them.

- [ ] **Step 4: Run the test**

Run: `perl -Ilib t/bootstrap/c-target-boolean.t`
Expected: Content assertions now PASS — generated code has function definitions

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/C.pm
git commit -m "feat: wire generate_c_files to emit C code with direct call naming"
```

---

## Task 4: Compile and behaviorally test generated boolean.c

The critical validation: does C.pm-generated `boolean.c` compile, link into
`chalk.so`, and pass all behavioral tests?

**Files:**
- Modify: `t/bootstrap/c-target-boolean.t` — add compilation and behavioral tests

- [ ] **Step 1: Add compilation test to c-target-boolean.t**

Append to the test file:

```perl
use Config;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};

SKIP: {
    skip 'No C compiler available', 10 unless $have_compiler;

    my $tmpdir = tempdir(CLEANUP => 1);
    my $cc = $Config{cc};
    my $ccflags = $Config{ccflags};
    my $archlib = $Config{archlib};
    my $so_ext = $Config{dlext};
    my $perl = $^X;

    # Write generated files to temp directory
    open my $cfh, '>', "$tmpdir/boolean.c" or die $!;
    print $cfh $result->{files}{'boolean.c'};
    close $cfh;

    open my $hfh, '>', "$tmpdir/boolean.h" or die $!;
    print $hfh $result->{files}{'boolean.h'};
    close $hfh;

    # Copy chalk.h to temp dir
    use File::Copy qw(copy);
    copy('c_src/chalk.h', "$tmpdir/chalk.h") or die "copy chalk.h: $!";

    # Compile generated boolean.c
    my $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir $tmpdir/boolean.c -o $tmpdir/boolean.o 2>&1";
    my $out = `$cmd`;
    is($? >> 8, 0, 'generated boolean.c compiles')
        or diag("Compile failed: $out\nCommand: $cmd");

    # Link into chalk.so
    $cmd = "$cc -shared -fPIC $tmpdir/boolean.o -o $tmpdir/chalk.$so_ext 2>&1";
    $out = `$cmd`;
    is($? >> 8, 0, 'generated boolean.o links into chalk.so')
        or diag("Link failed: $out");

    # Compile Boolean.xs against generated header
    my $xsubpp = "$Config{privlibexp}/ExtUtils/xsubpp";
    my $typemap = "$Config{privlibexp}/ExtUtils/typemap";
    copy('c_src/Boolean.xs', "$tmpdir/Boolean.xs") or die "copy Boolean.xs: $!";

    make_path("$tmpdir/auto/Chalk/Bootstrap/Semiring/Boolean");
    $cmd = "$perl $xsubpp -typemap $typemap $tmpdir/Boolean.xs > $tmpdir/Boolean_xsubpp.c 2>&1";
    $out = `$cmd`;
    is($? >> 8, 0, 'xsubpp processes Boolean.xs') or diag("xsubpp: $out");

    $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir $tmpdir/Boolean_xsubpp.c -o $tmpdir/Boolean.o 2>&1";
    $out = `$cmd`;
    is($? >> 8, 0, 'Boolean.xs compiles') or diag("Compile: $out");

    $cmd = "$cc -shared -fPIC $tmpdir/Boolean.o -o $tmpdir/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext 2>&1";
    $out = `$cmd`;
    is($? >> 8, 0, 'Boolean.so links') or diag("Link: $out");

    # === Verify generated code quality ===
    unlike($result->{files}{'boolean.c'}, qr/_impl_/, 'no _impl_ prefix in generated .c');
    unlike($result->{files}{'boolean.c'}, qr/\bstatic\b[^*]*\bboolean_\w+\(/, 'exported functions are not static');
    like($result->{files}{'boolean.c'}, qr/\bboolean_is_zero\b/, 'uses direct call naming');

    # === Behavioral test in subprocess ===
    # Same pattern as c-boolean-integration.t — load chalk.so with RTLD_GLOBAL,
    # then load Boolean.so which resolves symbols against it.
    # NOTE: The linking here does NOT require explicit -lchalk. Symbols are
    # resolved at load time via RTLD_GLOBAL on chalk.so, same as the
    # hand-crafted pipeline in c-build-pipeline.t.

    # Write behavioral test script to tempfile, run via $perl subprocess.
    # Test all semiring operations: zero, one, is_zero, add, multiply,
    # on_scan, on_complete, should_scan, supports_leo.
    # Print GENERATED_EQUIV_OK on success.

    # ... (follow exact pattern from c-boolean-integration.t Part 1,
    #      using $tmpdir paths for the generated .so files) ...
    # like($out, qr/GENERATED_EQUIV_OK/, 'generated Boolean passes behavioral tests');

    # === Determinism: generate twice, compare ===
    my $result2 = $c->generate_c_files($ir, $sa, $ctx);
    is($result2->{files}{'boolean.c'}, $result->{files}{'boolean.c'},
       'generate_c_files is deterministic (.c)');
    is($result2->{files}{'boolean.h'}, $result->{files}{'boolean.h'},
       'generate_c_files is deterministic (.h)');
}
```

The behavioral test should exercise the same operations as
`t/bootstrap/c-boolean-integration.t` Part 1: zero, one, is_zero, add,
multiply, on_scan, on_complete, should_scan, supports_leo.

- [ ] **Step 2: Run the test**

Run: `perl -Ilib t/bootstrap/c-target-boolean.t`
Expected: If all goes well, PASS. If compilation fails, debug the generated
C code — compare it against the hand-crafted `c_src/boolean.c` to find
differences.

- [ ] **Step 3: Debug and fix until tests pass**

Common issues to expect:
- Missing `SvREFCNT_inc` on singleton returns (Phase 1 lesson)
- `static` keyword still present on exported functions
- `_impl_` prefix still in some call sites
- Missing `#include` or forward declarations
- Variable declaration ordering issues

For each fix, re-run the test. This is iterative — expect 2-5 iterations.

- [ ] **Step 4: Commit when all tests pass**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/C.pm t/bootstrap/c-target-boolean.t
git commit -m "feat: Target/C.pm generates compilable boolean.c passing behavioral tests"
```

---

## Task 5: Verify existing tests still pass

The new C.pm must not break anything. XS.pm is unchanged (we copied, not moved).

**Files:** None (verification only)

- [ ] **Step 1: Run c-build-pipeline.t (hand-crafted pipeline)**

Run: `perl -Ilib t/bootstrap/c-build-pipeline.t`
Expected: All 13 tests PASS (hand-crafted code unchanged)

- [ ] **Step 2: Run c-boolean-integration.t**

Run: `perl -Ilib t/bootstrap/c-boolean-integration.t`
Expected: All 23 tests PASS

- [ ] **Step 3: Run earley-boolean.t**

Run: `perl -Ilib t/bootstrap/earley-boolean.t`
Expected: All tests PASS (pure Perl path unchanged)

- [ ] **Step 4: Run the full bootstrap test suite**

Since XS.pm is unchanged (copy, not move), all existing XS tests should pass:
```bash
perl -Ilib t/bootstrap/*.t 2>&1 | grep -E '^(ok|not ok|#|1\.\.)' | grep 'not ok' || echo "ALL PASS"
```
Expected: No `not ok` lines. If any XS tests fail, investigate — C.pm should
not affect XS.pm in any way.

- [ ] **Step 5: Commit any fixes if needed**

---

## Summary

After completing all 5 tasks:

1. `Target/C.pm` skeleton with `_analyze_class` and `generate_c_files`
2. ~50 emission methods copied from XS.pm, renamed `_emit_c_*`
3. `generate_c_files` wired to produce `.c` + `.h` with direct call naming
4. Generated `boolean.c` compiles and passes behavioral tests
5. Existing tests verified passing

**What's next (separate plans):**
- Wire XS.pm to delegate body emission to C.pm (eliminate duplication)
- Run C.pm on remaining classes (Structural, SemanticAction, FilterComposite, Earley, etc.)
- Build script integration: `build-chalk-so` uses C.pm instead of hand-crafted files
