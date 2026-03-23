# Eliminate call_method Dispatches in C-backed Earley

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all 72 `call_method` dispatches in the generated `earley.c`, replacing them with direct C function calls to achieve the performance gains the chalk.so architecture was designed to deliver.

**Architecture:** Two-step approach: (1) port XS.pm's self-call optimization to C.pm so Earley's own methods are called directly, (2) compile the 4 data model classes (Symbol, Rule, CoreItemIndex, LR0DFA) to C and wire `field_types` so cross-class calls also become direct.

**Tech Stack:** Perl 5.42.0, Target/C.pm codegen, chalk.so shared library, per-class XS wrappers

**Build time note:** Rebuilding chalk.so takes ~19 minutes (Earley.pm alone is ~19 min with FilterComposite). Steps that require a chalk.so rebuild are marked with **(rebuild ~19 min)**.

**Current State:** The generated `earley.c` has 72 `call_method` dispatches. Cross-class semiring calls (8 total) are already direct C via `field_types`. The remaining 72 break down as:

| Category | Count | Methods | Fix |
|----------|-------|---------|-----|
| Earley self-calls | 45 | `_chart_set`(9), `_chart_get`(6), `_chart_has`(5), `_is_complete`(6), `_advance_item`(5), `_symbol_after_dot`(3), `_make_item`(2), `_run_parse`(2), `_scan`(1), `_predict`(1), `_complete`(1), `_advance_from_completed`(1), `_is_safe_set`(1), `_format_parse_error`(1), `_emit_parse_diagnostic`(1) | Task 1: self-call optimization |
| CoreItemIndex field calls | 4 | `id_for`(2), `advance`(1), `item_for`(1) | Task 3: Earley field_types |
| LR0DFA field calls | 1 | `prediction_items_for`(1) | Task 3: Earley field_types |
| Rule object calls | 11 | `name`(4), `expressions`(7) | Task 4: type-aware dispatch |
| Symbol object calls | 11 | `value`(8), `is_reference`(2), `quantifier`(1) | Task 4: type-aware dispatch |

---

### Task 1: Self-call optimization in Target/C.pm

Port the existing self-call optimization from `Target/XS.pm` (lines 2646-2660) to `Target/C.pm`'s `_emit_method_call_expr`. When the invocant is `self` and the method exists in `$_class_methods`, emit `{slug}_{method}(aTHX_ self, ...)` instead of `call_method`.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm:448-528` (the `_emit_method_call_expr` method)
- Test: `t/bootstrap/c-self-call-optimization.t` (new)
- Verify: `t/bootstrap/c-end-to-end.t` (existing, must still pass)

**Precondition:** C.pm already builds `$_class_methods` at line 32 via `_scan_class_methods`. The data is there, it's just not used in `_emit_method_call_expr`.

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/c-self-call-optimization.t` with TWO parts:
1. **Codegen shape test:** Parse a small class with two methods where one calls the other on `$self`. Generate C via Target/C.pm. Assert the generated C contains a direct function call, not `call_method`.
2. **Behavioral test:** Must also include a test that covers a void self-call method (e.g., one that does not return a value), to verify the void path doesn't wrap in `SvREFCNT_inc`.

```perl
use 5.42.0;
use utf8;
use Test::More;

# Part 1: Codegen shape
# Parse a minimal class where method A calls $self->B()
# Verify the generated C uses direct slug_b(aTHX_ self) not call_method("b")
like($c_text, qr/testclass_method_b\(aTHX_ self\)/, 'self-call uses direct C function');
unlike($c_text, qr/call_method\("method_b"/, 'self-call does NOT use call_method');

# Part 2: Void method self-call
# A method that calls $self->_void_helper() (returns nothing)
# Must NOT wrap in SvREFCNT_inc — just emit the bare call
unlike($c_text, qr/SvREFCNT_inc\(testclass__void_helper/, 'void self-call not wrapped in SvREFCNT_inc');

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/c-self-call-optimization.t`
Expected: FAIL — generated C currently uses `call_method` for self-calls.

- [ ] **Step 3: Implement the self-call optimization**

In `C.pm`'s `_emit_method_call_expr`, after the pre-eval block (line 494) and before the `field_types` cross-class check (line 496), add:

```perl
# Self-call optimization: when invocant is self and method exists in this
# class, call the C function directly instead of Perl method dispatch.
# Mirrors the same optimization in Target/XS.pm lines 2646-2660.
# IMPORTANT: Do NOT wrap in SvREFCNT_inc — C.pm's exported functions
# return owned SVs (same contract as XS.pm's _impl_ helpers, line 2654).
# The field_types path uses SvREFCNT_inc because call_method/POPs returns
# a mortal SV — direct calls do not need this.
if ($invocant_expr eq 'self' && defined $self->_get_class_methods()
        && exists $self->_get_class_methods()->{$method_name}) {
    my $slug = $self->_get_current_slug();
    my $c_func_name = "${slug}_${method_name}";
    my @call_args = ('self', @arg_exprs);
    my $args_str = join(', ', @call_args);
    my $meta = $self->_get_class_methods()->{$method_name};
    my @stmts;
    push @stmts, @pre_eval;
    if ($meta->{returns}) {
        push @stmts, "${c_func_name}(aTHX_ ${args_str})";
    } else {
        # Void method — emit bare call, return &PL_sv_undef
        push @stmts, "${c_func_name}(aTHX_ ${args_str})";
        push @stmts, '&PL_sv_undef';
    }
    return '({ ' . join('; ', @stmts) . '; })';
}
```

Note the naming difference from XS.pm: XS uses `_impl_{slug}_{method}` (static helpers), C.pm uses `{slug}_{method}` (exported functions, line 287 of C.pm).

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/c-self-call-optimization.t`
Expected: PASS

- [ ] **Step 5: Rebuild chalk.so (rebuild ~19 min)**

```bash
script/build-chalk-so-generated
```

This must happen before end-to-end tests since those load the compiled chalk.so.

- [ ] **Step 6: Verify with earley.c inspection**

Count `call_method` in the rebuilt earley.c:

```bash
grep -c "call_method" .build/chalk-so-gen/earley.c
```

Expected: ~27 (down from 72 — the 45 self-calls eliminated).

Verify the self-call methods are now direct:
```bash
grep "earley__chart_set(aTHX_" .build/chalk-so-gen/earley.c | head -3
grep "earley__is_complete(aTHX_" .build/chalk-so-gen/earley.c | head -3
```

- [ ] **Step 7: Run existing end-to-end tests**

```bash
perl -Ilib t/bootstrap/c-end-to-end.t
```

Expected: All 21 tests pass. This is a behavioral regression test — the self-call optimization should produce identical parse results.

- [ ] **Step 8: Benchmark**

Run benchmark against Boolean.pm using the subprocess wrapper to measure impact of the 45 eliminated dispatches.

- [ ] **Step 9: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/C.pm t/bootstrap/c-self-call-optimization.t
git commit -m "feat: self-call optimization in Target/C.pm — eliminate 45 call_method dispatches"
```

---

### Task 2: Compile data model classes to C

Add Symbol, Rule, CoreItemIndex, and LR0DFA to the chalk.so build pipeline. These are small classes (21-155 lines) with simple accessors and methods. Their C implementations will be linked into chalk.so alongside the existing 7 classes.

**Files:**
- Modify: `script/build-chalk-so-generated` (add 4 classes to `@source_files`)
- Test: `t/bootstrap/c-data-model-classes.t` (new)
- Verify: `t/bootstrap/c-end-to-end.t` (update for 11 classes)

**Dependency:** Builds on Task 1 (self-call optimization must work first, but chalk.so rebuild can include both changes).

**Risk:** These classes are constructed by pure-Perl code (BNF parser, Desugar) before the C-backed Earley parser runs. The C compilation only replaces method dispatch — the objects are still created by Perl. This means `feature class` BOOT registration must be compatible with objects created before the C-backed class is loaded.

**Pre-implementation audit:** Before writing tests, audit these patterns against Target/C.pm capabilities:
1. `CoreItemIndex::register` — `%hash` field with `exists` check and early return
2. `CoreItemIndex::advance` — self-call (`$self->id_for(...)`) that Task 1 optimizes
3. `LR0DFA::_compute_prediction_closure` — `push @result, [$core_id, []] if defined $core_id` (conditional push of arrayref-of-arrayref)
4. `LR0DFA::_compute_nullable_set` — triple-nested `for` loops with `last` (early exit in nested loops has been problematic in XS codegen — see MEMORY.md)
5. `LR0DFA::_compute_prediction_closure` — `while (my $nt = shift @worklist)` with `%visited` tracking

If any of these patterns cannot compile, the affected method will be skipped (stays pure Perl). This is acceptable for `_compute_nullable_set` and `_compute_prediction_closure` (called once at construction, not hot path). The hot-path methods are `id_for`, `item_for`, `advance`, and `prediction_items_for` — these must compile.

- [ ] **Step 1: Audit C.pm codegen for data model patterns**

Check whether Target/C.pm handles:
- `%hash` field `exists` (CoreItemIndex::register, ::id_for)
- `join(':',...)` (CoreItemIndex key construction)
- `while (my $x = shift @list)` (LR0DFA worklist)
- Triple-nested `for` with `last`
- `push @arr, [$a, $b] if defined $c`

Document any gaps that need fixing before proceeding.

- [ ] **Step 2: Write the failing test**

Create `t/bootstrap/c-data-model-classes.t` that loads C-backed Symbol, Rule, CoreItemIndex, LR0DFA in a subprocess and verifies basic operations. Use the actual 10-rule bootstrap grammar from `docs/chalk-bootstrap.bnf` (not a toy grammar) to test CoreItemIndex and LR0DFA:

```perl
# Subprocess test (same pattern as c-end-to-end.t):
# 1. Load chalk.so + 11 per-class .so files
# 2. Create Symbol objects, verify type/value/quantifier/is_reference/is_terminal
# 3. Create Rule objects, verify name/expressions/alternative_count
# 4. Build CoreItemIndex from the 10-rule bootstrap grammar, verify id_for/advance/item_for
# 5. Build LR0DFA from the bootstrap grammar, verify prediction_items_for
```

- [ ] **Step 3: Run test to verify it fails**

Expected: FAIL — the 4 data model .so files don't exist yet.

- [ ] **Step 4: Add data model classes to build-chalk-so-generated**

Update `@source_files` in `script/build-chalk-so-generated`. Data model classes go first (they're dependencies of later classes):

```perl
my @source_files = (
    # Data model classes — compiled first since others depend on them
    ['Chalk::Grammar::Symbol',              'lib/Chalk/Grammar/Symbol.pm',              {}],
    ['Chalk::Grammar::Rule',                'lib/Chalk/Grammar/Rule.pm',                {}],
    ['Chalk::Bootstrap::CoreItemIndex',     'lib/Chalk/Bootstrap/CoreItemIndex.pm',     {}],
    ['Chalk::Bootstrap::LR0DFA',            'lib/Chalk/Bootstrap/LR0DFA.pm',            {
        core_index => 'Chalk::Bootstrap::CoreItemIndex',
    }],
    # Existing semiring + Earley classes (unchanged)
    ['Chalk::Bootstrap::Semiring::Boolean',         ...],
    ...
);
```

Note: LR0DFA has a `$core_index :param` field holding a CoreItemIndex, so it gets `field_types` for its OWN internal calls (e.g., `$core_index->id_for()` inside `_compute_prediction_closure`). This is separate from Task 3, which adds `field_types` to Earley's spec so Earley's calls to CoreItemIndex/LR0DFA are direct.

Also update the `@classes` array in `c-end-to-end.t` to include the 4 new classes.

- [ ] **Step 5: Build and verify the 4 new classes compile (rebuild ~19 min)**

```bash
script/build-chalk-so-generated
```

If any class fails to compile to C, the build will report which methods were skipped. Address any codegen gaps found in Step 1's audit. If `_compute_nullable_set` or `_compute_prediction_closure` are skipped, that's acceptable — they're construction-time, not hot path.

- [ ] **Step 6: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/c-data-model-classes.t`
Expected: PASS — all 4 classes load and basic operations work.

- [ ] **Step 7: Commit**

```bash
git add script/build-chalk-so-generated t/bootstrap/c-data-model-classes.t
git commit -m "feat: compile Symbol, Rule, CoreItemIndex, LR0DFA to C in chalk.so"
```

---

### Task 3: Wire field_types for CoreItemIndex and LR0DFA in Earley

Now that CoreItemIndex and LR0DFA are compiled to C (Task 2), add `field_types` entries to **Earley's** build spec so Earley's calls to `$core_index->id_for()`, `$lr0_dfa->prediction_items_for()`, etc. become direct C calls.

**Clarification:** Task 2 added `field_types` to LR0DFA's own spec (so LR0DFA internally calls CoreItemIndex directly). This task adds `field_types` to Earley's spec (so Earley calls CoreItemIndex and LR0DFA directly).

**Files:**
- Modify: `script/build-chalk-so-generated` (update Earley's `field_types`)
- Verify: Rebuild chalk.so, count `call_method` in earley.c

- [ ] **Step 1: Update Earley's field_types**

In `script/build-chalk-so-generated`, update Earley's spec:

```perl
['Chalk::Bootstrap::Earley', 'lib/Chalk/Bootstrap/Earley.pm', {
    semiring   => 'Chalk::Bootstrap::Semiring::FilterComposite',
    core_index => 'Chalk::Bootstrap::CoreItemIndex',
    lr0_dfa    => 'Chalk::Bootstrap::LR0DFA',
}],
```

- [ ] **Step 2: Rebuild and verify (rebuild ~19 min)**

```bash
script/build-chalk-so-generated
grep -c "call_method" .build/chalk-so-gen/earley.c
```

Expected: ~22 (down from ~27 — eliminates 5 calls: `id_for`(2), `advance`(1), `item_for`(1), `prediction_items_for`(1)).

- [ ] **Step 3: Run end-to-end test**

```bash
perl -Ilib t/bootstrap/c-end-to-end.t
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add script/build-chalk-so-generated
git commit -m "feat: wire field_types for core_index and lr0_dfa in Earley C codegen"
```

---

### Task 4: Type-aware dispatch for Rule and Symbol objects

The remaining ~22 `call_method` dispatches are calls on Rule and Symbol objects that come from grammar arrays and item hashes — not from named fields. The `field_types` mechanism doesn't apply because these aren't field accesses.

This requires a new codegen pattern: **type-aware method-name dispatch**. When a method name uniquely belongs to one compiled class, emit a direct C call regardless of the invocant's static type.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (new `compiled_methods` field + dispatch in `_emit_method_call_expr`)
- Modify: `script/build-chalk-so-generated` (two-pass generation for Earley)
- Test: `t/bootstrap/c-type-aware-dispatch.t` (new)
- Verify: Rebuild chalk.so, assert zero `call_method` in earley.c

**Two-pass generation requirement:** The `compiled_methods` map is built from the exported functions of ALL compiled classes (known after Phase 3). But each class is generated during Phase 3 with its own `Target::C` instance. Solution: Phase 3 generates all classes without `compiled_methods`. Then Phase 3b re-generates ONLY Earley (the only class that calls Rule/Symbol methods) with `compiled_methods` populated from Phase 3's results. This adds negligible time since Earley's C generation is fast (~1s) — the 19-minute cost is parsing, not generation.

**Ambiguity analysis for the 11-class compiled set:**
- `name` — unique to Rule (no other compiled class has it)
- `expressions` — unique to Rule
- `value` — unique to Symbol
- `is_reference` — unique to Symbol
- `quantifier` — unique to Symbol
- `is_quantified` — unique to Symbol
- `init_statics` — present in ALL classes → ambiguous, correctly excluded
- `add`, `multiply`, `is_zero`, `one`, `zero` — present in multiple semirings → ambiguous, correctly excluded (these already use `field_types` dispatch)
- `register`, `id_for`, `advance`, `item_for` — unique to CoreItemIndex
- `prediction_items_for`, `build`, `is_nullable` — unique to LR0DFA

All 22 remaining Rule/Symbol methods resolve unambiguously. Semiring interface methods (`add`/`multiply`/`is_zero`/etc.) are correctly marked ambiguous and excluded — they already go through `field_types` dispatch, not type-aware dispatch.

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/c-type-aware-dispatch.t` that generates C for a class that calls methods on Rule/Symbol objects, and verifies direct C calls are emitted instead of `call_method`.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — no type-aware dispatch exists yet.

- [ ] **Step 3: Add `compiled_methods` field to Target/C.pm**

```perl
field $compiled_methods :param = undef;  # hashref: method_name => class_slug (unambiguous only)
```

In `_emit_method_call_expr`, after self-call and field_types checks, before the `call_method` fallback:

```perl
# Type-aware dispatch: if method_name uniquely belongs to one compiled
# class across the entire build, emit a direct C call. Handles calls on
# objects from data structures (grammar arrays, item hashes) where
# field_types can't apply because the invocant isn't a named field.
# IMPORTANT: Ambiguous methods (present in multiple classes) are excluded
# from $compiled_methods by the build script — they fall through to
# call_method. This is safe because the ambiguous methods (semiring
# interface: add/multiply/is_zero) already use field_types dispatch.
if (defined $compiled_methods && exists $compiled_methods->{$method_name}) {
    my $target_slug = $compiled_methods->{$method_name};
    my $c_func_name = "${target_slug}_${method_name}";
    my @call_args = ($invocant_expr, @arg_exprs);
    my $args_str = join(', ', @call_args);
    my @stmts;
    push @stmts, @pre_eval;
    push @stmts, "${c_func_name}(aTHX_ ${args_str})";
    return '({ ' . join('; ', @stmts) . '; })';
}
```

- [ ] **Step 4: Implement two-pass generation in build-chalk-so-generated**

After Phase 3 completes (all classes generated), build `%method_to_slug`:

```perl
# Build reverse index: method_name => slug for unambiguous methods.
my %method_to_slug;
for my $info (@generated) {
    my $slug = $info->{slug};
    for my $fn ($info->{exported_functions}->@*) {
        my $func_name = $fn->{name};  # exported_functions is arrayref of hashrefs
        (my $method = $func_name) =~ s/^${slug}_//;
        if (exists $method_to_slug{$method}) {
            $method_to_slug{$method} = undef;  # ambiguous
        } else {
            $method_to_slug{$method} = $slug;
        }
    }
}
# Remove ambiguous entries
delete $method_to_slug{$_} for grep { !defined $method_to_slug{$_} } keys %method_to_slug;
```

Then re-generate Earley only (Phase 3b):

```perl
# Phase 3b: Re-generate Earley with type-aware dispatch
for my $info (@parsed) {
    next unless $info->{class_name} eq 'Chalk::Bootstrap::Earley';
    my $ft = $info->{field_types} // {};
    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name      => $info->{class_name},
        ($ft->%* ? (field_types => $ft) : ()),
        compiled_methods => \%method_to_slug,
    );
    # Re-generate, replace earley entry in @generated
    ...
}
```

- [ ] **Step 5: Run test to verify it passes**

- [ ] **Step 6: Rebuild chalk.so and verify zero call_method (rebuild ~19 min)**

```bash
script/build-chalk-so-generated
grep -c "call_method" .build/chalk-so-gen/earley.c
```

Expected: 0. Add this as an automated assertion in the test suite:

```perl
# In c-type-aware-dispatch.t or a dedicated verification test:
my $count = `grep -c "call_method" .build/chalk-so-gen/earley.c`;
chomp $count;
is($count, '0', 'earley.c has zero call_method dispatches');
```

- [ ] **Step 7: Run full test suite**

```bash
perl -Ilib t/bootstrap/c-end-to-end.t
perl -Ilib t/bootstrap/c-self-call-optimization.t
perl -Ilib t/bootstrap/c-data-model-classes.t
perl -Ilib t/bootstrap/c-type-aware-dispatch.t
```

- [ ] **Step 8: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/C.pm script/build-chalk-so-generated \
    t/bootstrap/c-type-aware-dispatch.t
git commit -m "feat: type-aware dispatch eliminates remaining call_method dispatches in earley.c"
```

---

### Task 5: Benchmark and update design docs

**Files:**
- Modify: `docs/superpowers/specs/2026-03-19-c-codegen-redesign-design.md` (add Phase 4a/4b)
- Create: benchmark comparison data

- [ ] **Step 1: Run benchmark suite**

Parse Boolean.pm, Structural.pm, FilterComposite.pm, and Earley.pm with the fully-optimized chalk.so (zero `call_method`). Compare to the baseline measurements:

| File | Lines | Before (72 call_method) | After (0 call_method) | Speedup |
|------|-------|------------------------|----------------------|---------|
| Boolean.pm | 69 | 3.9s | ? | ? |
| Structural.pm | 375 | 50.1s | ? | ? |
| FilterComposite.pm | 258 | 57.9s | ? | ? |
| Earley.pm | 1098 | 1135s | ? | ? |

- [ ] **Step 2: Update design doc**

Add "Phase 4a: Intra-class self-calls" to the design spec, documenting:
- The gap: design covered cross-class calls (Phase 4) but not self-calls
- The fix: ported XS.pm's self-call optimization to C.pm
- Impact: 45 of 72 dispatches eliminated
- Key insight: C.pm already had `$_class_methods` populated but never used it

Add "Phase 4b: Data model classes + type-aware dispatch" documenting:
- Compiled Symbol, Rule, CoreItemIndex, LR0DFA to C (275 lines total)
- Extended `field_types` for CoreItemIndex and LR0DFA fields in both LR0DFA's and Earley's specs
- Added type-aware dispatch: method-name heuristic for unambiguous methods across compiled set
- Two-pass generation: Phase 3 generates all classes, Phase 3b re-generates Earley with `compiled_methods`
- Impact: remaining 27 dispatches eliminated

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-03-19-c-codegen-redesign-design.md
git commit -m "docs: update design spec with Phase 4a/4b — self-call and data model optimization"
```

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `lib/Chalk/Bootstrap/Perl/Target/C.pm` | Modify | Add self-call optimization + `compiled_methods` field + type-aware dispatch |
| `script/build-chalk-so-generated` | Modify | Add 4 data model classes, update Earley field_types, add Phase 3b two-pass |
| `t/bootstrap/c-self-call-optimization.t` | Create | Codegen shape + void-method tests for self-call optimization |
| `t/bootstrap/c-data-model-classes.t` | Create | Behavioral tests for C-backed Symbol/Rule/CoreItemIndex/LR0DFA |
| `t/bootstrap/c-type-aware-dispatch.t` | Create | Codegen shape + call_method count assertion |
| `t/bootstrap/c-end-to-end.t` | Modify | Update @classes for 11 compiled classes |
| `docs/superpowers/specs/2026-03-19-c-codegen-redesign-design.md` | Modify | Add Phase 4a/4b documentation |

## Risk Assessment

**Task 1 (self-calls):** Low risk. The pattern is proven in XS.pm and the infrastructure (`$_class_methods`) already exists in C.pm. Key detail: do NOT use `SvREFCNT_inc` — direct C calls return owned SVs, unlike `call_method`/`POPs` which returns mortals.

**Task 2 (compile data model):** Medium risk. Symbol and Rule are trivially simple (only `:param :reader` fields and simple methods). CoreItemIndex uses `%hash` fields with `exists` and `join()` — audit C.pm first. LR0DFA has `while` loops with `shift @worklist`, triple-nested `for` loops with `last`, and conditional `push @arr, [$a, $b]` — these patterns may hit codegen gaps. Mitigated by Step 1 audit. Construction-time methods (`_compute_nullable_set`, `_compute_prediction_closure`) can stay pure Perl if they don't compile — only the hot-path accessors must compile.

**Task 3 (field_types wiring):** Low risk. Mechanical change to build script. Clearly separated from Task 2's LR0DFA field_types (which is LR0DFA calling CoreItemIndex internally).

**Task 4 (type-aware dispatch):** Medium risk. The method-name heuristic is safe for the current 11-class set (all target methods are unambiguous). The two-pass generation adds complexity to the build script. The `exported_functions` data structure is an arrayref of hashrefs (`{name, return_type, params}`), NOT plain strings — access via `$fn->{name}`.

**Task 5 (benchmark):** Zero implementation risk. The interesting question is how much speedup we get. The hypothesis: eliminating 72 `call_method` dispatches in the hot inner loop should yield a significant speedup for large files (Earley.pm), since each dispatch involves full Perl stack manipulation and method resolution, called millions of times per parse.
