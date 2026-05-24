# Target::C Migration Audit

**Date:** 2026-05-24
**For:** Phase 7 scope planning — migrate `Chalk::Bootstrap::Perl::Target::C`
from the legacy `Chalk::IR::Program` + Info-struct + `cfg_state`
shape to MOP + `Chalk::IR::Schedule` + ScheduleMeta. Phase 7 is
named in `docs/plans/2026-05-24-son-scheduler-design.md` §7 as the
unblock for the final transitional-infrastructure deletion (Program,
the Info-struct types, `cfg_state`, the `emit_cfg_*` helpers, and
`MOP::Method->body`).
**Status:** Read-only audit. No code modified. The remediation step
is a separate session.

## Scope

Audited:

- `lib/Chalk/Bootstrap/Perl/Target/C.pm` (2161 lines) — the XS/C
  target.
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (2523 lines) —
  the parent class of Target::C; after Phase 5 Target::Perl no
  longer inherits from it, so Target::C is the sole production
  inheritor.
- `t/bootstrap/lib/TestXSHelpers.pm` (297 lines) — the test harness
  used by all XS-target tests.

Consulted (not audited, used as blueprint or context):

- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` lines 77-326 (the
  Phase-5b `_generate_from_schedule` / `_emit_scheduled_body` /
  `_emit_schedule_item` pattern; the schedule_data gate at
  `_emit_foreach_head`, `_emit_for_head`, `_emit_catch_head`).
- `lib/Chalk/IR/Scheduler/EagerPinning.pm` (the scheduler whose
  `schedule($method)` Target::C will call).
- `lib/Chalk/Scheduler/EagerPinning/{If,Loop,Phi,TryCatch}.pm`
  (the ScheduleMeta subclasses C-target codegen will gate against).
- `script/build-chalk-so-generated` (production caller of
  `_generate_c_files` / `generate_xs_wrapper`).
- `docs/plans/2026-05-24-legacy-ir-consumer-audit.md` §
  `lib/Chalk/Bootstrap/Perl/Target/C.pm` (lines 295-384, the prior
  audit of consumer patterns) and § EmitHelpers (lines 236-294).
- `docs/plans/2026-05-24-codegen-test-triage.md` — XS tests are
  classified as REWRITE deferred to Phase 7; that triage is not
  re-done here.

The audit follows the established `2026-05-24-legacy-ir-consumer-audit.md`
format.

## 1. Entry points

Three production-relevant entry points; one stub:

### 1a. `_generate_c_files($ir, $sa, $ctx)` — C.pm:1521

The real production entry. Inputs:

- `$ir` — a `Chalk::IR::Program` tree (root of the parsed file).
- `$sa` — the SemanticAction semiring instance from the parse.
- `$ctx` — the top-level `Chalk::Bootstrap::Context` returned by
  the parser.

Step-by-step:

1. Stores `$sa`/`$ctx` on EmitHelpers fields (`_set_sa`/`_set_ctx`),
   so downstream emit helpers can call `$_ctx->cfg_state()` via
   `emit_from_cfg_state` (EmitHelpers.pm:1363).
2. Resets per-generation state (regex statics, anon-sub registrations,
   skipped-methods, `%_cfg_lookup`).
3. Precomputes `field_name => slug` map for cross-class direct calls.
4. Builds the type-aware dispatch tables (`$_method_dispatch`,
   `$_polymorphic_dispatch`) from `$compiled_class_metadata`.
5. If `$sa` is defined, calls `_build_cfg_lookup($sa, $ctx)` (C.pm:1604)
   — this populates `%_cfg_lookup` (a `refaddr → cfg_state` table)
   that downstream emit helpers consult via `$self->_get_cfg_lookup()`.
6. Calls `_analyze_class($ir)` (C.pm:1607) — walks the Program for
   the ClassInfo, sets the class slug, builds field index map, scans
   class methods, collects class-scope vars, scans `use constant`.
7. Iterates `$class_decl->body()` to emit class-scope subs (SubInfo,
   C.pm:1621-1639) and methods (MethodInfo, C.pm:1642-1664).
8. Assembles the `.c` file: includes, struct typedefs, file-scope
   statics, stash statics, regex statics, anon-sub CV statics, static
   helper functions, an `${slug}_init_statics` function (called from
   BOOT), and the exported method functions.
9. Assembles the `.h` file: include guard + prototypes sorted by name.

Output:

```
{
  files => {
    "${slug}.c" => "...",
    "${slug}.h" => "...",
  },
  exported_functions     => [...],   # for generate_xs_wrapper to consume
  skipped_methods        => [...],
  anon_sub_registrations => [...],
}
```

### 1b. `generate_xs_wrapper($ir, $exported_functions, $anon_sub_registrations)` — C.pm:1875

Takes the Program IR (again) plus the metadata returned by
`_generate_c_files`. Produces the per-class `.xs` wrapper as a single
string.

Walks `$ir` only to (a) find the ClassInfo for parent class
extraction (C.pm:2030-2047) and (b) iterate `$class_decl->body()`
again for FieldInfo registration in the BOOT block (C.pm:2050-2095).

Produces XSUB declarations from `$exported_functions` (purely a list
of `{name, return_type, params}` hashrefs — *no IR dependency*) and
a BOOT block that:
- sets up the stash via `Perl_class_setup_stash`;
- registers `:isa(...)` if the class has a parent;
- registers each field via `Perl_class_prepare_initfield_parse` +
  `pad_add_name_pvs` + `Perl_class_apply_field_attributes`;
- emits defops for fields with default values;
- registers `_ADJUST` as an ADJUST block if present;
- calls `${slug}_init_statics(aTHX)`.

### 1c. `generate($mop)` — C.pm:1479 (STUB)

The MOP-shaped entry that *does not* dispatch to `_generate_c_files`.
Iterates `$mop->classes()` and emits skeleton output only:

```
/* Generated C source for class Foo */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
/* method: bar */
/* method: baz */
```

No real C bodies, no `.h` file, no exported_functions, no init_statics.
The skeleton is what `t/bootstrap/mop/codegen-no-backchannel.t` and
similar tests assert against to verify the MOP signature exists; no
production caller routes through it. Production
(`script/build-chalk-so-generated`) calls `_generate_c_files`
directly.

This stub is what the legacy-IR-consumer audit flagged as "the
real work is done by `_generate_c_files`."

### 1d. Tests-only entry points

None. All XS-target tests reach `_generate_c_files` and
`generate_xs_wrapper` either directly or through
`TestXSHelpers::build_and_load`.

### 1e. Naming bug in `script/build-chalk-so-generated`

The build script at script/build-chalk-so-generated:140-146 and 289-294
calls `$target->generate_c_files(...)` (no leading underscore). No
method by that public name exists in `Target::C` or `EmitHelpers`
(`grep -n "method generate_c_files\b"` returns nothing in `lib/`).
A test at `t/bootstrap/mop/codegen-no-backchannel.t:17-18`
explicitly asserts `!Target::C->can('generate_c_files')` — so the
absence is *intentional* on the target side.

This means one of the following is true:

- The build script is broken (would die `Can't locate object method
  "generate_c_files"`).
- The build script is never run by CI / regression and the broken
  call has not been noticed.

The audit's brief did not include running the build script, so I
have not confirmed which. Flagging as an open question in §10.

## 2. Legacy IR shape dependencies

### 2a. Accessor reads on `->body()` (Program / Info structs)

| File:line | Site | Notes |
|---|---|---|
| C.pm:58 | `$class_decl->body()` in `_analyze_class` | iterates body for class-scope vars + `use constant` |
| C.pm:128 | `$method_decl->body()` in `_emit_method` | the MethodInfo branch only |
| C.pm:1617 | `$class_decl isa ClassInfo ? body() : inputs()->[2]` | dual-path; ClassInfo branch live, fallback dead — see §8 |
| C.pm:1625 | `$item->body()` in class-scope sub iteration (SubInfo) | |
| C.pm:1774 | same dual-path as 1617, in init_statics emission | |
| C.pm:2052 | `$class_decl->body()` in XS BOOT block field iteration | |
| EmitHelpers.pm:130 | `$class_decl->body()` in `_build_field_index_map` | called by `_analyze_class` |
| EmitHelpers.pm:207 | `$class_decl->body()` in `_scan_class_methods` | called by `_analyze_class` |

8 reads of `->body()` across the two files (6 in C.pm + 2 in
EmitHelpers). All need to migrate to either MOP iteration
(`$cls->fields`, `$cls->methods`, `$cls->subs`, `$cls->imports`)
or graph-walking (Phase 7 design doc commits to graph-walking for
the per-method body specifically).

### 2b. Reads of `->classes()` / `->top_level_subs()` etc. on `Chalk::IR::Program`

| File:line | Site |
|---|---|
| EmitHelpers.pm:120 | `$ir->classes()->@*` in `_find_class_decl` |

Only one site in the C-target codebase, and it's in EmitHelpers.
`_find_class_decl` is called from `Target::C::_generate_c_files`
(C.pm:1610) and `Target::C::generate_xs_wrapper` (C.pm:1877). The
function picks the first `ClassInfo` from `$ir->classes()`.

The Program also has `top_level_subs`, `other_stmts`, `use_decls`
fields, but `Target::C` reads none of those directly — its
top-level handler is "find *the* class" (Target::C is per-class).
Migration: replace with `$mop->classes()` iteration.

### 2c. isa-dispatch sites on Info-struct types

| File:line | Site | Branch live in production? |
|---|---|---|
| C.pm:79 | `$init isa Chalk::IR::SubInfo` (class-scope VarDecl filter) | live |
| C.pm:98 | `$item isa Chalk::IR::UseInfo` (`use constant` scan) | live |
| C.pm:126 | `$method_decl isa Chalk::IR::MethodInfo` (`_emit_method` dual-path) | true-branch live; else-branch dead (see §8) |
| C.pm:236 | `$method_decl isa Chalk::IR::MethodInfo` (return-type extraction) | true-branch live; else-branch dead |
| C.pm:1616 | `$class_decl isa Chalk::IR::ClassInfo` (body extract) | dead else-branch |
| C.pm:1622 | `$item isa Chalk::IR::SubInfo` (sub emission filter) | live |
| C.pm:1643 | `$item isa Chalk::IR::MethodInfo` (method emission filter) | live |
| C.pm:1773 | `$class_decl isa Chalk::IR::ClassInfo` (init_statics body extract) | dead else-branch |
| C.pm:2032 | `$class_decl isa Chalk::IR::ClassInfo` (XS BOOT parent extract) | dead else-branch |
| C.pm:2054 | `$item isa Chalk::IR::FieldInfo` (XS BOOT field registration filter) | live |
| EmitHelpers.pm:121 | `$stmt isa Chalk::IR::ClassInfo` (`_find_class_decl`) | live |
| EmitHelpers.pm:138 | `$item isa Chalk::IR::FieldInfo` (`_build_field_index_map`) | live |
| EmitHelpers.pm:218 | `$item isa Chalk::IR::Node || isa MethodInfo || isa SubInfo` (scan) | live |
| EmitHelpers.pm:224 | `$init isa Chalk::IR::SubInfo` (mis-parented sub) | live |
| EmitHelpers.pm:232 | `$item isa Chalk::IR::MethodInfo` (scan dispatch) | live |
| EmitHelpers.pm:247 | `$item isa Chalk::IR::SubInfo` (scan dispatch) | live |
| EmitHelpers.pm:271 | `$item isa Chalk::IR::FieldInfo` (`:reader` scan) | live |

17 isa-dispatch sites total; 6 are dead Constructor-fallback
else-branches (see §8). The remaining 11 must migrate to
MOP-entity dispatch (`$item isa Chalk::MOP::Method`, etc.) or be
re-expressed as direct iteration over typed MOP accessors
(`$cls->methods` / `$cls->fields` / etc. already return typed
lists, eliminating the need for inline filtering).

### 2d. Construction of legacy Info-structs

| File:line | Site |
|---|---|
| C.pm:131-135 | `$factory->make('Constant', ..., value => $param_name_string)` |

C.pm constructs Constant nodes inside `_emit_method` (C.pm:131-135)
to normalize MOP's plain-string params into the same shape the
Constructor-shaped legacy path uses. This is *not* legacy-IR
construction — it's a synthesis bridge that exists *because*
downstream code (`_emit_complex_method`, `_emit_xs_*` helpers)
expects param nodes shaped as `Chalk::IR::Node::Constant`.

When `_emit_method` migrates to the schedule path, this synthesis
becomes unnecessary (the schedule items carry node references; the
method body's parameters are addressable directly via the MOP).

**Target::C constructs no Info-struct types.** It is purely a
consumer.

## 3. EmitHelpers usage

Target::C `:isa(EmitHelpers)` (C.pm:28). After the Phase 5
Target::Perl migration, Target::C is the sole production inheritor
of EmitHelpers.

### 3a. Methods Target::C calls on `$self` that are defined in EmitHelpers

From `grep '$self->...' lib/Chalk/Bootstrap/Perl/Target/C.pm` cross-checked
against EmitHelpers method definitions. The inherited surface is:

**State accessors** (small / mechanical):
- `module_name`, `_class_slug`, `_xs_c_type_for`, `_escape_c_string`
- `_get_field_map`, `_set_field_map`, `_get_field_sigils`,
  `_set_field_sigils`, `_get_param_fields`, `_set_param_fields`
- `_get_current_slug`, `_set_current_slug`
- `_get_current_sub_name`, `_set_current_sub_name`
- `_get_class_methods`, `_set_class_methods`,
  `_set_class_method`, `_delete_class_method`
- `_get_class_scope_vars`, `_reset_class_scope_vars`,
  `_set_class_scope_var`
- `_get_class_subs`, `_reset_class_subs`, `_set_class_sub`,
  `_set_class_sub_compiled`
- `_get_return_context`, `_set_return_context`
- `_get_loop_depth`, `_inc_loop_depth`, `_dec_loop_depth`
- `_get_regex_counter`, `_inc_regex_counter`, `_reset_regex_counter`
- `_get_regex_statics`, `_reset_regex_statics`, `_push_regex_static`
- `_get_use_constants`, `_reset_use_constants`, `_set_use_constant`
- `_get_struct_schemas`, `set_struct_schemas`
- `_get_cfg_lookup`, `_reset_cfg_lookup`
- `_set_sa`, `_set_ctx`

**IR analysis helpers** (called from `_analyze_class`):
- `_find_class_decl` — Program walker; takes Program-IR, returns ClassInfo
- `_build_field_index_map` — takes ClassInfo, returns hashref
- `_scan_class_methods` — takes ClassInfo, returns method-info hashref
- `_scan_field_method_calls` — takes ClassInfo (EmitHelpers.pm:591)

**Body analysis helpers** (Phase 7 will partially retire these
when schedule replaces body iteration):
- `_collect_var_decls`, `_collect_all_var_refs`
- `_has_early_return`, `_body_contains_return`,
  `_body_contains_bare_return`
- `_is_bare_return_expr`, `_is_unambiguous_value_expr`,
  `_is_single_stmt_return_expr`
- `_is_complex_method`
- `_wrap_retval`, `_sv_true_wrap`, `_ir_default_to_perl`

**Per-node emit helpers** (the bulk of EmitHelpers, ~1100 lines):
- `_emit_stmt` (the inner per-statement dispatcher — itself reads
  `_cfg_lookup`)
- `_emit_expr` (top-level expression dispatcher; ~800 lines of
  per-node-type branches)
- `_emit_const_expr`, `_emit_interp_expr`, `_emit_binary_expr`,
  `_emit_unary_expr`, `_emit_subscript_expr`,
  `_emit_postfix_deref_expr`, `_emit_ternary_expr`,
  `_emit_hash_ref_expr`, `_emit_array_ref_expr`,
  `_emit_regex_match`, `_emit_regex_subst`, `_emit_keys_list`,
  `_emit_backtick_expr`, `_emit_compound_assign_expr`,
  `_emit_var_decl_expr`, `_emit_var_decl`, `_emit_return_stmt`,
  `_emit_die_call`, `_emit_compound_assign_stmt`, `_emit_loop_jump`,
  `_emit_struct_ref_expr`, `_emit_field_access_expr`
- `emit_struct_ref`, `emit_field_access` (public-name aliases for
  the struct-promotion path)
- `generate_typedefs`

**`emit_cfg_*` helpers** (the legacy control-flow emitters,
all called from `_emit_stmt`'s `_cfg_lookup` dispatch at
EmitHelpers.pm:1411-1453):
- `emit_cfg_if` — emit if/elsif/else from cfg_state
- `emit_cfg_phi_if` — emit if + Phi assignment
- `emit_cfg_loop` — emit while/foreach/for from cfg_state
- `emit_cfg_try_catch` — emit JMPENV_PUSH/POP try/catch
- `emit_from_cfg_state` — top-level dispatcher on `$_ctx->cfg_state()`
- `_emit_loop_jump` — emit bare next/last

These are the helpers the design doc §7 Phase 6 list (lines
1287-1294, Amendment 6) calls out as "Target::C *is* the user."
The schedule migration replaces them.

### 3b. Methods Target::C overrides or shadows

None. Target::C does not redefine any EmitHelpers method. Its
`_emit_method` (C.pm:124), `_emit_complex_method` (C.pm:246),
`_emit_sub` (C.pm:376), `_emit_interp_return` (C.pm:1386),
`_emit_init_expr` (C.pm:1443), and `_emit_defop_for_xs_wrapper`
(C.pm:2126) are all Target::C-only (not in EmitHelpers).

### 3c. Fields/state that survive on EmitHelpers after Phase 7

The state accessors in §3a are mostly target-agnostic (class slug,
field map, regex counter, struct schemas). These survive the
migration unchanged.

The cfg-related state (`%_cfg_lookup`, `$_sa`, `$_ctx`,
`_get_cfg_lookup`, `_reset_cfg_lookup`, `_set_sa`, `_set_ctx`)
is the part that goes away. The replacement is the typed
schedule_data side of each control-flow node (per design doc §10).

## 4. cfg_state integration

### 4a. Where Target::C uses cfg_state

Only one explicit call site in C.pm:

- C.pm:1604 — `$self->_build_cfg_lookup($sa, $ctx)` in
  `_generate_c_files`, when `$sa` is defined.

That call populates the inherited `%_cfg_lookup` field on
EmitHelpers (defined at EmitHelpers.pm:36).

C.pm also has:

- C.pm:1522 — `$self->_set_sa($sa)`
- C.pm:1523 — `$self->_set_ctx($ctx)`
- C.pm:1533 — `$self->_reset_cfg_lookup()`

These manage the EmitHelpers field state that `emit_from_cfg_state`
(EmitHelpers.pm:1363) reads later via `$_ctx->cfg_state()`.

That is the *full* surface of cfg_state Target::C touches
directly. The actual *consumption* is in EmitHelpers' `_emit_stmt`
(EmitHelpers.pm:1411-1453), which Target::C inherits.

### 4b. How `_emit_stmt` consumes `%_cfg_lookup`

`_emit_stmt` (EmitHelpers.pm:1407) is the per-statement emit
dispatcher. It is called from C.pm:295 (in `_emit_complex_method`)
and C.pm:434 (in `_emit_sub`) for each item of the method/sub
body arrayref.

For each `$node`, it queries `$self->_get_cfg_lookup()` by
`refaddr($node)`. If a `cfg_state` entry exists, it dispatches
to one of:

- `_emit_loop_jump($state->{loop_jump}, $state->{if_node}, ...)`
  — for postfix `next if`, `last unless`, etc.
- `emit_cfg_if($state->{if_node}, $state->{true_proj},
  $state->{false_proj}, ..., $state->{then_stmts},
  $state->{else_stmts})`
- `emit_cfg_loop($state->{loop}, $state->{loop_if},
  $state->{body_proj}, $state->{exit_proj}, ...,
  $state->{body_stmts}, $state->{iterator}, $state->{list})`
- `emit_cfg_try_catch($state->{try_stmts}, $state->{catch_var},
  $state->{catch_stmts}, ...)`

If no cfg_state entry exists, falls through to the typed-node
fast-path (VarDecl/Return/Unwind/etc.) or to `_emit_expr` for
unrecognized nodes.

The `cfg_state` hashref schema is rich: `{if_node, true_proj,
false_proj, then_stmts, else_stmts, loop_jump, loop, loop_if,
body_proj, exit_proj, body_stmts, iterator, list, try_node,
try_stmts, catch_var, catch_stmts, scope, ...}`.

The schedule-driven equivalent collapses this scattered hashref
into typed `EagerPinning::If` / `EagerPinning::Loop` /
`EagerPinning::TryCatch` / `EagerPinning::Phi` instances attached
to the relevant IR node via `$node->schedule_data` (design doc §10).

### 4c. Other cfg_lookup consumer sites in EmitHelpers

`%_cfg_lookup` is read in 4 additional analysis routines that
recurse into structured control flow:

- `_has_early_return` (EmitHelpers.pm:676) — walks then/else/body
  stmts to detect any early Return.
- `_body_contains_return` (EmitHelpers.pm:705) — same, for the
  "does this body have any Return" check.
- `_collect_var_decls` (EmitHelpers.pm:786) — recurses into
  then/else/body/try/catch stmts to collect VarDecl names.
- `_collect_all_var_refs` (EmitHelpers.pm:878) — same, for all
  variable references.

These are called from C.pm's `_emit_complex_method`
(`_collect_var_decls` at C.pm:285, `_collect_all_var_refs` at
C.pm:286, `_has_early_return` at C.pm:288) and `_emit_sub`
(C.pm:425-428).

The schedule path has to provide equivalent visibility:
schedule walking gives a flat sequence of items, but the
analyses above walk the *nested* structure (recursing into
branch/loop bodies). The natural shape is walking the method's
graph directly for these analyses (the same way the scheduler
does), and they probably become graph-iteration helpers rather
than schedule-iteration helpers.

### 4d. cfg_state population path (for context)

cfg_state is populated by `Chalk::Bootstrap::Perl::SemanticAction`
during the parse. After the parse it lives on each `Context` node;
the snapshot at parse time is what `TestXSHelpers::parse_file_ir`
captures into `\%cfg_snapshot` (TestXSHelpers.pm:73-83).

The snapshot exists because `SemanticAction`'s `%_cfg_state` is a
class-scope lexical wiped by `reset_cache()` between parses; the
snapshot pins it for `_build_cfg_lookup` to use later.

When the schedule replaces cfg_state, the snapshot mechanism
disappears entirely — `schedule_data` lives on the IR node
itself, persists with the node, and is not reset on subsequent
parses.

## 5. XS pipeline mechanics

### 5a. Three-file output

For each compiled class, Target::C produces three artifacts:

- `${slug}.c` — the C implementation. Contains: includes,
  struct typedefs (from struct promotion), file-scope statics
  (class-scope lexicals), polymorphic stash statics, regex
  REGEXP* statics, anon-sub CV statics, static helper functions
  (class-scope subs, anon subs), the `${slug}_init_statics(pTHX)`
  one-shot initializer, and the exported method functions.
- `${slug}.h` — the include header. Contains: include guard,
  `#include "chalk.h"`, and sorted prototypes for every exported
  function (used by other classes that direct-call into this one).
- `${slug}.xs` — the thin XS wrapper. Contains: preamble, MODULE
  line, optional `_ADJUST` void XSUB, one XSUB per exported method
  (`RETVAL = ${func_name}(aTHX_ ...)`), and the BOOT block that
  registers stash, parent class, fields, ADJUST, and calls
  `${slug}_init_statics`.

The build system (`script/build-chalk-so-generated`) compiles all
the `.c` files into a single `chalk.so` shared library. Per-class
`.xs` wrappers link against `chalk.so` and live as standalone
`.so` files; the `.pm` stub uses `XSLoader::load` to pull in the
per-class `.so`.

### 5b. Method/sub → XS export relationship

Class-scope subs (`Chalk::IR::SubInfo`) → static C helpers, name
`${slug}_${subname}`. Not in the `.h`, not exposed as XSUB. Called
from within other emitted C code via the direct-call optimization.

Methods (`Chalk::IR::MethodInfo`) → exported C functions, name
`${slug}_${methname}`. Listed in `.h` for cross-class direct calls,
and wrapped by a thin XSUB in the `.xs` file.

Anon subs (parsed inline as `Chalk::IR::Node::AnonSub`) → static
C helpers + an XSUB registration in `${slug}_init_statics` that
creates a CV under a synthetic package name (e.g. `::_anon_earley_0`)
for `call_sv` dispatch.

Fields (`Chalk::IR::FieldInfo`) → registered in the BOOT block via
`pad_add_name_pvs` + attribute application. No C-level emission
beyond the registration; field accesses compile to
`ObjectFIELDS(SvRV(self))[$index]`.

### 5c. Struct-promotion integration

`set_struct_schemas` (EmitHelpers.pm:99) is called by the build
script (build-chalk-so-generated:136) before `_generate_c_files`,
passing the schemas computed by
`Chalk::Bootstrap::Optimizer::StructPromotion`.

`generate_typedefs` (EmitHelpers.pm:2485) emits C `typedef struct
{ ... }` declarations into the `.c` file at C.pm:1703.

`emit_struct_ref` / `emit_field_access` (EmitHelpers.pm:2476-2483)
handle the per-node emission of struct accesses.

The schemas live on the EmitHelpers `$_struct_schemas` field; the
target instance is per-class but the schemas are populated *before*
`_generate_c_files` runs. Migration: schema integration is
target-agnostic; no Phase-7-specific work, just preserve the field
+ public setter.

### 5d. compiled_class_metadata + type-aware dispatch

`compiled_class_metadata` is passed as a constructor `:param`
(C.pm:36) for the second build pass (after Phase 3a). The build
script collects `{ slug, readers, methods }` per non-Earley class
and feeds it back into a re-generation of Earley so cross-class
method calls compile to direct C calls instead of `call_method`.

In the build script (build-chalk-so-generated:195-260), the
metadata collection walks the *legacy Constructor-shaped IR*:
`Chalk::Bootstrap::IR::Node::Constructor` with `class() eq
'ClassDecl'` / `'FieldDecl'` / `'MethodDecl'`. This means **the
build script's class-metadata collection assumes a different IR
shape than Target::C's `_generate_c_files` does** — the script
walks Constructor-shape, the target walks ClassInfo-shape.

This is a latent inconsistency in the build script. Flagged in
§10 as an open question; unclear whether the build script's
metadata loop actually runs successfully against current parser
output.

## 6. Method/sub body emission

### 6a. Current shape

`_emit_method($method_decl)` (C.pm:124) is Target::C's analogue of
Target::Perl's `_emit_mop_method`. It:

1. Extracts `name`, `params`, `body` from the input.
   - MethodInfo branch (C.pm:126-135): `name`, `body` direct
     accessors; params synthesized as Constant nodes (synthesis
     bridge — see §2d).
   - Constructor fallback (C.pm:137-140): reads `inputs()->[0..2]`.
     Dead code in production.
2. Handles three special-case "simple" forms early (returns
   directly without going through complex body emission):
   - Single statement that's a Return-of-Interpolate (C.pm:154-155)
     → `_emit_interp_return`.
   - Single statement that's a Return-of-literal-Constant
     (C.pm:156-191) → emit a one-liner C helper that returns the
     literal.
   - Single statement that's an Unwind (die, C.pm:194-218) → emit
     a one-liner C helper that `croak`s.
   - Empty body (C.pm:221-233) → emit a stub.
3. Otherwise calls `_emit_complex_method($name, $params, $body,
   $return_type)` (C.pm:242).

`_emit_complex_method` (C.pm:246) is the full per-body walker:

1. Analyzes body for return tail-expression shape, early-return
   presence (C.pm:249-273).
2. Builds `%declared_vars` from method params, then walks the body
   with `_collect_var_decls` and `_collect_all_var_refs`
   (C.pm:285-286).
3. **Iterates `for my $idx (0 .. $body->@* - 1)` and calls
   `_emit_stmt($body->[$idx], \%declared_vars, $is_last)` per item**
   (C.pm:293-297). This is the body-arrayref iteration that the
   schedule migration replaces.
4. Post-processes the last statement to convert tail expressions
   into `retval = ...` assignments (C.pm:299-325).
5. Wraps the result in a C function template (C.pm:329-372).

`_emit_sub` (C.pm:376) has the same shape — the body-arrayref
iteration is at C.pm:432-436.

### 6b. The body iteration is where the schedule replaces the
arrayref

The 5 `body->@*` iterations in C.pm:89, 97, 293, 432, 1621, 1642,
1776, 2053 are the migration target. Of these:

- C.pm:89, 97 (`_analyze_class`) iterate ClassInfo's body —
  migration target is iterating MOP entity lists (`$cls->fields`,
  `$cls->methods`, `$cls->subs`, `$cls->imports`).
- C.pm:293, 432 (`_emit_complex_method`, `_emit_sub`) iterate
  method/sub body arrayref — migration target is the schedule.
- C.pm:1621, 1642 (`_generate_c_files`) iterate ClassInfo's body
  for SubInfo / MethodInfo emission — migration target is
  `$cls->methods` / `$cls->subs`.
- C.pm:1776 (`_generate_c_files`, init_statics) iterates body for
  class-scope VarDecl init expressions — migration target is
  walking the MOP class's field-default / class-scope-lexical
  representation (currently absent in MOP; see open question §10).
- C.pm:2053 (`generate_xs_wrapper`) iterates body for FieldInfo
  registration — migration target is `$cls->fields`.

### 6c. The schedule-driven equivalent

Target::Perl's `_emit_scheduled_body` (Perl.pm:234) is the
blueprint. The Target::C equivalent would:

1. Take a `Chalk::MOP::Method` (or Sub).
2. Run `Chalk::IR::Scheduler::EagerPinning->new->schedule($method)`
   to obtain a `Chalk::IR::Schedule`.
3. Walk `$schedule->items->@*`, dispatching per `$item->kind`:
   - `'stmt'` → call C-flavored `_emit_stmt` on `$item->node`
     (no cfg_lookup recursion needed; control-flow items appear
     as `block_open`/`block_close` markers).
   - `'block_open' form=>'if'` → emit `if (cond) {` line, indent.
   - `'block_open' form=>'while'|'foreach'|'for'` → emit `while`/
     `for` line via the loop's `schedule_data` (gated check
     against `EagerPinning::Loop`).
   - `'block_open' form=>'try'` → emit `JMPENV_PUSH`/`if (ret == 0)`
     opening from the TryCatch node + `EagerPinning::TryCatch`
     schedule_data.
   - `'block_close'` → emit `}` line, dedent.
   - `'else'`, `'elsif'`, `'catch'` → emit `} else {`,
     `} else if (...)`, `} ... ERRSV-bind` heads.
4. Collect resulting lines into the function body.

The key difference from Target::Perl's path: C codegen needs
*both* indented line tracking (Perl's pattern) *and* the
existing `%declared_vars` + `retval` tail-expression
post-processing logic that wraps the C function template. The
schedule-walker produces the inner body; the existing function-
template wrapping at C.pm:329-372 stays.

### 6d. The Phi side of ScheduleMeta

Per design doc §10, `EagerPinning::Phi` carries `emit_slot` (a
VarDecl reference) or `synthetic_name` (a fallback string).
Target::Perl uses these in `_emit_phi_*` paths I did not fully
trace (the Perl emit code for Phi isn't on the audit's hot
path). Target::C currently handles Phi via
`emit_cfg_phi_if` (EmitHelpers.pm:1160), which materializes the
Phi as a fresh C SV* variable named `_phi_${phi->id}` and assigns
in each branch.

Migration: the schedule path produces a Phi item (per design doc
§ Property: chain coverage), and codegen-for-C reads
`$phi_node->schedule_data` (an `EagerPinning::Phi`) to decide the
emit_slot name. This is more disciplined than the current
`'_phi_' . $phi->id()` naming, which is fine but not gated.

### 6e. Tier A/B/empty-body shortcuts (preserve)

The simple-form shortcuts at C.pm:144-233 are emit shortcuts, not
graph readers. They still apply when the schedule has exactly one
stmt item that's a Return-of-Constant. They can be kept as-is
post-migration with a small refactor: feed the schedule's first
(and only) stmt item's node into the same logic, instead of
reading `$body->[0]`.

Alternatively, the shortcuts can be reframed as a post-schedule
pattern recognizer: "if the schedule is exactly one stmt of shape
Return(Constant), emit the one-liner." This is the cleaner shape
but is incremental polish, not a migration prerequisite.

## 7. Test surface

### 7a. Test files calling `_generate_c_files`

Per `grep -l _generate_c_files t/bootstrap/`:

| File | Pattern |
|---|---|
| `c-target-boolean.t` | parse_file_ir Boolean → `_generate_c_files($ir, $sa, $ctx)`, structural assertions on emitted C, compile + behavioral test |
| `c-data-model-classes.t` | parse_file_ir Symbol/Rule/CoreItemIndex/LR0DFA → `_generate_c_files` (4 separate subtests) |
| `c-direct-cross-class.t` | parse_file_ir Boolean → `_generate_c_files($ir, $sa, $ctx)` with various field_types configurations |
| `c-type-aware-dispatch.t` | parse_file_ir → `_generate_c_files`, baseline vs type-aware |
| `c-xs-wrapper-gen.t` | parse_file_ir Boolean + Precedence → `_generate_c_files` + `generate_xs_wrapper` |
| `c-self-call-optimization.t` | parse_file_ir → `_generate_c_files`, assertions on self-call direct-dispatch |
| `c-target-multi-class.t` | parse_file_ir → multiple `_generate_c_files` calls, cross-class linkage |
| `xs-athx-no-args.t` | **hand-built Program/ClassInfo/MethodInfo IR** → `_generate_c_files($program, undef, undef)` |
| `xs-isa-inheritance.t` | hand-built Program → `_generate_c_files` |
| `xs-int-specialization.t` | hand-built Program → `_generate_c_files` |
| `xs-polymorphic-dispatch.t` | parse_file_ir / hand-built → `_generate_c_files` |
| `c-emit-helpers-inheritance.t` | direct method-existence checks against Target::C |
| (Many Tier A-grammar tests via `build_and_load`) | call through TestXSHelpers wrapper |

### 7b. Hand-built Info-struct tests

Three tests construct `Chalk::IR::Program → ClassInfo → MethodInfo`
trees by hand and feed them to `_generate_c_files($program, undef,
undef)`:

- `t/bootstrap/xs-athx-no-args.t` (lines 14-50)
- `t/bootstrap/xs-isa-inheritance.t` (similar shape)
- `t/bootstrap/xs-int-specialization.t` (similar shape)

The legacy-IR-consumer audit's codegen-test-triage (lines 774-808)
flags all three as REWRITE deferred to Phase 7. They each call
`_generate_c_files($program, undef, undef)` — note `undef` for
`$sa`/`$ctx`, which means **`_build_cfg_lookup` is not called**
(C.pm:1603 guards with `if defined $sa`). These tests do not
exercise the cfg_state path at all; they exercise the Tier A
(simple-body) emission path.

Migration: replace hand-built Program with hand-built `Chalk::MOP`
constructed via `Chalk::MOP::Class->new` + `declare_method` calls.
Hand-construction of a `MOP::Method` requires a graph, which is the
non-trivial part — these tests will need a helper that builds a
minimal graph from a body description, or they rebuild against
schedule fixtures (the pattern in
`t/bootstrap/scheduler/schedule-shape.t`).

### 7c. TestXSHelpers shape

`parse_file_ir` returns `($ir, $sa, $sem_ctx, $cfg_snapshot)` in
list context (TestXSHelpers.pm:85) and `$ir` only in scalar
context.

`build_and_load` (TestXSHelpers.pm:91) takes `($ir, $sa,
$sem_ctx, $module_name, %opts)` and:

1. Calls `$target->_reset_cfg_lookup()` (line 102).
2. Calls `$target->_build_cfg_lookup($sa, $sem_ctx)` (line 103) —
   *without* the `cfg_snapshot` argument despite the snapshot
   being available; that's a parse-time-leak workaround the
   audit flagged previously.
3. Calls `$target->_generate_c_files($ir, $sa, $sem_ctx)` (line
   104).
4. Calls `$target->generate_xs_wrapper(...)` (line 113).
5. Writes `.c`/`.h`/`.xs` to tempdir; compiles `.c`, runs
   xsubpp on `.xs`, links into a per-class `.so`; writes a
   `.pm` stub; `require`s the module.

Phase 7 migration of TestXSHelpers:

- `parse_file_ir` should produce a `Chalk::MOP` (the parse result
  already populates the MOP; lift it out instead of dropping it
  on the floor). The `$sa`/`$sem_ctx`/`$cfg_snapshot` return
  values become irrelevant.
- `build_and_load` calls become `$target->generate($mop)` — but
  that requires `generate($mop)` to actually do the work (it
  currently stubs).
- Or: a new method like `$target->_generate_c_files_from_mop($mop,
  $class)` that mirrors the current `_generate_c_files` signature
  with MOP input.

The triage doc (line 947-958) calls this out: "TestXSHelpers's
`parse_file_ir()` snapshots cfg_state at parse time... Coordinate
with Phase 7 (XS migration) plan — this helper is the entire
surface that connects the XS test set to the legacy parser shape,
and its migration is a prerequisite for the XS test set's
deferred REWRITE."

### 7d. Test counts (rough)

`grep -l _generate_c_files t/bootstrap/*.t` returns 12 files
(including `c-emit-helpers-inheritance.t`'s method-existence
checks). All XS-target behavior tests route through one of these
12 (most via TestXSHelpers). Phase 7's test work is the union of:

- ~3 hand-built-Program tests (`xs-athx-no-args.t` etc.) — REWRITE
  against MOP construction.
- ~6 parse-and-emit tests — MIGRATE: `parse_file_ir` returns MOP
  instead of `($ir, $sa, $ctx)`, target call becomes
  `generate($mop)`.
- 1 emit-helpers-inheritance test — REWRITE: drop the deleted
  method-existence checks (the design doc's Phase 6 Amendment 5
  list deletes the `emit_cfg_*` helpers).

## 8. Constructor fallback investigation

The legacy-IR-consumer audit (lines 313-318) flagged a "dual-path"
pattern at C.pm:1616, 1773, 2032 (and noted similar at
C.pm:126/137-140, C.pm:236/239-241). The form is:

```perl
my $body = $class_decl isa Chalk::IR::ClassInfo
    ? $class_decl->body()
    : $class_decl->inputs()->[2];
```

I.e. "if this is a `ClassInfo`, read `.body`; otherwise it must be
a Constructor with a `class` of `'ClassDecl'`, and the body is at
`inputs()->[2]`."

### 8a. Is the Constructor branch reachable?

To verify, I checked:

1. **Who produces ClassInfo / Constructor-class-ClassDecl IR?**
   `lib/Chalk/Bootstrap/Perl/Actions.pm:747` constructs
   `Chalk::IR::ClassInfo->new(...)` for class declarations. Same
   file:
   - line 821 → `MethodInfo`
   - line 896 → `SubInfo`
   - lines 1733, 2264 → `FieldInfo`
   - line 564 → `UseInfo`
   - line 278 → `Program`
   No `make('Constructor', class => 'ClassDecl', ...)` anywhere
   in `lib/Chalk/Bootstrap/Perl/`. The Actions module is the
   *sole* IR producer for the Perl parser.
2. **Do tests construct Constructor-class-ClassDecl IR?**
   `grep -rn "'ClassDecl'\|'MethodDecl'\|'FieldDecl'"
   lib/ t/bootstrap/` shows only:
   - `t/bootstrap/method-return-type.t` reads `$node->class() eq
     'MethodDecl'` — a stale test that walks for Constructor-shape
     nodes that no longer exist (the test's `is_method_decl` loop
     will find nothing in current parser output; flagged as
     suspect).
   - `script/build-chalk-so-generated:207, 221, 251` reads
     `$_->class() eq 'ClassDecl'` / `'FieldDecl'` / `'MethodDecl'`
     in the type-aware-dispatch metadata collection. This is the
     latent inconsistency I flagged in §5d — the build script
     assumes a different IR shape than `_generate_c_files`. Its
     `class_metadata` map is probably empty in practice, which
     means the type-aware-dispatch second pass doesn't actually
     activate when the build script runs.
3. **Tests that call `_generate_c_files` with hand-built input:**
   All three (`xs-athx-no-args.t`, `xs-isa-inheritance.t`,
   `xs-int-specialization.t`) build `Chalk::IR::ClassInfo->new(...)`
   directly — `grep "Chalk::IR::ClassInfo->new\|Chalk::IR::MethodInfo->new"
   t/bootstrap/*.t` confirms this. They go through the ClassInfo
   branch, never the Constructor branch.

**Conclusion: the Constructor fallback branches at C.pm:1616,
1773, 2032 (the `: $class_decl->inputs()->[2]` else) and at
C.pm:137-140 (`$method_decl->inputs()->[0..3]`) and at C.pm:239
(`$method_decl->inputs()->[3]`) are dead code.** No production
caller and no test caller hits them.

### 8b. Implication for Phase 7

Deleting the Constructor fallback branches is cheap, mechanical,
risk-low cleanup that can land *before* the larger MOP/schedule
migration. It removes the legacy-IR audit's stated "interesting
dual-path" finding and reduces the surface area Phase 7 has to
reason about.

Estimated dead-code removal: ~30 lines across C.pm:137-140,
C.pm:239-241, C.pm:1616-1618, C.pm:1773-1775, C.pm:2030-2039.

It also affects `_emit_method`'s isa-dispatch (C.pm:126, 236)
which becomes unconditional ClassInfo / MethodInfo reads — the
dispatch goes away.

The XS BOOT field-registration FieldInfo `$attr` reads at
C.pm:2068-2076 are also dual-path (`HASH` vs Constructor
`:_Attribute`); same analysis: Actions.pm only produces HASH
attributes (Actions.pm uses `{name => ...}` hashrefs for attrs),
the Constructor `:_Attribute` branch is dead. The "Legacy
Constructor:_Attribute node" comments mark this explicitly.
Similar pattern in EmitHelpers.pm:154-157 and 281-285.

### 8c. Stale test to flag

`t/bootstrap/method-return-type.t` looks for Constructor-class-
MethodDecl nodes via `$node->class() eq 'MethodDecl'` (line 46).
With current parser output, that loop produces zero items — the
`ok(scalar @methods >= 1, ...)` assertion likely fails. The test
file is marked TODO for return-type inference (line 81), so the
failure may be masked, but the test is obsolete in shape. Not a
Phase 7 blocker; flag for the test-triage doc to pick up.

## 9. Migration shape

Recommended Phase 7 implementation plan, from lowest-risk-cheapest
to highest-risk-largest. Sub-phases are independent commits.

### Phase 7a — Constructor-fallback dead-code removal (cleanup prep)

Delete the legacy Constructor-shape fallback branches at C.pm:137-140,
C.pm:239-241, C.pm:1616-1618, C.pm:1773-1775, C.pm:2030-2039, and
the related `:_Attribute` Constructor branches at C.pm:2068-2076 /
EmitHelpers.pm:154-157 / EmitHelpers.pm:281-285.

Replace the dual-path isa-dispatch (e.g. C.pm:126's
`$method_decl isa Chalk::IR::MethodInfo`) with unconditional
ClassInfo / MethodInfo / FieldInfo reads. The isa-check survives
as a guard while these types still exist; it just no longer routes
to an alternate code path.

**Test gate:** existing XS tests pass.

**Risk:** Very low. The branches are dead per §8.

**Effort:** small (~50 lines deleted; ~5 isa-checks simplified).

### Phase 7b — Stub-upgrade preparation: name the MOP entry point

Decide whether the MOP-driven entry is `generate($mop)` (and the
current stub at C.pm:1479 is filled in) or a new method
`_generate_c_files_from_mop($mop, $class)`. The legacy-IR audit
prefers the former: rename `_generate_c_files` to
`_generate_c_files_legacy` (or delete it once tests migrate) and
fill in `generate($mop)` properly.

If the build-script naming bug in §1e is unresolved, also rename
the public entry point consistently.

**Risk:** Low; mechanical.

**Effort:** small (signature plumbing).

### Phase 7c — `_analyze_class` MOP-ification

Migrate `_analyze_class` (C.pm:44), `_find_class_decl`,
`_build_field_index_map`, `_scan_class_methods`, and
`_scan_field_method_calls` to take a `Chalk::MOP::Class` instead
of a `Chalk::IR::ClassInfo`. Walk `$cls->fields`, `$cls->methods`,
`$cls->subs`, `$cls->imports` directly.

`_find_class_decl` (EmitHelpers.pm:119) becomes "given a MOP,
return the (typically one) compilable class" — i.e., it picks the
non-`main` class from `$mop->classes`, since each Target::C
instance is per-class.

Class-scope variable scan (C.pm:60-91) and `use constant` scan
(C.pm:93-120) become walks of the relevant MOP entity lists. The
mis-parented-SubInfo-as-VarDecl-init branch
(EmitHelpers.pm:222-227) needs careful handling: in the MOP model,
those subs may have been correctly parented (Actions.pm's
`MethodDefinition`/`SubroutineDefinition` paths feed the MOP
directly).

The `:reader` attribute scan (EmitHelpers.pm:269-301) becomes a
walk of `$cls->fields` checking `$field->attributes` for `:reader`.

**Test gate:** structural tests on emitted C unchanged.

**Risk:** Medium. The mis-parented-sub branch needs verification
against the MOP shape; the simplest probe is to grep for
"`my %_cache; sub _intern`" patterns in the parsed corpus and
confirm whether the MOP captures the inner sub as a `MOP::Sub` or
as a VarDecl-init.

**Effort:** medium (~200 lines of changes; mostly in EmitHelpers).

### Phase 7d — Schedule-driven body emission

Migrate `_emit_method` (C.pm:124), `_emit_complex_method`
(C.pm:246), `_emit_sub` (C.pm:376) to consume `Chalk::IR::Schedule`
instead of body arrayrefs.

Concrete moves:

1. New helper `_emit_scheduled_c_body($method)` analogous to
   Target::Perl's `_emit_scheduled_body` (Perl.pm:234). Inside:
   ```
   my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
   my $schedule  = $scheduler->schedule($method);
   for my $item ($schedule->items->@*) {
     $self->_emit_c_schedule_item($item, ...);
   }
   ```
2. New helper `_emit_c_schedule_item($item, ...)` that dispatches
   per `$item->kind` ('stmt', 'block_open', 'block_close', 'else',
   'elsif', 'catch'). The 'stmt' case calls the existing
   `_emit_stmt` on `$item->node` (note: `_emit_stmt` still
   contains the cfg_lookup dispatch at EmitHelpers.pm:1411-1453 —
   that path becomes unreachable when control-flow nodes appear
   only inside block_open/block_close pairs, never as 'stmt'
   nodes by themselves; this is the design contract per the
   scheduler).
3. New head emitters: `_emit_c_block_open_head`,
   `_emit_c_if_head`, `_emit_c_while_head`,
   `_emit_c_foreach_head`, `_emit_c_for_head`,
   `_emit_c_catch_head`. These mirror Target::Perl's heads
   (Perl.pm:357-427) but produce C syntax (`if (...) {`,
   `while (...) {`, the foreach `for (_i = 0; ...) {` idiom, the
   JMPENV_PUSH try/catch boilerplate from `emit_cfg_try_catch`).
4. Gate `schedule_data` access through typed isa-checks per
   design doc §10:
   ```
   my $sd = $loop->schedule_data;
   die "..." unless defined $sd
                 && $sd isa Chalk::Scheduler::EagerPinning::Loop;
   ```

The existing `_emit_complex_method` *wrapper* logic (param
collection, `%declared_vars`, retval post-processing, function
template) stays in place — only the body iteration changes.

The tail-expression-to-`retval` heuristics
(`_is_unambiguous_value_expr`, `_is_bare_return_expr`,
`_body_contains_return`, etc., at EmitHelpers.pm:735-779) need to
operate over the schedule instead of the arrayref. The simplest
shape: walk the schedule looking for the last 'stmt' item and run
the heuristics against its node.

The `_has_early_return`, `_body_contains_return`,
`_body_contains_bare_return`, `_collect_var_decls`,
`_collect_all_var_refs` analysis helpers (EmitHelpers.pm:673-893)
all currently recurse into cfg_state's nested `then_stmts` /
`body_stmts` arrays. Migration: walk the method's `Chalk::IR::Graph`
directly for these analyses (the graph iteration gives every node
with no recursion-shape decisions), or walk the schedule's items
flat.

**Test gate:** XS tests pass (including hand-built ones once
they're migrated in 7e).

**Risk:** Medium-to-high. The C codegen has *more* layered emit
helpers than Perl codegen (param handling, scope unwinding,
mortal cleanup, scope guards on each iteration). Each layer needs
to be reviewed for cfg_state-coupled behavior; e.g.
`emit_cfg_loop`'s injection of chart re-read code at
EmitHelpers.pm:1284-1325 is a workaround for a specific filter-gap
artifact that may or may not persist in the schedule path.

**Effort:** large (~500-700 lines of code changes across C.pm and
EmitHelpers).

### Phase 7e — TestXSHelpers + hand-built tests migration

1. `parse_file_ir` returns `($mop, ...)` instead of
   `($ir, $sa, $sem_ctx, $cfg_snapshot)`. cfg_snapshot mechanism
   deleted entirely.
2. `build_and_load` calls `$target->generate($mop)` (the un-stubbed
   entry from 7b) instead of `_generate_c_files($ir, $sa, $sem_ctx)`.
3. `xs-athx-no-args.t`, `xs-isa-inheritance.t`,
   `xs-int-specialization.t` rewrite to construct MOP+graph by
   hand. Helper module `t/bootstrap/lib/TestMOPBuilder.pm` (new)
   provides `mop_with_class($name, methods => [...])` that wraps
   the boilerplate.
4. `c-emit-helpers-inheritance.t` drops the 6 deleted-method
   `can('emit_cfg_*')` checks; keeps the other 24.

**Test gate:** the migrated tests pass; the original XS tests
(behavior + structural) still pass.

**Risk:** Medium. The hand-built-IR tests are the smallest
surface area; the parse-and-emit tests via `parse_file_ir` are
the biggest.

**Effort:** medium (mostly mechanical; some test reshaping).

### Phase 7f — StructPromotion `_analyze_mop` body→graph

Per design doc Amendment 6, StructPromotion's `_analyze_mop` still
reads `$method->body` (StructPromotion.pm:108, 120). Migrate to
graph-walking. This is one of the two readers of `MOP::Method.body`
referenced in Phase 6's "Deferred to Phase 7" list (the other
being Target::C, addressed in 7d above).

**Risk:** Low. StructPromotion's analyze loop already walks
nodes; switching the source from body arrayref to graph iteration
is mechanical.

**Effort:** small.

### Phase 7g — Final transitional-infrastructure deletion

After 7a-7f land and stabilize:

- Delete `_build_cfg_lookup`, `%_cfg_lookup`, `_get_cfg_lookup`,
  `_reset_cfg_lookup`, `_set_sa`, `_set_ctx`, `$_sa`, `$_ctx` on
  EmitHelpers.
- Delete `emit_cfg_if`, `emit_cfg_phi_if`, `emit_cfg_loop`,
  `emit_cfg_try_catch`, `emit_from_cfg_state`, `_emit_loop_jump`
  on EmitHelpers.
- Delete the cfg_state dispatch at EmitHelpers.pm:1411-1453 from
  `_emit_stmt`.
- Delete the cfg_lookup recursion in `_has_early_return`,
  `_body_contains_return`, `_collect_var_decls`,
  `_collect_all_var_refs`.
- Delete `cfg_state` reader on `Chalk::Bootstrap::Context`.
- Delete `_generate_with_cfg` and `_emit_program` / `_emit_*_decl`
  on Target::Perl (the test-side residual from Phase 6).
- Delete `MOP::Method->body`, `MOP::Sub->body`, and the parser-
  side `_finalize_body_graph` body population.
- Delete `Chalk::IR::Program`, `ClassInfo`, `MethodInfo`,
  `SubInfo`, `FieldInfo`, `UseInfo`.
- Delete the Info-struct construction sites in Actions.pm (per
  the legacy-IR audit's ordering recommendation step 4).
- Delete `Graph->schedule` field (per design doc Phase 6
  Amendment 5 deletion list).

**Test gate:** full test suite passes.

**Risk:** Low if 7a-7f were thorough. Misses surface as failing
tests.

**Effort:** small (mechanical deletion).

### Ordering and parallelism

7a is independent and can land immediately. 7b is independent.
7c gates on 7b (the entry-point shape). 7d gates on 7b and 7c
(the body iteration plugs into the entry path). 7e gates on
whichever of 7b/7c/7d defines the new public-facing shape. 7f
is independent (StructPromotion). 7g gates on all of 7a-7f.

7a + 7b + 7f can land in one session. 7c + 7d in one session
(coupled by EmitHelpers field-map/method-scan). 7e in one session
after 7c-7d stabilize. 7g in a follow-up.

## 10. Risks and open questions

### Risks

1. **Schedule walker doesn't replicate all cfg_lookup behavior.**
   `%_cfg_lookup` carries `loop_jump` distinguishing postfix
   `next if X` from a real if-block; carries `then_stmts` /
   `else_stmts` arrays computed by the SemanticAction with
   specific filter-gap repair behavior; carries `iterator` /
   `list` for foreach loops; carries `scope` for variable
   resolution. The schedule path replaces this with
   `EagerPinning::If.is_loop_jump`, `EagerPinning::Loop.iterator`
   / `.list`, etc. (design doc §10). Verify completeness:
   `t/bootstrap/scheduler/schedule-data-*.t` already exercise
   the schedule_data shape; cross-reference these against
   Target::C's current cfg_state reads to ensure no field is
   missing in the new shape.

2. **The `chart re-read` workaround at EmitHelpers.pm:1284-1325.**
   This is a textual patch that detects a specific filter-gap-
   merge artifact in `_emit_method`'s output for Earley's
   while-shift loop and re-injects lost destructuring. If the
   schedule path produces semantically-equivalent IR but
   *different* textual output, this regex-based patch may stop
   matching. Verify whether the underlying filter-gap is still
   present in schedule-walked output; if so, port the patch; if
   not, delete it.

3. **The `_repair_stale_merge` machinery at EmitHelpers.pm:378-423.**
   Same shape: textual patch over emitted C, depends on the legacy
   shape of `_emit_method`'s output. Phase 7d's new emit path may
   need a different repair, or none.

4. **C codegen has its own simple-body shortcuts that bypass body
   iteration entirely.** `_emit_method` at C.pm:144-233 detects
   single-statement bodies and emits one-liner C helpers without
   ever calling `_emit_complex_method`. The schedule path needs
   to identify "schedule with one stmt item" and dispatch through
   the same shortcuts, or refactor the shortcuts to work on
   the schedule directly. Either is fine; the design choice
   should be explicit.

5. **`field_types` and `compiled_class_metadata` constructor
   params.** These are passed at instantiation time
   (C.pm:34-37), used during emission for cross-class direct
   calls. The build script populates them. The MOP-shaped
   equivalent: the MOP could carry the same metadata via a side
   table similar to `$mop->struct_promotion_schemas`. Decide
   whether `field_types` / `compiled_class_metadata` migrate to
   the MOP or stay as constructor params.

### Open questions

1. **Is `script/build-chalk-so-generated` actually broken?** It
   calls `$target->generate_c_files(...)` (no underscore) at
   lines 140 and 289, but no method by that public name exists.
   The `t/bootstrap/mop/codegen-no-backchannel.t` test asserts
   the absence is intentional. Either the script dies on first
   call (and CI doesn't notice) or there's something AUTOLOAD-y
   I missed. **Probe required:** run `./script/build-chalk-so-generated`
   and see what happens. If it dies, this is a pre-existing
   regression that's orthogonal to Phase 7 but should be fixed
   *before* Phase 7 starts (since 7b touches the same name).

2. **Does the build-script class-metadata loop (build-chalk-so-generated:195-260)
   actually produce metadata against current parser output?**
   It walks `$ir->inputs->[0]` looking for `Chalk::Bootstrap::IR::Node::Constructor`
   with `class() eq 'ClassDecl'` etc. Actions.pm produces
   `Chalk::IR::Program` with `classes()` returning a list of
   `Chalk::IR::ClassInfo`, not a Constructor at `inputs[0]`. If
   the metadata loop returns empty, the second-pass type-aware-
   dispatch regeneration is a no-op in practice, and the
   `compiled_class_metadata` field plumbing in Target::C is dead
   in production. **Probe required:** add a `warn` in the metadata
   loop and run the build script. (Flag for the §10.1 same probe
   session.)

3. **`generate($mop)` stub's relationship to test
   `codegen-no-backchannel.t`.** The test at
   `t/bootstrap/mop/codegen-no-backchannel.t:17-18` asserts
   `!Target::C->can('generate_c_files')`. When Phase 7b
   fills in `generate($mop)`, is this test's intent satisfied
   or does it need rewording? The intent was "no
   `generate_c_files` (no underscore) method exists." The
   new `generate($mop)` is a different method name; the test
   still passes by name. But if Phase 7b renames
   `_generate_c_files` → `generate_from_program` or similar,
   the test naming may need adjustment.

4. **Are the cfg_lookup recursions in `_has_early_return` etc.
   actually exercised against any nested control flow in the
   compiled corpus?** The audit didn't trace which
   `_generate_c_files` consumers actually emit code that
   contains nested if-in-loop or try-in-while patterns. If the
   compiled corpus is all flat-control-flow methods, the
   recursive analyzers' cfg_state branches are dead, and the
   migration is simpler. **Probe required:** instrument the
   recursive analyzers with a counter, run the XS test suite,
   see whether the cfg_state-recursive branches fire.

5. **`MOP::Method.graph` completeness for C codegen.** Target::Perl's
   schedule path consumes `$method->graph` indirectly via the
   scheduler. C codegen has more analysis needs (variable
   scoping, retval flow, mortal cleanup, scope unwinding for
   continue/break). Verify that `$method->graph` carries every
   node `_emit_complex_method`'s body iteration currently sees.
   Per memory note `phase_3d_effect_chain.md`, Phase 3d/3e closed
   the bare-side-effect gap that previously left `Call`/`Assign`
   nodes off the control chain. If true, the graph is complete;
   if there are residual gaps for C-specific patterns (e.g. anon
   subs as VarDecl initializers), Phase 7 may surface them.

6. **`_emit_init_expr` for class-scope vars in init_statics.** At
   C.pm:1776-1788, init_statics iterates the *body arrayref* of
   the ClassInfo to find VarDecl items and emit their init
   expressions. The MOP doesn't currently expose class-scope
   lexical declarations directly; they're parsed into ClassInfo
   body but not into MOP::Class as a typed entity. Phase 7 may
   need to expose `$mop_class->class_scope_vars()` (or similar)
   to drive this path post-migration. **Probe required:** check
   whether `Chalk::MOP::Class` has a class-scope-lexical reader
   today.

7. **Multi-class build interaction.** `_polymorphic_dispatch` and
   `_method_dispatch` build cross-class dispatch tables from
   `compiled_class_metadata`. When per-class targets run in
   sequence (the build script's main loop), the metadata is
   accumulated and fed into a second-pass regeneration of
   Earley. The MOP shape may make this cleaner by providing
   metadata directly from `$mop->classes` after first-pass
   compilation. Phase 7's metadata-collection migration is
   coupled with the build-script work (cf. §10.2).

## Acceptance criteria verification

Per the brief's enumerated What-to-find sections:

1. **Target::C entry points** — §1: `generate($mop)` (stub),
   `_generate_c_files`, `generate_xs_wrapper`. **Met.**
2. **Legacy IR shape dependencies in Target::C** — §2: 8 `->body()`
   reads, 1 `->classes()` read, 17 isa-dispatch sites, 6
   Constructor-fallback else-branches all dead. Cited with
   file:line. **Met.**
3. **EmitHelpers usage** — §3: full inherited-method inventory
   grouped by category; cfg_lookup state on EmitHelpers
   enumerated; nothing overridden. **Met.**
4. **cfg_state and `%_cfg_lookup` integration** — §4: 4 Target::C
   touch sites + EmitHelpers consumer map + 4 recursive analyzers
   that walk cfg_state. **Met.**
5. **XS pipeline mechanics** — §5: three-file output, method/sub
   export relationship, struct-promotion integration,
   compiled_class_metadata plumbing (with latent inconsistency
   flagged). **Met.**
6. **Method/sub body emission** — §6: current shape (body
   arrayref iteration), 5 migration target sites, the
   schedule-driven equivalent shape, Phi side, Tier-A/B/empty
   shortcuts. **Met.**
7. **Test surface** — §7: 12 test files identified, 3 hand-built
   tests singled out, TestXSHelpers migration shape.
   **Met (referencing the prior triage doc).**
8. **Constructor fallback investigation** — §8: 6 fallback
   else-branches confirmed dead; cleanup recommended as Phase
   7a (pre-migration prep). **Met.**
9. **Migration shape (Phase 7 plan)** — §9: seven sub-phases
   7a-7g, ordered, with risks and effort estimates. **Met.**
10. **Risks and open questions** — §10: 5 risks + 7 open
    questions, several requiring small probe sessions. **Met.**

## Cross-references

- `docs/plans/2026-05-24-son-scheduler-design.md` — design doc;
  §7 Phase 7 (lines 1125-1169), §10 ScheduleMeta class tree
  (lines 1652-1806), Amendment 6 (lines 1262-1315).
- `docs/plans/2026-05-24-legacy-ir-consumer-audit.md` —
  Target::C section (lines 295-384), EmitHelpers section
  (lines 236-294), dependency-graph and migration-ordering
  sections (lines 482-587).
- `docs/plans/2026-05-24-codegen-test-triage.md` — XS test
  classification (REWRITE entries from line 770 onward,
  TestXSHelpers entry at line 947).
- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` lines 77-326 — Phase
  5b blueprint for `_generate_from_schedule` /
  `_emit_scheduled_body` / `_emit_schedule_item`.
- `lib/Chalk/IR/Scheduler/EagerPinning.pm` — the scheduler.
- `lib/Chalk/Scheduler/EagerPinning/{If,Loop,Phi,TryCatch}.pm` —
  the ScheduleMeta subclasses.

## Out of scope (NOT this audit)

- Running tests or probes (the brief said read-only; §10's
  open questions name probes deferred to Phase 7 prep).
- Re-auditing tests (covered by `2026-05-24-codegen-test-triage.md`).
- The destination scheduler (Phase 8) — design doc names this as
  a separate phase.
- The MOP `body` field's parser-side population — covered by
  the legacy-IR audit.
