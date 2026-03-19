# Target/C.pm — C Emitter Design Spec

## Goal

Extract the IR-to-C emission logic from `Target/XS.pm` into a new
`Target/C.pm` module that produces `.c` and `.h` files from IR. This is the
automated emitter that replaces hand-crafting C files per class.

## Architecture

`Target/C.pm` is a standalone class that owns all expression, statement, and
function body emission. `Target/XS.pm` delegates to it for method body
generation and retains ownership of XS-specific concerns (XSUB wrappers,
BOOT blocks, PM stubs).

```
IR (from parser)
    │
    ├──→ Target/C.pm  ──→  boolean.c + boolean.h
    │
    └──→ Target/XS.pm ──→  Boolean.xs (calls C.pm for method bodies)
```

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Relationship to XS.pm | Composition (B+C) | C.pm extracts methods from XS.pm and owns its own state. XS.pm creates C.pm instance and delegates. Future: XS.pm goes away, C.pm is the primary emitter. |
| State management | C.pm owns its fields | field_map, class_methods, cfg_lookup, etc. move to C.pm. XS.pm drops them. |
| API | `generate_c_files()` returns `.c` + `.h` | XS.pm separately produces `.xs`. Each module owns its domain. |
| Cross-class calls | Direct C function calls | `boolean_is_zero(aTHX_ ...)` not `call_method(...)`. The whole point of the redesign. |
| Function naming | `{slug}_{method}` (non-static) | Exported from chalk.so. No `_impl_` prefix — these are the real implementation. |
| Validation | Behavioral equivalence | Generated code must pass same 48 tests as hand-crafted boolean.c. Not byte-identical. |

## Public API

```perl
my $c = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Chalk::Bootstrap::Semiring::Boolean',
);
my $result = $c->generate_c_files($ir, $sa, $ctx);
# Returns: {
#   files => {
#     'boolean.c' => '...',
#     'boolean.h' => '...',
#   },
#   exported_functions => [
#     { name => 'boolean_is_zero', return_type => 'SV *', params => 'pTHX_ SV *self, SV *value' },
#     ...
#   ],
#   skipped_methods => ['method_that_needs_eval_pv', ...],
# }
```

`exported_functions` is accumulated during emission (not parsed from
generated text) and used to produce the `.h` file. It is also available
to XS.pm for generating matching XSUB wrappers.

`skipped_methods` lists methods that could not be fully translated to C.
The caller decides how to handle them (pure Perl fallback, eval_pv, etc.).

## Internal Pipeline

`generate_c_files($ir, $sa, $ctx)` runs this sequence internally:

1. **`_build_cfg_lookup($sa, $ctx)`** — populate `%_cfg_lookup` from
   semantic actions and context (same as XS.pm's existing method)
2. **`_analyze_class($ir)`** — walk the IR's ClassDecl node to populate
   `$field_map`, `$_class_methods`, `%_class_scope_vars`, `%_class_subs`,
   `%_use_constants`. This replaces XS.pm's `_emit_class_sections` for
   the analysis-only portion (no XS output).
3. **Emit class-scope statics** — regex statics, anon sub helpers,
   class-level `my` variables with lazy initializers
4. **Emit methods** — for each method, call `_emit_c_complex_method` to
   produce the function body. Track exported function signatures.
5. **Assemble `.c` file** — preamble + statics + helpers + functions
6. **Assemble `.h` file** — from accumulated `exported_functions`

## Method Extraction

### Group 1: Expression emitters (~18 methods) → C.pm

`_emit_c_expr`, `_emit_c_const_expr`, `_emit_c_binary_expr`,
`_emit_c_unary_expr`, `_emit_c_method_call_expr`,
`_emit_c_subscript_expr`, `_emit_c_postfix_deref_expr`,
`_emit_c_ternary_expr`, `_emit_c_hash_ref_expr`,
`_emit_c_array_ref_expr`, `_emit_c_anon_sub_expr`,
`_emit_c_regex_match`, `_emit_c_regex_subst`,
`_emit_c_builtin_call`, `_emit_c_interp_expr`,
`_emit_c_keys_list`, `_emit_c_backtick_expr`,
`_emit_c_compound_assign_expr`, `_emit_c_var_decl_expr`

### Group 2: Statement emitters (~7 methods) → C.pm

`_emit_c_stmt`, `_emit_c_var_decl`, `_emit_c_return_stmt`,
`_emit_c_die_call`, `_emit_c_compound_assign_stmt`,
`_emit_c_loop_jump`, `_emit_c_interp_return`

### Group 3: Function-level emitters (~3 methods) → C.pm

`_emit_c_complex_method`, `_emit_c_sub`, `_emit_c_method`

Note: `_emit_xs_eval_fallback` does NOT move to C.pm. The parent spec
says "no eval_pv fallback within compiled code." If a method cannot be
fully translated to C, `generate_c_files` omits it from the `.c` output
and returns a list of skipped methods. The caller (XS.pm or build script)
decides whether to handle them as pure Perl.

### Group 4: Control flow emitters (~4 methods) → C.pm

`emit_cfg_if`, `emit_cfg_phi_if`, `emit_cfg_loop`,
`emit_cfg_try_catch`

These emit C `if/else`, value-producing if, `for/while/foreach`, and
try-catch patterns. Called from `_emit_c_stmt` when `%_cfg_lookup` has
an entry for the current IR node.

### Group 5: Helper/analysis methods → C.pm

`_body_contains_return`, `_is_bare_return_expr`,
`_is_unambiguous_value_expr`, `_is_single_stmt_return_expr`,
`_collect_var_decls`, `_collect_all_var_refs`,
`_build_field_index_map`, `_scan_class_methods`,
`_build_cfg_lookup`, `_class_slug`,
`_fixup_xs_list_destructuring`, `_fixup_ternary_assignment`

The `_fixup_*` methods are regex-based post-processors that rewrite
generated C text. They are fragile but necessary for Earley-class
compilation. They move to C.pm as-is for now; replacing them with
IR-level fixes is future work.

### Group 6: Stays in XS.pm

`_emit_xs_preamble`, `_emit_xs_boot_block`,
`_emit_xs_boot_block_inner`, `_emit_class_sections`,
`_emit_xs_eval_fallback`

`_emit_class_sections` stays because it orchestrates the XS-specific
output (MODULE/PACKAGE sections, XSUB wrappers). C.pm has its own
`_analyze_class` method for IR analysis (see Internal Pipeline below).

### Key behavioral changes in C.pm

1. Cross-class method calls emit `classname_method(aTHX_ ...)` (direct
   C function calls) instead of `call_method(...)`. This eliminates the
   Perl/C bridge overhead that motivated the entire redesign.

2. CV cache logic (`$_cv_cache`, `$_param_fields`) is NOT extracted.
   Same-class calls become direct `{slug}_{method}(aTHX_ self, ...)`
   calls. Cross-class calls become `{target_slug}_{method}(aTHX_ ...)`
   calls. No caching needed — all calls are direct C function calls.

3. Cross-class call resolution depends on type information to map an
   invocant to a target slug. For Phase 1 (Boolean has no cross-class
   calls), this is not needed. For Phase 4 (Earley calling Boolean),
   the mechanism is the existing `$_composite_field_types` or
   `:param` field type annotations.

## State Fields

### Moved to C.pm (owns these)

| Field | Purpose |
|-------|---------|
| `$module_name` | `:param` — class being compiled |
| `$field_map` | field name → index for ObjectFIELDS access |
| `$field_sigils` | field name → sigil ($, @, %) |
| `%_cfg_lookup` | IR node → cfg_state entry (if/loop detection) |
| `$_return_context` | true when emitting a returning method body |
| `$_loop_depth` | loop nesting depth |
| `$_class_methods` | name → { returns, params } for same-class calls |
| `$_regex_counter` | counter for `_rx_N` static names |
| `$_regex_statics` | arrayref of { var, pat } for REGEXP* statics |
| `%_class_scope_vars` | class-level lexicals (e.g., `$ZERO`) |
| `%_class_subs` | class-scope sub declarations |
| `%_use_constants` | `use constant` values |
| `@_anon_sub_helpers` | static C functions for anon subs |
| `$_anon_sub_counter` | counter for unique anon sub names |
| `$_current_slug` | class-derived prefix (e.g., `boolean`) |

### Stays in XS.pm (XS-specific)

`$_cv_cache`, `$_param_fields`, `$_semiring_intrinsics`,
`$_class_registry`, `$_composite_field_types`,
`%_multi_class_methods`, `%_fallback_method_slugs`,
`@_anon_sub_fwd_decls`, `@_anon_sub_boot`

## Output Format

### .c file structure

```c
/* ABOUTME: C implementation of {ClassName} (generated by Target::C). */
/* ABOUTME: {description from source file}. */
#include "chalk.h"
#include "{slug}.h"

/* File-scope statics: regex, anon CVs, class-scope vars */
static SV *_rx_{slug}_0 = NULL;
static SV *_{slug}_ZERO = NULL;

/* Static helpers (my sub, anon subs — not exported).
   File-scoped statics don't need slug prefix since they can't collide
   across .c files, but we use _{slug}_ prefix for consistency with
   the exported naming convention. */
static SV * _{slug}_helper(pTHX_ ...) { ... }

/* Exported functions (one per method) */
SV * {slug}_is_zero(pTHX_ SV *self, SV *value) { ... }
SV * {slug}_add(pTHX_ SV *self, SV *a, SV *b) { ... }
```

### .h file structure

```c
/* ABOUTME: Function prototypes for {ClassName} C implementation (generated). */
/* ABOUTME: Included by other .c files that call {slug} functions directly. */
#ifndef CHALK_{SLUG}_H
#define CHALK_{SLUG}_H
#include "chalk.h"

SV * {slug}_is_zero(pTHX_ SV *self, SV *value);
SV * {slug}_add(pTHX_ SV *self, SV *a, SV *b);
/* ... one prototype per exported function */

#endif
```

The `.h` is generated from the `exported_functions` list accumulated
during `.c` emission — not by parsing the generated C text. Each entry
has return type, function name, and parameter list, which are formatted
as a prototype line with a trailing semicolon.

### Class-scope variables

Class-level `my` variables (like Boolean's `my $ZERO = []`) are emitted as
file-scope statics with a lazy initializer function, following the same
pattern as the hand-crafted `_boolean_ZERO` + `_get_zero()`.

## How XS.pm Uses C.pm

```perl
# In XS.pm's generate_distribution_with_cfg:
my $c_emitter = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => $module_name,
);
my $c_files = $c_emitter->generate_c_files($ir, $sa, $ctx);
# $c_files->{'boolean.c'} has the implementation
# $c_files->{'boolean.h'} has the prototypes

# XS.pm then generates Boolean.xs using its own BOOT/XSUB emitters,
# referencing the function names from the .h file
```

## Testing Strategy

**Primary validation:** C.pm-generated code must pass the same 48 behavioral
tests that the hand-crafted `boolean.c` passes.

**Test flow:**
1. Parse `lib/Chalk/Bootstrap/Semiring/Boolean.pm` → IR
2. Feed IR to `Target::C->generate_c_files()` → generated `boolean.c` + `boolean.h`
3. Write to temp directory
4. Compile `chalk.so` from generated `boolean.c`
5. Compile `Boolean.xs` (Phase 1 hand-crafted) against it
6. Load and run behavioral tests: semiring operations + Earley integration

**Test file:** `t/bootstrap/c-target-boolean.t`

**Success criteria:** Generated `boolean.c` compiles and passes all behavioral
tests. Not byte-identical to hand-crafted version — behavioral equivalence
only.

## Phase 1 Lessons Applied

From the hand-crafted pipeline (documented in memory):
- `PROTOTYPES: DISABLE` in all .xs files
- Forward-declare `Perl_class_setup_stash` (guarded by `PERL_IN_CLASS_C`)
- `SvREFCNT_inc` on singleton returns (sv_2mortal in xsubpp OUTPUT path)
- Load through stub `.pm` via `require` (class_setup_stash needs PL_compcv)
- RTLD_GLOBAL (0x01) for chalk.so symbol visibility
