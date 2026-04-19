# XS.pm EmitHelpers Refactor Design

> **ARCHIVED.** Step A (extract shared code into `EmitHelpers` as a class)
> **landed** — `EmitHelpers.pm` is a `feature class` that `Target/C.pm`
> inherits from. Step B (have `XS.pm` inherit from `EmitHelpers`) became
> **moot**: Chalk pivoted away from a hand-written `Target/XS.pm` class
> toward generating C from the IR and using per-class thin XS wrappers
> that bind into a shared `chalk.so` library. No `Target/XS.pm` exists
> to inherit. See memory note `xs_target_evolution.md` for the narrative.
> Preserved for history.

**Goal:** Eliminate code duplication between XS.pm and EmitHelpers/C.pm in two steps.

**Architecture:** Two-phase refactor:
- **Step A**: XS.pm inherits from EmitHelpers (eliminate 36 duplicate methods + 12 duplicate fields)
- **Step B**: Unify 29 body emission methods into EmitHelpers (eliminate `_emit_c_*`/`_emit_xs_*` duplication)

## Current State

```
Target (abstract: generate/generate_distribution)
  └── XS.pm (5933 lines, 36 duplicated helpers, 29 duplicated emitters)

EmitHelpers (1286 lines, 34 shared methods, 12 shared fields)
  └── C.pm (2747 lines, uses accessor methods for parent fields)
```

## Step A: XS.pm Inherits from EmitHelpers

### Inheritance Chain Change

```
Target (abstract)
  └── EmitHelpers (add :isa(Target))
        ├── C.pm (unchanged)
        └── XS.pm (change from :isa(Target) to :isa(EmitHelpers))
```

### Fields to Remove from XS.pm (now inherited)

These 10 fields are exact duplicates of EmitHelpers fields:
- `$field_map`, `$field_sigils`, `%_cfg_lookup`, `$_return_context`, `$_loop_depth`
- `$_class_methods`, `%_class_scope_vars`, `%_class_subs`, `$_current_slug`, `$_param_fields`

### Fields to Move from XS.pm/C.pm to EmitHelpers (shared but not yet in EmitHelpers)

- `$module_name :param :reader` (both C.pm and XS.pm have this)
- `$_regex_counter`, `$_regex_statics`, `%_use_constants` (both C.pm and XS.pm have this)

### Methods to Remove from XS.pm (now inherited)

36 methods that are exact copies of EmitHelpers methods. See the exploration analysis
for the full list.

### New Accessor Methods Needed in EmitHelpers

For fields that XS.pm accessed directly and now needs accessor methods:
- `_get_class_methods()`, `_get_module_name()`
- `_get_regex_counter()`, `_inc_regex_counter()`, `_reset_regex_counter()`
- `_get_regex_statics()`, `_reset_regex_statics()`, `_push_regex_static($entry)`
- `_get_use_constants()`, `_reset_use_constants()`, `_set_use_constant($name, $val)`
- `_inc_loop_depth()`, `_dec_loop_depth()`

### Field Access Conversion in XS.pm

All direct field references in XS.pm methods that remain must be converted to
accessor method calls. Key counts:
- `$field_map` → `$self->_get_field_map()` (~40 sites)
- `%_cfg_lookup` → `$self->_get_cfg_lookup()` (~15 sites)
- `$_class_methods` → `$self->_get_class_methods()` (~20 sites)
- `$_return_context` → `$self->_get_return_context()` / `$self->_set_return_context()` (~8 sites)
- `$_loop_depth` → `$self->_get_loop_depth()` / `$self->_inc_loop_depth()` (~12 sites)
- `%_class_scope_vars` → `$self->_get_class_scope_vars()` (~18 sites)
- `%_class_subs` → `$self->_get_class_subs()` (~6 sites)
- `%_use_constants` → `$self->_get_use_constants()` (~2 sites)
- `$_current_slug` → `$self->_get_current_slug()` (~12 sites)
- `$_param_fields` → `$self->_get_param_fields()` (~4 sites)
- `$module_name` → `$self->_get_module_name()` or `$self->module_name()` (~15 sites)

### XS.pm-Only Fields (stay in XS.pm)

- `$_cv_cache`, `$_semiring_intrinsics`, `$_class_registry`
- `$_composite_field_types`, `%_multi_class_methods`, `%_fallback_method_slugs`
- `@_anon_sub_fwd_decls`, `@_anon_sub_helpers`, `@_anon_sub_boot`, `$_anon_sub_counter`

## Step B: Unified Body Emission (future)

Move 29 shared `_emit_*` methods from C.pm and XS.pm into EmitHelpers with
neutral names. Each target overrides only the methods that diverge:
- XS.pm: `_emit_method_call_expr` (5 extra dispatch paths), 4 XS-only methods
- C.pm: `_emit_init_expr` (C-only)

This step depends on Step A completing cleanly, because both targets must use
the same accessor pattern before method bodies can be compared for unification.

## Validation

### Test Coverage
- 31 XS test files (`t/bootstrap/xs-*.t`)
- 10 C test files (`t/bootstrap/c-*.t`)
- `t/bootstrap/c-emit-helpers-inheritance.t` (54 tests for EmitHelpers)

All tests must pass unchanged after each step.
