# Phase 7c-proper Design — Target::C Consumes MOP::Class

**Date:** 2026-05-25
**Status:** Design v3 (post-review iteration 2; approved with notes).
**Branch:** `fixup-audit-baseline` (will commit on this branch).
**Predecessors:**
- `docs/plans/2026-05-25-phase-7c-proper-handoff.md` — handoff from the
  prior session.
- `docs/plans/2026-05-25-phase-7c-prep-design.md` — what 7c-prep shipped
  (MOP::Class gained `$scope`, `@class_scope_vars`, `@use_constants`,
  `declare_class_scope_var`, `declare_use_constant`).
- Commits `798c955e` (7c-prep MOP API + Actions.pm population) and
  `03318890` (this handoff doc).

## Purpose

Phase 7c-proper migrates Target::C's analyze layer
(`_analyze_class`, `_find_class_decl`, `_build_field_index_map`,
`_scan_class_methods`) from `Chalk::IR::ClassInfo` body-arrayref
iteration to `Chalk::MOP::Class` entity reads.

(`_scan_field_method_calls` was originally listed as a migration site;
investigation showed it has zero production callers and a single
`can('_scan_field_method_calls')` test assertion. It is **dead code**
and is **deleted** in Commit 2 rather than migrated.)

Brainstorming surfaced an unrelated-looking smell that this commit
must fix as precursor work: the parser's `Context.mop` field is
not reliably propagated through `FilterComposite::multiply` and
`add`, so two sites in `Actions.pm` reach around it to a class-global
escape hatch (`Chalk::Bootstrap::Semiring::SemanticAction::current_mop()`).
The same fragility blocks the natural approach for 7c-proper:
`_generate_c_files($ir, $sa, $ctx)` cannot derive a reliable
`$mop` from `$ctx` until propagation is fixed.

A second latent bug surfaces from the same investigation: Actions.pm's
ClassBlock loop populates `$mop_class->class_scope_vars` only from
top-level body items, while the legacy `_analyze_class` (C.pm:65-77)
recursively descends into chained VarDecl initializers (the parser
emits `my $a; my $b;` as one VarDecl with another VarDecl as init).
The MOP path's `class_scope_vars` is currently **lossy** for the
chained-decl case — verified against `lib/Chalk/Bootstrap/Semiring/Boolean.pm`,
which has consecutive `my $ZERO_CTX; my $ONE_CTX;`. This must be fixed
before Commit 2 can rely on `$mop_class->class_scope_vars` as the
source of truth.

This commit cluster fixes the propagation hole, retires the
class-global workaround in Actions.pm, fixes the chained-VarDecl
population, then migrates Target::C and EmitHelpers onto the
now-reliable contract.

## Framing: an architectural debt blocks the natural migration

The intent of commits `ca949854` (`feat(context): add mop field for
compile-time MOP coordination`) and `90448cd8` (`feat(parser): thread
Chalk::MOP through SemanticAction and FilterComposite`) was that
`$ctx->mop()` would be the canonical compile-time MOP access
surface — readable from any semiring or downstream consumer.

The implementation didn't follow through. Two sites in
`FilterComposite.pm` construct fresh result Contexts without
threading `mop`:

- **`_wrap_sa_result`** (FilterComposite.pm:147) — the universal
  multiply wrap path. **Propagates `scope`, `graph`, and `factory`
  correctly today (lines 155-157); only `mop` is missing.** A
  one-field fix.
- **`_pack_survivors`** (FilterComposite.pm:176) and the inline
  packed-Context construction in the add-merge path
  (FilterComposite.pm:475, inside the deterministic-tie-break
  branch) — when add() abstains and packs ambiguous
  alternatives, the packed Context carries `focus`, `children`,
  `is_ambiguous` but **none of `mop` / `scope` / `graph` / `factory`**.
  Four-field fix at each site.

Actions.pm worked around both holes by calling
`Chalk::Bootstrap::Semiring::SemanticAction::current_mop()` directly
at lines 259-261 and 658-660, with the identical comment at each
site: *"current_mop() is used instead of $ctx->mop() because
intermediate multiply contexts do not propagate the mop field."*

That comment documents a real bug, not a design choice. The
class-global `$_mop` is a singleton — it gets reset between parses
and is identical across all in-flight Contexts of the *most recent*
parse only. Spreading this workaround to more consumers (like
Target::C) compounds the rot. Fixing propagation first lets Target::C
consume the MOP through the contract its original architects
intended.

## What ships

This effort lands as **two commits** on `fixup-audit-baseline`:

### Commit 1 — `fix(mop): thread mop through FilterComposite, complete class-scope-var registration, retire current_mop workarounds, MOP-ify test fixtures`

**Changes:**

1. **Propagation fix in FilterComposite.pm.**

   `_wrap_sa_result` (line ~147) gains one field:
   ```perl
   mop => ($is_ctx ? $sa_result->mop() : undef),
   ```
   (Inserted alongside the existing `scope`/`graph`/`factory`
   propagation, same `$is_ctx` guard. **No other field is missing
   here.**)

   `_pack_survivors` (line ~179) gains four fields:
   ```perl
   mop     => ($survivors[0]->mop()),
   scope   => ($survivors[0]->scope()),
   graph   => ($survivors[0]->graph()),
   factory => ($survivors[0]->factory()),
   ```

   The inline packed-Context construction inside `_add_unpacked`
   (FilterComposite.pm:475, inside the deterministic-tie-break
   abstention branch, NOT a separate `_pack_survivors` call) gets
   the same four-field addition, sourced from `$left` (the local
   variable at that call site; semantically equivalent to
   `$survivors[0]` in `_pack_survivors` — first alternative wins):
   ```perl
   mop     => ($left->mop()),
   scope   => ($left->scope()),
   graph   => ($left->graph()),
   factory => ($left->factory()),
   ```

   **Why `$survivors[0]` (and the equivalent `$left`) is correct for
   `mop`/`scope`/`graph`/`factory`:** these four fields encode
   *parse-level* state — the MOP being built, the current lexical
   scope, the per-method graph, the parse factory. They are identical
   across all alternative derivations at the same parse position
   because alternatives differ in *focus* (the IR node they
   produce) and *annotations* (their semiring slot values), not in
   parse-level state. The regression test
   (`t/bootstrap/mop/ctx-mop-propagation.t`) verifies this invariant
   by constructing two genuine survivors with the same MOP+scope+
   graph+factory and asserting the pack carries them through; if
   the assumption ever stops holding (because some future feature
   diverges these fields between alternatives), the test stops
   passing and the design needs an explicit merge rule.

   **Other `Context->new` sites in FilterComposite.pm and
   SemanticAction.pm are audited but not changed.** Specifically:
   - `FilterComposite::zero()` (line 88) — intentionally minimal;
     `mop` on a zero is meaningless, leave alone.
   - `FilterComposite::one()` (line 120) — already correctly
     propagates `mop` from SA's one (line 126). The `$_one_cache`
     (line 25) is invalidated by `reset_cache()` (line 82), which
     `TestXSHelpers::parse_file_ir` calls (TestXSHelpers.pm:59)
     before every parse. SA's `_one_singleton` is similarly
     invalidated by `set_mop()` (SemanticAction.pm:218). The
     `one()` cache cannot carry a stale MOP across parses.
   - The transient `$ti_ctx_wrapper` (line 268) — single-use TI
     bridge consumed inline, not a propagation chain. Leave alone.
   - `SemanticAction` Context->new sites (lines 84, 144, 307, 337,
     358, 379, 400, 467) — all already propagate `mop` (some read
     `$_mop` directly via the class-global, some read
     `$result_ctx->mop()`). No change.

2. **Fix Actions.pm ClassBlock to descend into chained VarDecl
   initializers when populating `class_scope_vars`.**

   Today (Actions.pm:746-747) only top-level body items get
   registered:
   ```perl
   } elsif ($item isa Chalk::IR::Node::VarDecl) {
       $mop_class->declare_class_scope_var($item);
   }
   ```

   `my $a; my $b;` at class scope parses as one VarDecl whose `init`
   is another VarDecl — the inner VarDecl never reaches the body
   iteration, so it never gets registered on the MOP. C.pm:65-77
   handled this in legacy code with a recursive `$register_class_var`
   coderef. The MOP path needs the same recursion:

   ```perl
   } elsif ($item isa Chalk::IR::Node::VarDecl) {
       # Descend into chained VarDecl inits: `my $a; my $b;` parses as
       # one VarDecl whose init is another VarDecl. Each link of the
       # chain must be registered.
       my $current = $item;
       while (defined $current && $current isa Chalk::IR::Node::VarDecl) {
           my $next_init = $current->init();
           $mop_class->declare_class_scope_var($current);
           last unless defined $next_init && $next_init isa Chalk::IR::Node::VarDecl;
           $current = $next_init;
       }
   }
   ```

   **Concrete validation:** `lib/Chalk/Bootstrap/Semiring/Boolean.pm`
   has `my $ZERO_CTX; my $ONE_CTX;` at class scope. The integration
   test in `t/bootstrap/mop/parse-integration.t` (per 7c-prep's
   plan) parses `Semiring::Structural.pm`, which has only one
   class-scope `my $ZERO`. Add an assertion: parse `Semiring::Boolean.pm`
   and assert `class_scope_vars` contains both `$ZERO_CTX` and
   `$ONE_CTX`. Today this fails — the fix in this commit makes it
   pass.

   **Order note:** the legacy `_analyze_class` (C.pm:65-77) uses a
   recursive coderef that descends *before* registering, producing
   inner-first order (`[$ONE_CTX, $ZERO_CTX]` for the Boolean.pm
   case where `$ZERO_CTX` is the outer VarDecl whose init is the
   `$ONE_CTX` VarDecl). The proposed while-loop registers
   outer-first (`[$ZERO_CTX, $ONE_CTX]`). This order reversal is
   intentional and safe: chained class-scope `my` declarations are
   mutually independent by language semantics — no VarDecl in the
   chain can refer to another VarDecl from the same chain as its
   initializer (the parser doesn't produce that shape; bare `my $x;`
   has no init referencing the chain). Commit 2's
   `_analyze_class` consumes `class_scope_vars` to emit static C
   variables whose order does not affect correctness (each static
   is initialized independently in init_statics, and any references
   between them resolve at runtime via the same static names).

   **Regression test stance:** the new integration assertion checks
   that both `$ZERO_CTX` and `$ONE_CTX` are present in
   `class_scope_vars` (as a set), not that they appear in any
   specific order. This deliberately decouples the test from the
   inner-first-vs-outer-first choice so a future refactor can
   change registration order without spurious test churn.

3. **Retire `current_mop()` workarounds in Actions.pm.**

   At lines 259-261 and 658-660, replace:
   ```perl
   # current_mop() is used instead of $ctx->mop() because intermediate
   # multiply contexts do not propagate the mop field.
   my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
   ```
   with:
   ```perl
   my $mop = $ctx->mop;
   ```

   Delete the workaround comments. The new code reads from the
   contract that propagation now honors.

   `SemanticAction::current_mop()` itself stays — `set_mop()` still
   exists for TestPipeline to install the per-parse MOP into the
   `_one_ctx` singleton, and `current_mop()` is the symmetric reader.
   Internal-to-semiring usage is fine (`_one_ctx` at line 89 and
   `_mul_ctx` at line 149 both read `$_mop` directly — they're inside
   the semiring that owns the field). The only thing being retired
   is *external* consumers reaching past `$ctx->mop()`.

4. **Add `MOP::Field` helper methods.**

   Two booleans expressing the attribute checks every consumer
   repeats:

   ```perl
   # In lib/Chalk/MOP/Field.pm:
   method has_attribute($name) {
       return scalar grep { $_ eq ":$name" } $attributes->@*;
   }
   method is_param()    { return $self->has_attribute('param') }
   method has_reader()  { return $self->has_attribute('reader') }
   ```

   The naming follows the colon-prefixed convention `attributes`
   already uses (Target::Perl writes `:$a` at Perl.pm:185). These
   helpers exist to make the Commit 2 migration sites read like
   prose. Three new methods total; small surface increase that
   removes repetition in the migration sites and centralizes one
   class of attribute-shape bug (consumer mis-matching attribute
   shape was the audit's worry; the helpers make the matching
   provably correct).

5. **Rewrite four named hand-built-IR test fixtures to MOP-driven
   construction.**

   The handoff doc identifies four canary tests that pass `undef`
   for `$ctx` and hand-build `Chalk::IR::ClassInfo`:

   - `t/bootstrap/xs-isa-inheritance.t`
   - `t/bootstrap/xs-polymorphic-dispatch.t`
   - `t/bootstrap/xs-int-specialization.t`
   - `t/bootstrap/xs-athx-no-args.t`

   These tests were written before MOP existed (test fixtures
   pre-date commits `ca949854` and `90448cd8` from April 2026).
   Today they construct legacy ClassInfo IR that runs through a
   code path real parses no longer use. After Commit 2 removes the
   legacy `_find_class_decl` body iteration, those tests will
   exercise dead code paths — they must be migrated.

   **Migration pattern** (per-test, see notes below for the
   per-test specifics):

   ```perl
   # Each migrated test:
   # 1. Construct a Chalk::MOP.
   # 2. Call $mop->declare_class($CLASS_NAME, parent_name => $PARENT_OR_UNDEF).
   # 3. For every method the test asserts about, call
   #    $mop_class->declare_method($name, params => [...], body => [...]).
   # 4. For every sub, call declare_sub. For every field, declare_field
   #    (with the same args Actions.pm would produce).
   # 5. Construct $ctx = Chalk::Bootstrap::Context->new(focus => undef, mop => $mop).
   # 6. Build $program from ClassInfo as before — ClassInfo stays alive
   #    until 7g and Target::C still reads it for method/sub *body*
   #    iteration (7d's job). The MOP carries class-shape; ClassInfo
   #    carries body items.
   # 7. Call $target->_generate_c_files($program, undef, $ctx).
   ```

   **Per-test specifics:**

   - **`xs-isa-inheritance.t`** — `module_name => 'Test::ISA::Child'`,
     class `'Test::ISA::Child'` with `parent_name => 'Test::ISA::Parent'`,
     one method `greet`. Migration: register class as
     `'Test::ISA::Child'` (matches `module_name`); MOP class
     lookup via `$mop->for_class('Test::ISA::Child')` succeeds.
     Declare the `greet` method on the MOP class so Commit 2's
     `for my $method ($mop_class->methods)` loop emits it.

   - **`xs-polymorphic-dispatch.t`** — `module_name =>
     'Test::Dispatch::Host'`, class `'Test::Dispatch::Host'` with
     a stub method. Same pattern as above. The
     `compiled_class_metadata` argument is passed to the Target::C
     constructor and is independent of the MOP for the *host*
     class — it describes external classes the host knows about.
     No MOP changes needed for the metadata classes themselves
     (they are stubs whose data lives in the metadata hashref).

   - **`xs-int-specialization.t`** — `module_name => 'Test::IntSpec'`,
     class `'Test::IntSpec'` with method `add_one`. Standard
     pattern.

   - **`xs-athx-no-args.t`** — **Module-name/class-name mismatch
     is intentional.** `module_name => 'Some::Module::TestBaz'`,
     class `'Foo::Bar::Baz'`. The test exists *to verify* that
     when class slug ('baz' from `Foo::Bar::Baz`) differs from
     module slug ('testbaz' from `Some::Module::TestBaz`), the C
     function uses the **class** slug — i.e., `baz_init_statics`,
     not `testbaz_init_statics`. The MOP must register the class
     under its real name (`Foo::Bar::Baz`), and the Commit 2
     lookup helper must pick the class **without using
     `module_name`** (see Commit 2 item 2 for the corrected lookup
     contract).

   Tests that already pass `$ctx` (`c-data-model-classes.t`,
   `c-self-call-optimization.t`, `c-target-multi-class.t`,
   `c-target-boolean.t`, `c-direct-cross-class.t`,
   `c-type-aware-dispatch.t`, `c-xs-wrapper-gen.t`) **are not
   touched by Commit 1**. They already obtain a real
   parser-built Context, so after the propagation fix their
   `$ctx->mop()` will be populated automatically. If any of them
   fails after Commit 1, that's evidence the propagation fix
   missed a site; fix forward, don't work around.

6. **Regression tests for the propagation fix and the chained-decl
   fix.**

   Three test files:

   - **`t/bootstrap/mop/ctx-mop-propagation.t`** (new) — structural
     unit tests covering the three changed `Context->new` sites.
     Tests dispatch through the public `multiply` and `add`
     methods (not private `_wrap_sa_result` / `_pack_survivors`)
     to avoid coupling to internal site names:
     - Construct two FilterComposite Contexts via `_one_ctx`-like
       seeding with a MOP attached; call `$composite->multiply($l, $r)`;
       assert result carries the MOP. (Hits `_wrap_sa_result`.)
     - Construct two genuinely-different Contexts that force add()
       to pack; assert packed result carries MOP+scope+graph+factory.
       (Hits `_pack_survivors`.)
     - Construct alternatives that force the deterministic-tie-break
       branch in `_add_unpacked` and assert the same. (Hits the
       inline `Context->new` at line 475.)
     Estimated 5-7 tests. End-to-end-flavor structural tests, not
     private-method-touching unit tests.

   - **Extension to `t/bootstrap/mop/parse-threading.t`** — adds
     one end-to-end assertion. Parse a minimal synthetic 2-class
     source (e.g., `class A { method f { 1 } } class B { method g { 2 } }`)
     through TestPipeline. Assert `refaddr($parse_root_ctx->mop) ==
     refaddr($installed_mop)`. This documents the contract
     ("`$ctx->mop()` is the MOP after a parse") without coupling
     to any specific internal site.

   - **Extension to `t/bootstrap/mop/parse-integration.t`** — adds
     one assertion for the chained-decl fix. Parse
     `lib/Chalk/Bootstrap/Semiring/Boolean.pm`; assert
     `$mop->for_class('Chalk::Bootstrap::Semiring::Boolean')
     ->class_scope_vars` contains entries for both `$ZERO_CTX` and
     `$ONE_CTX`.

**Why fold all six into one commit instead of decomposing further:**

The audit smell, the propagation fix, the chained-decl fix, the
workaround retirement, the MOP::Field helpers, the test fixture
migration, and the regression coverage are tightly coupled.
Splitting them invites intermediate states where:

- The propagation fix is in but the workarounds in Actions.pm still
  exist (dead code).
- The workarounds are removed but propagation isn't fixed (Actions.pm
  crashes).
- Class-scope-vars population is fixed but no consumer reads from it
  (dead correctness).
- Test fixtures are migrated but Commit 2 hasn't landed yet (test
  fixtures call MOP setup whose data isn't yet consumed).

The size of the diff is moderate: propagation fix ~12 lines across
one file, chained-decl fix ~8 lines in Actions.pm, workaround
retirement ~6 lines in Actions.pm, MOP::Field helpers ~8 lines, four
test files get rewritten fixture-construction blocks (~30 lines each).
The cumulative scope is one cohesive change: "make `$ctx->mop()` and
`$mop_class->class_scope_vars` the reliable sources of truth for
compile-time class data."

### Commit 2 — `feat(target-c): Phase 7c-proper — analyze layer reads MOP::Class`

The actual migration. With Commit 1 landed, `_generate_c_files`
can derive the MOP from `$ctx->mop`.

**Changes:**

1. **`_generate_c_files($ir, $sa, $ctx)` signature stays.** Inside,
   at the top:
   ```perl
   my $mop = $ctx->mop
       // die "_generate_c_files requires \$ctx->mop() to be set; "
            . "construct \$ctx with mop => \$mop or use TestPipeline";
   my $mop_class = $self->_find_mop_class($mop)
       // die "MOP has no non-main class entry";
   ```
   No legacy fallback. If MOP isn't there, the test/caller is wrong;
   die loudly.

2. **`_find_mop_class($mop)` in EmitHelpers** — picks the non-main
   class from `$mop->classes`. Mirrors the legacy `_find_class_decl`
   contract: each Target::C instance compiles one class at a time,
   `main` is the import-bucket, the remaining (typically one) class
   is the one being compiled.

   ```perl
   method _find_mop_class($mop) {
       for my $cls ($mop->classes) {
           return $cls if $cls->name ne 'main';
       }
       return undef;
   }
   ```

   **Why not `$mop->for_class($self->module_name)`:** the
   `xs-athx-no-args.t` test shows `module_name` and class name
   can legitimately differ — that's a feature, not a bug. Looking
   up by `module_name` would break that test. The legacy contract
   ("find the one non-main class") is the right contract to
   preserve.

   The `_find_class_decl` method in EmitHelpers (line 119) is
   replaced by `_find_mop_class`. The old name is deleted; one
   `can('_find_class_decl')` reference in
   `t/bootstrap/c-emit-helpers-inheritance.t` (line ~46) needs
   updating to assert `can('_find_mop_class')` instead.

3. **`_analyze_class` migrates from `$ir` to `$mop_class` parameter.**

   ```perl
   method _analyze_class($mop_class) {
       my $class_name = $mop_class->name;
       $self->_set_current_slug($self->_class_slug($class_name));
       $self->_set_field_map($self->_build_field_index_map($mop_class));
       $self->_set_class_methods($self->_scan_class_methods($mop_class));

       $self->_reset_class_scope_vars();
       for my $vardecl ($mop_class->class_scope_vars) {
           my $raw_var = $vardecl->name()->value();
           my $sigil = substr($raw_var, 0, 1);
           my $var = $raw_var =~ s/^[\$\@\%]//r;
           my $init = $vardecl->init();
           # Skip if init is a SubInfo or VarDecl (handled elsewhere);
           # skip if var is a field.
           next if defined $init && $init isa Chalk::IR::SubInfo;
           next if defined $init && $init isa Chalk::IR::Node::VarDecl;
           next if defined $self->_get_field_map()
                && exists $self->_get_field_map()->{$var};
           $self->_set_class_scope_var($var, {
               sigil       => $sigil,
               init        => $init,
               static_name => "_csv_" . $self->_get_current_slug() . "_${var}",
           });
       }

       $self->_reset_use_constants();
       for my $uc ($mop_class->use_constants) {
           my $vv = $uc->{value};
           my $vv_value = ($vv isa Chalk::IR::Node::Constant) ? $vv->value() : undef;
           next unless defined $vv_value && $vv_value =~ /^-?[0-9]+$/;
           $self->_set_use_constant($uc->{name}, $vv_value);
       }
       return;
   }
   ```

   The recursion-into-VarDecl-init logic from C.pm:74-77 is
   **gone** — that case is now handled at population time by the
   Commit 1 fix in Actions.pm. `_analyze_class` simply iterates
   the (now complete) `class_scope_vars` list.

   Call site in `_generate_c_files` (C.pm:1594):
   ```perl
   $self->_analyze_class($mop_class);
   ```

4. **`_build_field_index_map($mop_class)`** iterates
   `$mop_class->fields`. Reads `$field->name` (sigil-prefixed),
   `$field->sigil`, `$field->is_param` (the new helper). The
   `%params` hashref population becomes `$_param_fields = {
   map { my $n = $_->name =~ s/^[\$\@\%]//r; $_->is_param ? ($n => 1) : () } $mop_class->fields }`.

5. **`_scan_class_methods($mop_class)`** iterates
   `$mop_class->methods`, `$mop_class->subs`, and uses
   `$field->has_reader` to scan for `:reader` attributes.

   The mis-parented-SubInfo-as-VarDecl-init branch at
   EmitHelpers.pm:215-221 is probed (`grep "my %_cache; sub " lib/`),
   and **deleted if no production class shows the pattern**. Per
   7c-prep's Risk #1 framing, Actions.pm routes
   SubroutineDefinition through `declare_sub` regardless, so the
   workaround should be dead in the MOP path. If any production
   class shows the pattern, keep the fallback with a TODO and a
   tracking issue.

6. **`_scan_field_method_calls`** is **deleted**. Investigation
   found zero production callers and a single `can(...)` test
   assertion in `c-emit-helpers-inheritance.t:46`. The method
   itself reads `$class_decl->inputs()->[2]` — a Constructor IR
   shape that `ClassInfo` doesn't even have — confirming it's
   stale code. Remove both the method and its `can` assertion.

7. **`_generate_c_files` body-iteration loop** (C.pm:1602-1650)
   migrates from `for my $item ($class_decl->body->@*)` to two
   clean loops:

   ```perl
   # Subs first (static helpers).
   for my $sub ($mop_class->subs) {
       my $sname = $sub->name;
       my $sparams = $sub->params;
       my $sbody = $sub->body;   # 7d-transitional read
       my $result;
       try {
           $result = $self->_emit_sub($sname, $sparams, $sbody);
       } catch ($e) { }
       # ... unchanged: push helper lines, mark compiled, etc. ...
   }

   # Methods.
   for my $method ($mop_class->methods) {
       my $result;
       try {
           $result = $self->_emit_method($method);
       } catch ($e) {
           push @_skipped_methods, $method->name;
           next;
       }
       # ... unchanged ...
   }
   ```

   **`_emit_method` accepts a `MOP::Method` instead of a
   `MethodInfo` after this change.** The accessor surface is
   compatible:
   - `MOP::Method->name` — returns the method name (string). Matches
     `MethodInfo->name`. ✓
   - `MOP::Method->params` — returns the params arrayref. Matches
     `MethodInfo->params` (Actions.pm:700 populates MOP::Method's
     `params` field from `$item->params()`, the same MethodInfo
     accessor; same arrayref shape). ✓
   - `MOP::Method->body` — returns the body arrayref. Matches
     `MethodInfo->body` (same source: Actions.pm:702
     `body => $item->body()`). 7d-transitional. ✓
   - `MOP::Method->return_type` — returns the type or undef.
     Matches `MethodInfo->return_type`. ✓
   - `MOP::Method->graph` — exists but unused by `_emit_method`
     today. 7d-relevant.

   No adapter needed; the `_emit_method($mop_method)` call works
   because both objects answer the same four messages with the
   same shapes. The internals of `_emit_method` (which read
   `->name`, `->body`, `->params`, `->return_type`) are unchanged.

8. **init_statics emission** (C.pm:1757-1770) migrates from body
   iteration to `for my $vardecl ($mop_class->class_scope_vars)`.
   The inner logic (skip if var not in `_class_scope_vars` hash,
   emit init expression) is unchanged.

9. **XS BOOT field iteration** (C.pm:2026-2062) migrates from body
   iteration to `for my $field ($mop_class->fields)`. Reads
   `$field->name`, `$field->attributes` (the colon-stringified
   list), `$field->default_value`. The attribute-application loop
   (lines 2043-2052) maps each `:reader`-style attribute directly
   — no hashref unwrapping needed.

10. **`compiled_class_metadata` Phase 3b loop in
    `script/build-chalk-so-generated` (lines 200-260)** migrates
    from Constructor IR walking to MOP-driven walking. The loop is
    already known-broken (the metadata map is empty in practice
    per the audit's Phase 7b findings) so the fix has no
    behavioral regression risk. New shape:
    ```perl
    my $mop_class = $parsed_info->{ctx}->mop->for_class($cn);
    next unless defined $mop_class;
    my %readers;
    my $field_idx = 0;
    for my $field ($mop_class->fields) {
        if ($field->has_reader) {
            my $fname = $field->name =~ s/^[\$\@\%]//r;
            $readers{$fname} = $field_idx;
        }
        $field_idx++;
    }
    my %methods = map { $_->name => 1 } $mop_class->methods;
    # ... rest unchanged ...
    ```

    **Justification for in-scope:** the build script's Phase 3b
    loop walks ClassInfo body-shape data (FieldDecl/MethodDecl
    Constructor IR nodes) that Actions.pm doesn't currently
    produce. It's a stale reader of a stale source — exactly the
    kind of plan-vs-code drift CLAUDE.md flags as the #1 failure
    mode. Migrating it in the same commit as Target::C's analyze
    layer means production codegen (the build script) and test
    codegen (the test fixtures via TestPipeline) consume the MOP
    consistently. Splitting it to a separate commit risks the
    build script staying on Constructor IR forever, hiding behind
    "the metadata map is empty in practice so it doesn't matter."

**Sites the handoff doc explicitly excludes (stay until 7d):**

- C.pm:126 `my $body = $method_decl->body()` in `_emit_method` —
  method body read for code emission, 7d.
- C.pm:1610 `my $sbody = $item->body()` inside SubInfo iteration —
  sub body read, 7d. (After this commit it's `$sub->body` where
  `$sub` is a `MOP::Sub`, but same transitional shape.)

These stay as transitional reads on `MOP::Method.body` /
`MOP::Sub.body` until 7d migrates emission to schedule-driven.

**Why a single commit covers both C.pm and EmitHelpers:**

The 9 sites (was 10; `_scan_field_method_calls` is now a deletion,
not a migration) are coupled — `_analyze_class` (C.pm) calls
`_build_field_index_map` and `_scan_class_methods` (EmitHelpers);
`_generate_c_files` calls `_find_mop_class` (EmitHelpers) and
`_analyze_class`. A split commit (C.pm only / EmitHelpers only)
would force an intermediate state with mixed-API signatures
(ClassInfo on one side of the call, MOP::Class on the other).
Single commit avoids that.

## Risks

### Commit 1 risks

1. **Propagation fix surfaces latent bugs in other consumers.** If
   some semiring or downstream consumer was silently coping with
   `$ctx->mop()` returning undef, the fix may cause them to start
   running code that's broken in subtle ways. **Mitigation:** the
   regression suite (`bnf-target-c.t`, `c-emit-helpers-inheritance.t`,
   `mop/*.t`, plus the `c-*.t` tests that pass `$ctx`) is the
   canary. Run before/after the fix and triage any delta.

2. **The `$survivors[0]` choice could be wrong if survivors carry
   different `mop`/`scope`/`graph`/`factory` values.** They
   shouldn't — these fields encode parse-level state that's
   identical across alternative derivations — but the assumption
   is structural. **Mitigation:** the regression test explicitly
   constructs two survivors with the same MOP/scope/graph/factory
   and asserts the pack carries them through. If a future feature
   diverges these fields between alternatives, the test fails
   visibly and the design needs an explicit merge rule.

3. **The chained-decl fix in Actions.pm could double-register a
   VarDecl if both the outer item AND the inner init reach the
   ClassBlock loop.** They shouldn't — the parser packs them, the
   inner one is reachable only via init descent. **Mitigation:**
   the new integration test on `Boolean.pm` asserts both
   `$ZERO_CTX` and `$ONE_CTX` are registered. If the fix
   double-registers, the list has more entries than expected and
   the test catches it.

4. **Tests that previously passed via stale `current_mop()` state
   may now fail.** If a test runs after a parse that left a
   different MOP in the class-global, and the test's `$ctx->mop()`
   is undef (which it would be in a hand-built Context that didn't
   set `mop`), the test that previously got the stale MOP via
   `current_mop()` will now see `$ctx->mop()` return undef. This
   is the **intended** behavior: tests should not depend on
   class-global cross-test state. Any test that fails this way is
   a test that was wrong; fix the test fixture. **Mitigation:** if
   this surfaces, the fix is mechanical (add a MOP setup to the
   test fixture, per the four canary tests' pattern).

5. **MOP::Field helper naming collisions.** Unlikely; the names
   `is_param`, `has_reader`, `has_attribute` are specific enough.

### Commit 2 risks

1. **Mis-parented-SubInfo branch deletion may regress.** If the
   `my %_cache; sub _intern` parse ambiguity *still* mis-parents
   in the MOP-routing path (unlikely per 7c-prep's claim, but
   unverified), deleting the EmitHelpers fallback at line 215-221
   loses sub registrations. **Mitigation:** probe before deleting
   (`grep -rn "my %_cache; sub " lib/`); if any production class
   shows the pattern, keep the fallback with a TODO and a separate
   ticket.

2. **Phase 3b loop rewrite in `build-chalk-so-generated` is
   build-script-only and not exercised by the test suite.** A
   regression here only surfaces when someone runs
   `script/build-chalk-so-generated` (i.e., the actual `chalk.so`
   build). **Mitigation:** run the build script after Commit 2
   lands; it's documented in CLAUDE.md as the validation gate for
   the C target. **Pre-implementation check:** confirm the
   `parsed_info->{ctx}` shape carries a MOP via `$ctx->mop` — it
   should after Commit 1, but verify before relying on it.

3. **`_find_mop_class` returns the wrong class for files with
   multiple non-main classes.** Currently rare (the corpus has
   one class per file), but not impossible. The legacy
   `_find_class_decl` had the same limitation (it returns the
   first ClassInfo, full stop). **Mitigation:** keep the same
   "first non-main class wins" semantics; if a multi-class file
   ever appears, both the legacy code and the new code break the
   same way — a separate fix.

4. **`_emit_method` previously received a `MethodInfo`; now
   receives a `MOP::Method`.** Accessor compatibility verified
   above. The risk is that some downstream call inside
   `_emit_method` reads an accessor that exists on MethodInfo but
   not MOP::Method. **Mitigation:** the verified-compatible
   accessors are `name`, `params`, `body`, `return_type`. Run
   `bnf-target-c.t` after the swap; any accessor mismatch surfaces
   as `Can't locate object method` and is mechanical to fix.

5. **Deleting `_scan_field_method_calls` plus its `can` assertion
   may surface other callers not found by `grep`.** Unlikely
   given Perl's static method dispatch, but worth double-checking
   with `ag '_scan_field_method_calls' /home/perigrin/dev/chalk/`
   before the delete commit.

### Inter-commit sequencing risk

**Between Commit 1 landing and Commit 2 landing, any test that
still passes `$ctx = undef` to `_generate_c_files` would have
worked through legacy ClassInfo fallback before Commit 1 and
would still work through legacy ClassInfo fallback after Commit 1
(Commit 1 does NOT add the `$ctx->mop // die` guard — that's
Commit 2). The four canary tests get their fixtures rewritten in
Commit 1 to pass a real `$ctx` with `mop` set, so they don't
exercise the undef path. After Commit 2 lands, any remaining call
site that passes `$ctx = undef` will hit the clean `die` message.

The intermediate state (Commit 1 landed, Commit 2 not yet) is
safe: nothing crashes, propagation works, the legacy reader path
is still alive. The two commits don't have to land in the same
session — Commit 1 can sit on the branch while Commit 2 is
prepared.**

## Out of scope (explicitly)

- **`_emit_method` / `_emit_complex_method` / `_emit_sub` body
  iteration** — Phase 7d (schedule-driven body emission).
- **Deletion of `MOP::Method.body`, `MOP::Sub.body`,
  `Chalk::IR::Program`, `ClassInfo`, `MethodInfo`, `SubInfo`,
  `FieldInfo`, `UseInfo`** — Phase 7g.
- **Modification of `Target::Perl`** — already consumes MOP via
  `_generate_from_schedule`.
- **Wiring method-scope-inherits-class-scope** — per 7c-prep
  design, this is a separate decision with its own tests and
  risks.
- **Tests that already pass `$ctx`** — they get the propagation
  fix automatically; not rewritten in Commit 1.
- **Coverage audit of whether any of the four rewritten test
  fixtures are fully redundant with parser-driven tests** —
  separate cleanup; not in this scope.
- **Internal `SemanticAction::current_mop()` consumers** —
  `_one_ctx` and `_mul_ctx` read `$_mop` directly; that's an
  intra-semiring concern, not the external-consumer pattern this
  commit retires.

## Test gates

Before Commit 1:
- Capture baseline counts: `mop/codegen-byte-compat.t` 19/19,
  `mop/class-scope-vars.t`, `mop/use-constants.t`,
  `mop/parse-integration.t` all pass, `c-emit-helpers-inheritance.t`
  54/54, `bnf-target-c.t` 178/178.
- Document any pre-existing failures from
  `docs/plans/2026-05-24-phase-7-baseline.md` for regression
  delta.

After Commit 1:
- All gates above pass.
- New: `t/bootstrap/mop/ctx-mop-propagation.t` passes (5-7 tests).
- New: extension to `t/bootstrap/mop/parse-threading.t` passes
  (1 added test).
- New: extension to `t/bootstrap/mop/parse-integration.t` passes
  (1 added test for chained-decl on Boolean.pm).
- Four rewritten test fixtures pass: `xs-isa-inheritance.t`,
  `xs-polymorphic-dispatch.t`, `xs-int-specialization.t`,
  `xs-athx-no-args.t`.

After Commit 2:
- All gates above stay green.
- `mop/codegen-byte-compat.t` stays at 19/19 (no Target::Perl
  changes; golden should not regenerate).
- `c-emit-helpers-inheritance.t` passes (count -1 due to
  `_scan_field_method_calls` can-assertion removal: 53/53).
- `bnf-target-c.t` 178/178 unchanged.
- `script/build-chalk-so-generated` runs successfully and
  produces a working `chalk.so` (build-script Phase 3b fix
  verification).

## Acceptance

This design is approved when:

1. **Propagation contract is documented as the canonical
   mechanism.** `$ctx->mop()` is the reader;
   `SemanticAction::set_mop()` is the parse-time writer;
   `current_mop()` is for *internal* semiring use (e.g.,
   `_one_ctx`, `_mul_ctx`), not external consumers.
2. **Commit 1 covers six fold-ins** (propagation fix,
   chained-decl fix, workaround retirement, MOP::Field helpers,
   test fixture rewrites, regression coverage) with regression
   coverage from structural, end-to-end, and integration tests.
3. **Commit 2 migrates all 9 sites enumerated in the Commit 2
   change list** (`_analyze_class`, `_find_mop_class`,
   `_build_field_index_map`, `_scan_class_methods`, body
   iteration loop, init_statics walk, XS BOOT field walk,
   `_scan_field_method_calls` deletion, build-script Phase 3b
   loop) with no legacy ClassInfo fallback in the analyze layer.
4. **The `_emit_method` and `_emit_sub` body reads** at
   C.pm:126 and (post-migration) the `$mop_class->subs` loop
   stay alive (7d's scope).
5. **Out-of-scope items match the handoff doc's hard
   constraints.**

User approval gate at brainstorming time (2026-05-25).
Implementation plan to follow via the `writing-plans` skill.

## Changelog from v2 (post-review iteration 2)

Addresses two important issues and two questions from the second
project-plan-reviewer dispatch:

- **Important A (sequencing).** Added explicit "Inter-commit
  sequencing risk" subsection under Commit 2 risks documenting
  that the intermediate state between Commit 1 and Commit 2 is
  safe (no `die` guard lands until Commit 2; legacy fallback is
  still alive during the gap).
- **Important B (order reversal).** Added "Order note" to the
  chained-decl fix in Commit 1 item 2, explicitly acknowledging
  that the while-loop registers outer-first while legacy
  recursion registered inner-first, and explaining why the order
  reversal is safe for chained class-scope VarDecls (they are
  mutually independent by language semantics; static init order
  in the generated C does not depend on the list order). The
  regression test now asserts set-presence, not specific order.
- **Question 1 (`_one_cache` lifecycle).** Added a note to the
  audit of `FilterComposite::one()` confirming the cache is
  invalidated by `reset_cache()` before every parse, so no stale
  MOP can leak across parses.
- **Question 2 (`_pack_survivors` vs inline site variable name).**
  Made the variable name explicit in Commit 1 item 1: `$left` for
  the inline `_add_unpacked` site, `$survivors[0]` for
  `_pack_survivors`. Both reduce to "first/left alternative
  wins."

## Changelog from v1 (post-review iteration 1)

Addresses six issues from project-plan-reviewer dispatch on
2026-05-25:

- **Critical #1.** Corrected framing to clarify that
  `_wrap_sa_result` already propagates `scope`/`graph`/`factory`;
  only `mop` is missing. `_pack_survivors` and the inline add-merge
  pack site need all four fields.
- **Critical #2.** Fixture migration pattern now explicitly
  requires declaring methods on the MOP (not just on ClassInfo)
  so Commit 2's method loop has data to emit.
- **Important #3.** `_scan_field_method_calls` reclassified from
  migration site to deletion (dead code, no production callers).
  Removed from "sites to migrate" list.
- **Important #4.** Added Commit 1 task to fix Actions.pm's
  ClassBlock loop to descend into chained VarDecl inits when
  populating `class_scope_vars`. Validated against Boolean.pm's
  `my $ZERO_CTX; my $ONE_CTX;`. Added regression test.
- **Important #5.** Resolved `_emit_method` parameter-type
  question: `_emit_method` accepts a `MOP::Method` post-Commit 2;
  the accessor surface (`name`, `params`, `body`, `return_type`)
  is verified compatible.
- **Important #6.** `xs-athx-no-args.t` migration spelled out:
  the module-name/class-name mismatch is intentional test
  coverage; MOP must register the class under its real name; the
  `_find_mop_class($mop)` lookup uses "first non-main class," not
  `$mop->for_class($self->module_name)`.

Also addressed suggestions:
- **Suggestion #7.** Renamed "the add merge-packing site" to
  "the inline packed-Context construction in `_add_unpacked`
  (FilterComposite.pm:475, inside the deterministic-tie-break
  branch)".
- **Suggestion #8.** Regression tests in `ctx-mop-propagation.t`
  now dispatch through public `multiply`/`add` methods, not
  private `_wrap_sa_result`/`_pack_survivors`, to avoid coupling
  to internal site names.
- **Suggestion #9.** Acceptance criterion 3 now enumerates the
  9 Commit 2 sites by name (including init_statics walk and XS
  BOOT walk) instead of saying "no legacy fallback in the analyze
  layer."
