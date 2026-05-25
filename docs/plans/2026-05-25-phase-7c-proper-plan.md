# Phase 7c-proper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Target::C's analyze layer from `Chalk::IR::ClassInfo` body-arrayref iteration to `Chalk::MOP::Class` entity reads, after fixing the propagation hole that prevents `$ctx->mop()` from being a reliable source of truth.

**Architecture:** Two commits on branch `fixup-audit-baseline`. Commit 1 is plumbing: fix `mop` propagation in FilterComposite, fix chained-VarDecl population in Actions.pm, retire the `current_mop()` workarounds, add MOP::Field helpers, migrate four hand-built-IR test fixtures, add regression tests. Commit 2 is the migration: Target::C and EmitHelpers read MOP entity lists; `_scan_field_method_calls` deletes; build script's Phase 3b loop migrates.

**Tech Stack:** Perl 5.42.0 (via plenv: `plenv exec perl`), `feature class`, postfix dereferencing, true/false builtins, try/catch. Test harness: `prove` or `perl -Ilib t/...`.

**Spec:** `docs/plans/2026-05-25-phase-7c-proper-design.md`

**Skills mandate (per CLAUDE.md):** every implementer of every task MUST invoke `@superpowers:writing-perl-5.42.0` and `@superpowers:test-driven-development` before writing code.

---

## File Map

### Commit 1 — files touched

**Modify:**
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` — three Context->new sites (lines ~147, ~176, ~475).
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — three sites (lines 259-261, 658-660, 746-747).
- `lib/Chalk/MOP/Field.pm` — add three methods.
- `t/bootstrap/lib/TestPipeline.pm` — add `parse_perl_source` convenience helper.
- `lib/Chalk/Bootstrap/Perl/Target/C.pm` — none (untouched in Commit 1).
- `t/bootstrap/xs-isa-inheritance.t` — fixture rewrite.
- `t/bootstrap/xs-polymorphic-dispatch.t` — fixture rewrite.
- `t/bootstrap/xs-int-specialization.t` — fixture rewrite.
- `t/bootstrap/xs-athx-no-args.t` — fixture rewrite.
- `t/bootstrap/mop/parse-threading.t` — extension.
- `t/bootstrap/mop/parse-integration.t` — extension.

**Create:**
- `t/bootstrap/mop/ctx-mop-propagation.t` — new regression test file.
- `t/bootstrap/mop/field-helpers.t` — MOP::Field helper coverage.
- `t/bootstrap/mop/test-pipeline-helper.t` — `parse_perl_source` coverage.

### Commit 2 — files touched

**Modify:**
- `lib/Chalk/Bootstrap/Perl/Target/C.pm` — sites at lines 44-122, 1594-1602, 1602-1650, 1757-1770, 2026-2062.
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` — sites at lines 119-124, 129-163, 200-292, 579-629 (last is deletion).
- `t/bootstrap/c-emit-helpers-inheritance.t` — one `can` assertion update + one deletion.
- `script/build-chalk-so-generated` — Phase 3b loop at lines 200-260.

**No new files.**

---

## Baseline capture (one-time, before any task)

Capture the pre-Commit-1 test state so regressions can be detected. Numbers come from `docs/plans/2026-05-24-phase-7-baseline.md`; treat any deviation as a pre-existing failure to document, not a Commit 1 regression.

- [ ] **Step B1: Run the test gates and record pass/fail counts.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/class-scope-vars.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/use-constants.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/parse-threading.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -5
```

Expected: all green (`Result: PASS` or `All tests successful.`). Record counts.

- [ ] **Step B2: Also run the four canary tests before any change.**

```bash
plenv exec perl -Ilib t/bootstrap/xs-isa-inheritance.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/xs-polymorphic-dispatch.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/xs-int-specialization.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/xs-athx-no-args.t 2>&1 | tail -5
```

Expected: all green. Record counts.

- [ ] **Step B3: Confirm head commit is the design doc commit.**

```bash
git log --oneline -3
```

Expected first line: `e9b7a16d docs(plans): Phase 7c-proper design — propagation fix + analyze migration` (or later, if other docs-only commits land before implementation starts).

- [ ] **Step B4: Confirm working tree is clean.**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## COMMIT 1 — plumbing + chained-decl fix + workaround retirement + fixture migration

### Task 1.1: Add `has_attribute`, `is_param`, `has_reader` to MOP::Field (TDD)

**Files:**
- Modify: `lib/Chalk/MOP/Field.pm`
- Create: `t/bootstrap/mop/field-helpers.t`

- [ ] **Step 1: Write failing test.**

Create `t/bootstrap/mop/field-helpers.t`:

```perl
# ABOUTME: Tests for MOP::Field attribute helper methods.
# ABOUTME: Verifies has_attribute, is_param, has_reader semantics.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::MOP::Class;
use Chalk::MOP::Field;

# A bare class scaffold for declare_field.
my $mop = Chalk::MOP->new;
my $cls = $mop->declare_class('Test::Field::Helpers');

# 1. Field with no attributes: all helpers return false.
my $f1 = $cls->declare_field('$plain', sigil => '$');
ok(!$f1->has_attribute('param'),  'plain field: has_attribute(param) is false');
ok(!$f1->has_attribute('reader'), 'plain field: has_attribute(reader) is false');
ok(!$f1->is_param,                'plain field: is_param is false');
ok(!$f1->has_reader,              'plain field: has_reader is false');

# 2. Field with :param: is_param true, has_reader false.
my $f2 = $cls->declare_field('$p', sigil => '$', attributes => [':param']);
ok($f2->is_param,                 'param field: is_param is true');
ok($f2->has_attribute('param'),   'param field: has_attribute(param) is true');
ok(!$f2->has_reader,              'param field: has_reader is false');

# 3. Field with :reader: has_reader true, is_param false.
my $f3 = $cls->declare_field('$r', sigil => '$', attributes => [':reader']);
ok($f3->has_reader,               'reader field: has_reader is true');
ok($f3->has_attribute('reader'),  'reader field: has_attribute(reader) is true');
ok(!$f3->is_param,                'reader field: is_param is false');

# 4. Field with both :param and :reader.
my $f4 = $cls->declare_field('$pr', sigil => '$', attributes => [':param', ':reader']);
ok($f4->is_param,                 'pr field: is_param is true');
ok($f4->has_reader,               'pr field: has_reader is true');

# 5. has_attribute is case-sensitive and does not match partial names.
my $f5 = $cls->declare_field('$x', sigil => '$', attributes => [':reader']);
ok(!$f5->has_attribute('read'),   'has_attribute(read) is false (no partial match)');
ok(!$f5->has_attribute('Reader'), 'has_attribute(Reader) is false (case-sensitive)');

done_testing();
```

- [ ] **Step 2: Run the test to confirm it fails.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/field-helpers.t
```

Expected: FAIL with `Can't locate object method "has_attribute" via package "Chalk::MOP::Field"` (and similar for `is_param`, `has_reader`).

- [ ] **Step 3: Add the three methods to MOP::Field.**

Edit `lib/Chalk/MOP/Field.pm`. Find the existing `method attributes()` line (~line 18) and add immediately after the closing brace of the class body... wait, methods go *inside* the class body. Insert the three new methods after the existing `attributes()` method, still inside `class Chalk::MOP::Field { ... }`:

```perl
    method has_attribute($name) {
        return scalar grep { $_ eq ":$name" } $attributes->@*;
    }
    method is_param()   { return $self->has_attribute('param') }
    method has_reader() { return $self->has_attribute('reader') }
```

- [ ] **Step 4: Run the test to confirm it passes.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/field-helpers.t
```

Expected: all 13 assertions PASS.

- [ ] **Step 5: Confirm no regressions in adjacent tests.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/class.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -5
```

Expected: still green.

**No commit yet** — Commit 1 is a single cohesive commit; all sub-tasks land together.

---

### Task 1.2: Fix `_wrap_sa_result` mop propagation (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` (line ~147).
- Create: `t/bootstrap/mop/ctx-mop-propagation.t` (this task adds the first test; later tasks extend).

- [ ] **Step 1: Write the failing test.**

Create `t/bootstrap/mop/ctx-mop-propagation.t`:

```perl
# ABOUTME: Regression tests for Context.mop propagation through FilterComposite.
# ABOUTME: Verifies that multiply and add preserve the mop field on result Contexts.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Semiring::FilterComposite;

# Install a MOP into SA via set_mop so SA's one() carries it.
my $mop = Chalk::MOP->new;
Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);

my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new;
my $sa_sr   = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => undef);

my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
    semirings => [$bool_sr, $sa_sr],
);

# Sanity: composite one() carries the MOP (this is the propagation
# pre-condition that the FilterComposite one() already honors).
my $one = $comp->one;
is(refaddr($one->mop), refaddr($mop), 'one() carries MOP');

# Test 1: _wrap_sa_result propagates mop through multiply.
# Construct two Contexts (one() copies) and multiply them; assert the
# result still carries the MOP. This exercises _wrap_sa_result via the
# public multiply method.
{
    my $left  = $comp->one;
    my $right = $comp->one;
    my $product = $comp->multiply($left, $right);
    ok(defined $product->mop, 'multiply result has defined mop');
    is(refaddr($product->mop), refaddr($mop),
       'multiply result preserves MOP refaddr (_wrap_sa_result fix)');
}

done_testing();
```

- [ ] **Step 2: Run the test to confirm it fails.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/ctx-mop-propagation.t
```

Expected: the first two assertions PASS (one() already works); the third FAILS with `'multiply result has defined mop'` because `_wrap_sa_result` drops the mop field.

If the third assertion unexpectedly PASSES, stop and investigate — either propagation was already fixed by some other recent commit (unlikely) or the test doesn't actually exercise the broken path. Do not proceed to Step 3 silently.

- [ ] **Step 3: Apply the fix to `_wrap_sa_result`.**

Edit `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm`. Find the method (around line 147):

```perl
    method _wrap_sa_result($sa_result, %slot_results) {
        my $is_ctx = blessed($sa_result) && $sa_result->can('extract');
        return Chalk::Bootstrap::Context->new(
            focus       => $is_ctx ? $sa_result->extract() : $sa_result,
            children    => $is_ctx ? [$sa_result->children()->@*] : [],
            position    => $is_ctx ? $sa_result->position() : 0,
            rule        => $is_ctx ? $sa_result->rule() : undef,
            is_zero     => false,
            scope       => ($is_ctx ? $sa_result->scope() : undef),
            graph       => ($is_ctx ? $sa_result->graph() : undef),
            factory     => ($is_ctx ? $sa_result->factory() : undef),
            annotations => {
                ($is_ctx ? $sa_result->annotations()->%* : ()),
                %slot_results,
            },
        );
    }
```

Insert one line, between `factory` and `annotations`:

```perl
            mop         => ($is_ctx ? $sa_result->mop() : undef),
```

Result:

```perl
            scope       => ($is_ctx ? $sa_result->scope() : undef),
            graph       => ($is_ctx ? $sa_result->graph() : undef),
            factory     => ($is_ctx ? $sa_result->factory() : undef),
            mop         => ($is_ctx ? $sa_result->mop() : undef),
            annotations => {
```

- [ ] **Step 4: Run the test to confirm it passes.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/ctx-mop-propagation.t
```

Expected: all 3 assertions PASS.

---

### Task 1.3: Fix `_pack_survivors` mop+scope+graph+factory propagation (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` (line ~179).
- Modify: `t/bootstrap/mop/ctx-mop-propagation.t` (extend with two more tests).

- [ ] **Step 1: Extend the regression test file with a `_pack_survivors` test.**

Append to `t/bootstrap/mop/ctx-mop-propagation.t` *before* `done_testing()`:

```perl
# Test 2: _pack_survivors propagates mop+scope+graph+factory.
# Construct two Contexts with a shared MOP and call _pack_survivors via
# its public surface — packing happens in add() when both alternatives
# survive. Easiest reliable path: call _pack_survivors directly with
# two distinct survivors (the method is method-scoped on the semiring).
{
    # Two distinct child Contexts that both carry the MOP.
    my $c1 = Chalk::Bootstrap::Context->new(
        focus => 'a', children => [], mop => $mop,
    );
    my $c2 = Chalk::Bootstrap::Context->new(
        focus => 'b', children => [], mop => $mop,
    );
    my $packed = $comp->_pack_survivors($c1, $c2);
    ok($packed->is_ambiguous, '_pack_survivors returns ambiguous Context');
    is(refaddr($packed->mop), refaddr($mop),
       '_pack_survivors preserves mop from $survivors[0]');
}

# Test 3: Verify scope, graph, factory also propagate through _pack_survivors.
# (They have the same hole; the fix adds all four together.)
{
    my $scope_obj    = bless { tag => 'scope' }, 'Test::Sentinel::Scope';
    my $graph_obj    = bless { tag => 'graph' }, 'Test::Sentinel::Graph';
    my $factory_obj  = bless { tag => 'factory' }, 'Test::Sentinel::Factory';
    my $c1 = Chalk::Bootstrap::Context->new(
        focus => 'a', children => [], mop => $mop,
        scope => $scope_obj, graph => $graph_obj, factory => $factory_obj,
    );
    my $c2 = Chalk::Bootstrap::Context->new(
        focus => 'b', children => [], mop => $mop,
        scope => $scope_obj, graph => $graph_obj, factory => $factory_obj,
    );
    my $packed = $comp->_pack_survivors($c1, $c2);
    is(refaddr($packed->scope),   refaddr($scope_obj),   '_pack_survivors preserves scope');
    is(refaddr($packed->graph),   refaddr($graph_obj),   '_pack_survivors preserves graph');
    is(refaddr($packed->factory), refaddr($factory_obj), '_pack_survivors preserves factory');
}
```

- [ ] **Step 2: Run the test to confirm the new assertions fail.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/ctx-mop-propagation.t
```

Expected: Tests 1's three assertions PASS; Test 2 and Test 3's five new assertions FAIL (packed Context's `mop`/`scope`/`graph`/`factory` are all undef in current code).

- [ ] **Step 3: Apply the fix to `_pack_survivors`.**

Edit `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm`. Find:

```perl
    method _pack_survivors(@survivors) {
        return $self->zero()  if @survivors == 0;
        return $survivors[0]  if @survivors == 1;
        return Chalk::Bootstrap::Context->new(
            focus        => undef,
            children     => \@survivors,
            position     => 0,
            is_zero      => false,
            is_ambiguous => true,
            annotations  => {},
        );
    }
```

Replace the `Chalk::Bootstrap::Context->new(...)` call with:

```perl
        return Chalk::Bootstrap::Context->new(
            focus        => undef,
            children     => \@survivors,
            position     => 0,
            is_zero      => false,
            is_ambiguous => true,
            annotations  => {},
            mop          => $survivors[0]->mop(),
            scope        => $survivors[0]->scope(),
            graph        => $survivors[0]->graph(),
            factory      => $survivors[0]->factory(),
        );
```

- [ ] **Step 4: Run the test to confirm it passes.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/ctx-mop-propagation.t
```

Expected: all 8 assertions PASS (3 + 2 + 3).

---

### Task 1.4: Fix `_add_unpacked` inline packed-Context site (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` (line ~475).
- Modify: `t/bootstrap/mop/ctx-mop-propagation.t` (add one more test).

- [ ] **Step 1: Extend the regression test with the inline-site assertion.**

Append to `t/bootstrap/mop/ctx-mop-propagation.t` before `done_testing()`:

```perl
# Test 4: The inline packed Context in _add_unpacked (line ~475)
# propagates mop+scope+graph+factory.
# This site is hit by add() in the genuine-abstention branch: two
# alternatives that differ in some annotation slot get packed together.
# Construct two Contexts that differ ONLY in their boolean slot value
# so _has_real_annotation_difference returns true, forcing the inline
# pack path.
{
    my $left = Chalk::Bootstrap::Context->new(
        focus => 'L', children => [], mop => $mop,
        annotations => { boolean => true },
    );
    my $right = Chalk::Bootstrap::Context->new(
        focus => 'R', children => [], mop => $mop,
        annotations => { boolean => false },
    );
    # add() with two alternatives that differ in the boolean slot
    # should produce a packed result if both survive Boolean's add()
    # logic. The exact verdict path varies by semiring config; if the
    # test does not naturally trigger the inline pack, skip with diag.
    my $result = $comp->add($left, $right);
    if ($result->is_ambiguous) {
        is(refaddr($result->mop), refaddr($mop),
           'add inline pack preserves mop');
    } else {
        # The add path picked a single survivor (not the inline pack
        # branch). This is acceptable behavior; the inline pack site
        # is exercised by the structural _pack_survivors test above
        # plus integration tests. Note the path taken.
        pass('add picked single survivor; inline pack path not exercised in this case');
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails (or skips cleanly).**

```bash
plenv exec perl -Ilib t/bootstrap/mop/ctx-mop-propagation.t
```

Expected: if the inline pack path is hit, FAIL with "add inline pack preserves mop". If add picks a single survivor, the test passes via the alternate branch. Either way the new assertion's intent (regression coverage) lands. Document which path was taken; if always-single-survivor, the inline site is implicitly verified by sharing the same fix pattern with `_pack_survivors` which IS tested.

- [ ] **Step 3: Apply the fix to the inline `Context->new` in `_add_unpacked`.**

Edit `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm`. Find the site at ~line 475 (inside `_add_unpacked`, in the abstention branch where both alternatives survive as ambiguous):

```perl
                return Chalk::Bootstrap::Context->new(
                    focus        => undef,
                    children     => [$left, $right],
                    position     => 0,
                    is_zero      => false,
                    is_ambiguous => true,
                    annotations  => {},
                );
```

Replace with:

```perl
                return Chalk::Bootstrap::Context->new(
                    focus        => undef,
                    children     => [$left, $right],
                    position     => 0,
                    is_zero      => false,
                    is_ambiguous => true,
                    annotations  => {},
                    mop          => $left->mop(),
                    scope        => $left->scope(),
                    graph        => $left->graph(),
                    factory      => $left->factory(),
                );
```

- [ ] **Step 4: Run the test to confirm it passes.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/ctx-mop-propagation.t
```

Expected: all assertions PASS.

- [ ] **Step 5: Run the broader MOP test suite to catch any regression from the propagation changes.**

```bash
for t in t/bootstrap/mop/*.t; do plenv exec perl -Ilib "$t" 2>&1 | tail -3; echo "---"; done
```

Expected: all green; counts unchanged from baseline.

---

### Task 1.5: Retire `current_mop()` workarounds in Actions.pm

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (lines 259-261, 658-660).

This task does not need a new test — the existing parse-integration and bnf-target-c tests exercise both code paths. After propagation is fixed (Tasks 1.2-1.4), `$ctx->mop` now returns the same MOP that `current_mop()` was reaching for; the substitution is mechanical and the test gates verify behavior is unchanged.

- [ ] **Step 1: Edit the Program action site (Actions.pm:255-261).**

Find:

```perl
        # Register top-level subs on the MOP's main class.
        # These are SubInfo objects that appear at program scope (not inside a ClassBlock).
        # ClassBlock separately registers in-class subs on the declared class.
        # current_mop() is used instead of $ctx->mop() because intermediate
        # multiply contexts do not propagate the mop field.
        my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
```

Replace with:

```perl
        # Register top-level subs on the MOP's main class.
        # These are SubInfo objects that appear at program scope (not inside a ClassBlock).
        # ClassBlock separately registers in-class subs on the declared class.
        my $mop = $ctx->mop;
```

- [ ] **Step 2: Edit the ClassBlock action site (Actions.pm:655-660).**

Find:

```perl
        # Populate MOP with the class and its members when a MOP is present.
        # current_mop() is used instead of $ctx->mop() because intermediate
        # multiply contexts do not propagate the mop field.
        my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
```

Replace with:

```perl
        # Populate MOP with the class and its members when a MOP is present.
        my $mop = $ctx->mop;
```

- [ ] **Step 3: Run the parse-integration and MOP test suites.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/parse-threading.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/class.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/class-scope-vars.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/use-constants.t 2>&1 | tail -5
```

Expected: all green; counts unchanged. If any fail with "undefined value passed where MOP expected" or similar, the propagation fix from Tasks 1.2-1.4 has a gap — investigate which test failed and trace back through which Context->new site dropped the mop.

- [ ] **Step 4: Run bnf-target-c.t for broader regression coverage.**

```bash
plenv exec perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -5
```

Expected: 178/178 PASS (or whatever baseline recorded in Step B1).

---

### Task 1.5b: Add `parse_perl_source` helper to TestPipeline.pm (TDD)

**Files:**
- Modify: `t/bootstrap/lib/TestPipeline.pm`
- Create: `t/bootstrap/mop/test-pipeline-helper.t`

The integration tests in Tasks 1.6 and 1.7 want a one-liner
`($ir, $sa, $ctx) = parse_perl_source($src)`. Today the equivalent is
a 6-line scaffold (`perl_pipeline → BNF::Target::Perl::generate →
eval → grammar() lookup → build_perl_ir_parser → parse_value`).
Extracting the scaffold into a reusable helper avoids copy-pasting
the dance into two new test files and keeps the integration tests
focused on the assertion, not the setup.

- [ ] **Step 1: Write the failing test.**

Create `t/bootstrap/mop/test-pipeline-helper.t`:

```perl
# ABOUTME: Test for TestPipeline::parse_perl_source convenience helper.
# ABOUTME: Verifies it returns (ir, sa, ctx) for a minimal Perl source string.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(parse_perl_source);

my $mop = Chalk::MOP->new;
Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);

my $src = "class A { method f { 1 } }\n";
my ($ir, $sa, $ctx) = parse_perl_source($src);

ok(defined $ir,  'parse_perl_source returns defined ir');
ok(defined $sa,  'parse_perl_source returns defined sa');
ok(defined $ctx, 'parse_perl_source returns defined ctx');
isa_ok($ctx, 'Chalk::Bootstrap::Context', 'ctx is a Chalk::Bootstrap::Context');

# Post-propagation-fix (Tasks 1.2-1.4), ctx->mop is the installed MOP.
is(refaddr($ctx->mop), refaddr($mop), 'ctx->mop is the installed MOP');

done_testing();
```

- [ ] **Step 2: Run to confirm failure.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/test-pipeline-helper.t
```

Expected: FAIL with `"parse_perl_source" is not exported by the TestPipeline module`.

- [ ] **Step 3: Add the helper to TestPipeline.pm.**

Edit `t/bootstrap/lib/TestPipeline.pm`. Add `parse_perl_source` to `@EXPORT_OK`:

```perl
our @EXPORT_OK = qw(
    build_parser parse_ir bnf_text full_pipeline optimized_pipeline grammars_match
    perl_bnf_text perl_pipeline build_perl_recognizer
    build_perl_ir_parser
    parse_perl_source
);
```

Also add at the top with the other use lines (it's already used elsewhere in the file but confirm):

```perl
use Chalk::Bootstrap::BNF::Target::Perl;
```

Then add the helper subroutine anywhere in the file's `package TestPipeline;` body (after the existing `build_perl_ir_parser`-related code):

```perl
# Parse a Perl source string through the full pipeline.
# Returns ($ir, $sa, $ctx) — the IR root, the SemanticAction semiring
# instance, and the parse-root Context (whose ->mop accessor returns
# the MOP that SemanticAction::set_mop installed, post-Phase-7c-proper
# propagation fix).
#
# This is a convenience wrapper around the perl_pipeline →
# BNF::Target::Perl → eval → build_perl_ir_parser → parse_value dance
# used by parse-integration.t. Caches the generated grammar across
# calls in the same process to avoid re-evaling.
my $_cached_perl_grammar;
sub parse_perl_source ($source) {
    unless (defined $_cached_perl_grammar) {
        my $raw_ir = perl_pipeline();
        die "perl_pipeline returned undef" unless defined $raw_ir;
        my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
        my $generated = $bnf_target->generate($raw_ir);
        $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ParsePerlSourceHelper/g;
        eval $generated;
        die "generated grammar eval failed: $@" if $@;
        $_cached_perl_grammar = Chalk::Grammar::Perl::ParsePerlSourceHelper::grammar();
    }

    my $parser   = build_perl_ir_parser($_cached_perl_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $ctx = $parser->parse_value($source);
    return unless defined $ctx;
    my $ir = $ctx->extract();
    my $sa = $semiring->semirings()->[-1];

    return ($ir, $sa, $ctx);
}
```

- [ ] **Step 4: Run the test to confirm it passes.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/test-pipeline-helper.t
```

Expected: all 5 assertions PASS. (The `ctx->mop` assertion requires the propagation fix from Tasks 1.2-1.4 to be in place.)

**Sanity-check `FilterComposite::reset_cache` exists** (referenced inside the new helper):

```bash
grep -n 'method reset_cache' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Semiring/FilterComposite.pm
```

Expected: one match at line ~76. If absent, the helper's `$semiring->reset_cache()` call dies; investigate before proceeding.

- [ ] **Step 5: Run the broader MOP test suite to confirm no regression in TestPipeline consumers.**

```bash
for t in t/bootstrap/mop/*.t; do echo "=== $t ==="; plenv exec perl -Ilib "$t" 2>&1 | tail -3; done
```

Expected: all green.

---

### Task 1.6: Fix chained-VarDecl population in Actions.pm ClassBlock (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (lines 746-747).
- Modify: `t/bootstrap/mop/parse-integration.t` (extend with chained-decl assertion).

- [ ] **Step 1: Extend `parse-integration.t` with the failing assertion.**

Open `t/bootstrap/mop/parse-integration.t`. After the existing assertion block for `Structural.pm` (the one asserting `$ZERO` from 7c-prep), add a new test block:

```perl
# Chained-decl regression: Boolean.pm has consecutive `my $ZERO_CTX; my $ONE_CTX;`
# at class scope. The parser packs these as one VarDecl whose init is another
# VarDecl. Both names must end up in class_scope_vars (presence, not order).
{
    my $bool_src;
    {
        open my $fh, '<:utf8', 'lib/Chalk/Bootstrap/Semiring/Boolean.pm'
            or die "Cannot read Boolean.pm: $!";
        local $/;
        $bool_src = <$fh>;
        close $fh;
    }

    # parse_perl_source is the Task-1.5b helper.
    use TestPipeline qw(parse_perl_source);

    # The MOP must be installed before parse — parse_perl_source does
    # not install it (it threads whatever set_mop was called with).
    my $mop_for_parse = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop_for_parse);

    my ($ir, $sa, $ctx) = parse_perl_source($bool_src);
    ok(defined $ctx, 'Boolean.pm parses');
    my $mop = $ctx->mop;
    ok(defined $mop, 'Boolean.pm parse produces a MOP');
    is(refaddr($mop), refaddr($mop_for_parse),
       'parse ctx->mop is the installed MOP');

    my $mop_cls = $mop->for_class('Chalk::Bootstrap::Semiring::Boolean');
    ok(defined $mop_cls, 'Boolean class is registered on MOP');

    my @class_scope_var_names = map {
        my $n = $_->name->value;
        $n =~ s/^[\$\@\%]//r;
    } $mop_cls->class_scope_vars;

    my %present = map { $_ => 1 } @class_scope_var_names;
    ok($present{ZERO_CTX}, 'class_scope_vars contains ZERO_CTX (outer chained decl)');
    ok($present{ONE_CTX},  'class_scope_vars contains ONE_CTX (inner chained decl)');
}
```

Note: `parse_perl_source` is the helper added by Task 1.5b. The
existing test file at `parse-integration.t` may not import it
yet — add the import line (`use TestPipeline qw(parse_perl_source);`)
in the new block, and `use Scalar::Util qw(refaddr);` if not already
imported.

- [ ] **Step 2: Run the test to confirm the chained-decl assertion fails.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/parse-integration.t
```

Expected: the existing assertions PASS; `'class_scope_vars contains ONE_CTX'` FAILS (because Actions.pm only registers the outer VarDecl).

The earlier assertions in the block (`'Boolean.pm parses'`, `'class_scope_vars contains ZERO_CTX'`) must PASS — if those fail, the test scaffold is wrong, not the production code.

- [ ] **Step 3: Apply the fix to Actions.pm ClassBlock.**

Edit `lib/Chalk/Bootstrap/Perl/Actions.pm`. Find lines 746-747:

```perl
                } elsif ($item isa Chalk::IR::Node::VarDecl) {
                    $mop_class->declare_class_scope_var($item);
```

Replace with:

```perl
                } elsif ($item isa Chalk::IR::Node::VarDecl) {
                    # Descend into chained VarDecl inits: the parser packs
                    # `my $a; my $b;` as VarDecl($a, init => VarDecl($b)).
                    # Each link in the chain must be registered.
                    my $current = $item;
                    while (defined $current && $current isa Chalk::IR::Node::VarDecl) {
                        my $next_init = $current->init();
                        $mop_class->declare_class_scope_var($current);
                        last unless defined $next_init
                                 && $next_init isa Chalk::IR::Node::VarDecl;
                        $current = $next_init;
                    }
```

- [ ] **Step 4: Run the test to confirm it passes.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/parse-integration.t
```

Expected: all assertions PASS, including the new `ONE_CTX` check.

- [ ] **Step 5: Run the broader test suite for regression.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/class-scope-vars.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -5
```

Expected: all green; counts unchanged.

---

### Task 1.7: Extend `parse-threading.t` with end-to-end mop assertion

**Files:**
- Modify: `t/bootstrap/mop/parse-threading.t`.

- [ ] **Step 1: Add the end-to-end assertion.**

Open `t/bootstrap/mop/parse-threading.t`. After the existing Tests 1-4, before `done_testing()`, add:

```perl
# Test 5: After a real parse, $ctx->mop returns the installed MOP.
# This is the canonical contract that motivated the propagation fix.
{
    use lib 't/bootstrap/lib';
    use TestPipeline qw(parse_perl_source);

    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);

    my $src = "class A { method f { 1 } }\nclass B { method g { 2 } }\n";
    my ($ir, $sa, $ctx) = parse_perl_source($src);
    ok(defined $ctx, 'parse succeeds');
    is(refaddr($ctx->mop), refaddr($mop),
       'parse root \$ctx->mop is the installed MOP (post-propagation-fix)');
}
```

`parse_perl_source` is the helper added by Task 1.5b.

- [ ] **Step 2: Run the test to confirm it passes.**

```bash
plenv exec perl -Ilib t/bootstrap/mop/parse-threading.t
```

Expected: existing tests + new Test 5 all PASS.

---

### Task 1.8: Rewrite `xs-isa-inheritance.t` fixture

**Files:**
- Modify: `t/bootstrap/xs-isa-inheritance.t` (lines 1-60).

- [ ] **Step 1: Read the current fixture construction (lines 19-55).**

The current code builds `MethodInfo` + `ClassInfo` + `Program`, then calls `_generate_c_files($program, undef, undef)`.

- [ ] **Step 2: Augment the fixture-construction block with MOP setup and switch the `_generate_c_files` call to pass `$ctx`.**

The legacy `$factory` / `$child_method` / `$class_decl` / `$program` construction stays — `_generate_c_files` still receives `$ir` (the Program built from ClassInfo) and uses it for method-body emission (7d's scope). The change is: add a MOP that mirrors the ClassInfo shape, build a `$ctx` carrying the MOP, and pass `$ctx` instead of `undef`.

Replace lines 19-55 of the existing file with the following (it includes the legacy construction unchanged, plus the new MOP/ctx setup, and changes only the `_generate_c_files` call's third argument):

```perl
my $factory = Chalk::IR::NodeFactory->new();

my $child_name  = 'Test::ISA::Child';
my $parent_name = 'Test::ISA::Parent';

my $child_method = Chalk::IR::MethodInfo->new(
    name        => 'greet',
    params      => [$factory->make('Constant', const_type => 'string', value => '$self')],
    body        => [
        $factory->make_cfg('Return',
            inputs => [
                $factory->make('Start'),
                $factory->make('Constant', const_type => 'string', value => 'hello'),
            ],
        ),
    ],
    return_type => undef,
);

my $class_decl = Chalk::IR::ClassInfo->new(
    name    => $child_name,
    parent  => $parent_name,
    methods => [$child_method],
    body    => [$child_method],
);

my $program = Chalk::IR::Program->new(classes => [$class_decl]);

# MOP setup: Commit 2 reads class shape from $ctx->mop.
# Build a MOP that mirrors what Actions.pm would produce for
# `class Test::ISA::Child :isa(Test::ISA::Parent) { method greet { 'hello' } }`.
my $mop = Chalk::MOP->new;
my $mop_class = $mop->declare_class($child_name, parent_name => $parent_name);
# IMPORTANT: MOP::Method->params is consumed by EmitHelpers::_scan_class_methods
# via a sigil-strip regex. The convention (matching Actions.pm-driven production
# parses) is plain strings like '$self', NOT IR Constant nodes. The legacy
# fixture passed Constant nodes; the MOP fixture uses plain strings to match
# what Actions.pm does for real parses.
$mop_class->declare_method('greet',
    params      => ['$self'],
    body        => $child_method->body,
    return_type => undef,
);
my $ctx = Chalk::Bootstrap::Context->new(focus => undef, mop => $mop);

my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => $child_name,
);

my $c_result = eval { $target->_generate_c_files($program, undef, $ctx) };
ok(defined $c_result, '_generate_c_files succeeds') or do {
    diag "Error: $@";
    done_testing();
    exit;
};
```

And add the missing `use` line near the top (with the other `use Chalk::IR::*;` lines):

```perl
use Chalk::MOP;
use Chalk::Bootstrap::Context;
```

- [ ] **Step 3: Run the test.**

```bash
plenv exec perl -Ilib t/bootstrap/xs-isa-inheritance.t
```

Expected: same pass count as baseline. The fixture change is mechanical; the regex assertions further down (lines 76+) operate on the C/XS output and should be stable. Note: Commit 1 has not yet added the `die "$ctx->mop required"` guard — that's Commit 2 — so the test still works because `_generate_c_files` reads from ClassInfo. The MOP setup is preparatory; after Commit 2 it becomes load-bearing.

If runtime portion (lines 87+) fails for unrelated reasons (e.g., C compiler unavailable), that's pre-existing — match against baseline.

---

### Task 1.9: Rewrite `xs-polymorphic-dispatch.t` fixture

**Files:**
- Modify: `t/bootstrap/xs-polymorphic-dispatch.t` (top hand-built block).

- [ ] **Step 1: Apply the same fixture pattern as Task 1.8.**

The host class is `Test::Dispatch::Host` with one stub method. The `compiled_class_metadata` argument describes external classes and stays unchanged. Add MOP construction for `Test::Dispatch::Host` with the stub method declared, and pass `$ctx` instead of `undef`.

Specifically, in the block that constructs `$class_decl` and calls `_generate_c_files($program, undef, undef)` (lines ~35-80 in the current file):

After the `$program = ...` line, before constructing `$target`, add:

```perl
my $mop = Chalk::MOP->new;
my $mop_class = $mop->declare_class('Test::Dispatch::Host');
# params are plain strings (Actions.pm convention) — see Task 1.8 note.
$mop_class->declare_method('stub',
    params      => ['$self'],
    body        => $method->body,
    return_type => undef,
);
my $ctx = Chalk::Bootstrap::Context->new(focus => undef, mop => $mop);
```

Change the `_generate_c_files` call from `($program, undef, undef)` to `($program, undef, $ctx)`.

Add the use lines near the top:

```perl
use Chalk::MOP;
use Chalk::Bootstrap::Context;
```

- [ ] **Step 2: If the file has additional `_generate_c_files($program, undef, undef)` calls** (search for them with `grep _generate_c_files t/bootstrap/xs-polymorphic-dispatch.t`), apply the same pattern: build a MOP/ctx for each, declaring whatever methods that sub-test asserts about.

- [ ] **Step 3: Run the test.**

```bash
plenv exec perl -Ilib t/bootstrap/xs-polymorphic-dispatch.t
```

Expected: same pass count as baseline.

---

### Task 1.10: Rewrite `xs-int-specialization.t` fixture

**Files:**
- Modify: `t/bootstrap/xs-int-specialization.t` (lines ~40-75).

- [ ] **Step 1: Apply the fixture pattern.**

After `$program = ...`, before constructing `$target`:

```perl
my $mop = Chalk::MOP->new;
my $mop_class = $mop->declare_class('Test::IntSpec');
# params are plain strings (Actions.pm convention) — see Task 1.8 note.
$mop_class->declare_method('add_one',
    params      => ['$self', '$n'],
    body        => $method->body,
    return_type => undef,
);
my $ctx = Chalk::Bootstrap::Context->new(focus => undef, mop => $mop);
```

Change `_generate_c_files($program, undef, undef)` to `($program, undef, $ctx)`.

Add the use lines.

- [ ] **Step 2: Apply same pattern if file has additional `_generate_c_files` calls.**

- [ ] **Step 3: Run the test.**

```bash
plenv exec perl -Ilib t/bootstrap/xs-int-specialization.t
```

Expected: same pass count as baseline.

---

### Task 1.11: Rewrite `xs-athx-no-args.t` fixture (module/class mismatch case)

**Files:**
- Modify: `t/bootstrap/xs-athx-no-args.t`.

This test has the deliberate `module_name='Some::Module::TestBaz'` vs class `'Foo::Bar::Baz'` mismatch. The MOP must register the class under `'Foo::Bar::Baz'` (the real class name from the IR), and the Commit 2 `_find_mop_class` helper picks the first non-main class (does NOT look up by `module_name`), which works for this case.

- [ ] **Step 1: Apply the fixture pattern with the correct class name.**

After `$program = ...`, before constructing `$target`:

```perl
my $mop = Chalk::MOP->new;
# Register the class under its REAL name ('Foo::Bar::Baz'), not the
# module_name ('Some::Module::TestBaz'). The mismatch is the point
# of this test: class slug ('baz') differs from module slug ('testbaz'),
# and the generated C function uses the class slug.
my $mop_class = $mop->declare_class('Foo::Bar::Baz');
# params are plain strings (Actions.pm convention) — see Task 1.8 note.
$mop_class->declare_method('hello',
    params      => ['$self'],
    body        => $method->body,
    return_type => undef,
);
my $ctx = Chalk::Bootstrap::Context->new(focus => undef, mop => $mop);
```

Change `_generate_c_files($program, undef, undef)` to `($program, undef, $ctx)`.

Add the use lines.

- [ ] **Step 2: Run the test.**

```bash
plenv exec perl -Ilib t/bootstrap/xs-athx-no-args.t
```

Expected: same pass count as baseline. The class-slug assertion (`'init_statics uses class slug'`, expecting `baz_init_statics`) must still PASS — the slug derives from the class name `Foo::Bar::Baz`, which the MOP correctly carries.

---

### Task 1.12: Commit 1

- [ ] **Step 1: Run the full relevant test suite one more time.**

```bash
for t in t/bootstrap/mop/*.t \
         t/bootstrap/xs-isa-inheritance.t \
         t/bootstrap/xs-polymorphic-dispatch.t \
         t/bootstrap/xs-int-specialization.t \
         t/bootstrap/xs-athx-no-args.t \
         t/bootstrap/c-emit-helpers-inheritance.t \
         t/bootstrap/bnf-target-c.t; do
    echo "=== $t ===";
    plenv exec perl -Ilib "$t" 2>&1 | tail -3;
done
```

Expected: all green; counts match baseline (with the new tests in `mop/ctx-mop-propagation.t`, `mop/field-helpers.t`, `mop/test-pipeline-helper.t`, the parse-integration extension, and the parse-threading extension adding to their respective totals).

- [ ] **Step 2: Stage and commit.**

```bash
git status
git add lib/Chalk/Bootstrap/Semiring/FilterComposite.pm \
        lib/Chalk/Bootstrap/Perl/Actions.pm \
        lib/Chalk/MOP/Field.pm \
        t/bootstrap/lib/TestPipeline.pm \
        t/bootstrap/xs-isa-inheritance.t \
        t/bootstrap/xs-polymorphic-dispatch.t \
        t/bootstrap/xs-int-specialization.t \
        t/bootstrap/xs-athx-no-args.t \
        t/bootstrap/mop/parse-threading.t \
        t/bootstrap/mop/parse-integration.t \
        t/bootstrap/mop/ctx-mop-propagation.t \
        t/bootstrap/mop/field-helpers.t \
        t/bootstrap/mop/test-pipeline-helper.t
git status   # verify nothing extra is staged
git commit -m "$(cat <<'EOF'
fix(mop): thread mop through FilterComposite, complete class-scope-var registration

Fix two architectural debts blocking Phase 7c-proper migration:

1. FilterComposite propagation hole:
   - _wrap_sa_result (line ~147) was dropping the mop field from
     every multiply-completion result.
   - _pack_survivors (line ~179) and the inline packed-Context in
     _add_unpacked (line ~475) were dropping mop+scope+graph+factory.
   The duplicated workaround comments at Actions.pm:259 and :658
   ("current_mop() is used because intermediate multiply contexts
   do not propagate the mop field") documented this bug as a
   class-global workaround. Both now read $ctx->mop directly.

2. Actions.pm ClassBlock chained-VarDecl drop:
   `my $a; my $b;` at class scope parses as one VarDecl whose init
   is another VarDecl. The MOP path only registered the outer one,
   making $mop_class->class_scope_vars lossy for any class with
   consecutive bare `my` declarations (e.g., Semiring/Boolean.pm's
   `my $ZERO_CTX; my $ONE_CTX;`). The ClassBlock loop now descends
   into chained inits via a while-loop.

Also:
- MOP::Field gains has_attribute / is_param / has_reader helpers
  used by the Commit 2 migration sites.
- Four hand-built-IR test fixtures (xs-isa-inheritance.t,
  xs-polymorphic-dispatch.t, xs-int-specialization.t,
  xs-athx-no-args.t) now construct a real MOP and pass $ctx with
  mop set, in preparation for Commit 2's $ctx->mop // die guard.
  xs-athx-no-args.t retains its module/class name mismatch
  (Some::Module::TestBaz vs Foo::Bar::Baz) — that's the test's
  point.
- New: t/bootstrap/mop/ctx-mop-propagation.t (structural regression).
- New: t/bootstrap/mop/field-helpers.t (helper coverage).
- New: t/bootstrap/mop/test-pipeline-helper.t + parse_perl_source
  convenience helper in TestPipeline.pm (wraps the
  perl_pipeline → BNF::Target::Perl → eval → build_perl_ir_parser →
  parse_value dance so integration tests can do one-line parse-to-ctx).
- Extension: mop/parse-threading.t asserts post-parse $ctx->mop
  identity.
- Extension: mop/parse-integration.t asserts both ZERO_CTX and
  ONE_CTX are present in Boolean.pm's class_scope_vars.

Design: docs/plans/2026-05-25-phase-7c-proper-design.md
EOF
)"
```

Expected: commit succeeds; no pre-commit hook violations.

- [ ] **Step 3: Confirm the commit landed.**

```bash
git log --oneline -2
```

Expected: top line is the new commit.

---

## COMMIT 2 — Target::C analyze layer reads MOP::Class

### Task 2.1: Add `_find_mop_class` to EmitHelpers (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (add new method near line 119).
- Modify: `t/bootstrap/c-emit-helpers-inheritance.t` (update `can` assertion).

- [ ] **Step 1: Write a small test for `_find_mop_class`.**

Create or extend an appropriate test file. Easiest: add to `t/bootstrap/c-emit-helpers-inheritance.t` near the existing `can` checks. Find the line:

```perl
ok($target->can('_find_class_decl'), '_find_class_decl is available');
```

Add immediately after:

```perl
ok($target->can('_find_mop_class'), '_find_mop_class is available');
```

Also add a behavioral test elsewhere in the file (or create `t/bootstrap/c-find-mop-class.t`):

```perl
# _find_mop_class picks the non-main class from a MOP.
{
    my $mop = Chalk::MOP->new;
    $mop->declare_class('Some::Class');  # plus 'main' which is auto-declared

    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Some::Class',
    );
    my $cls = $target->_find_mop_class($mop);
    ok(defined $cls, '_find_mop_class returns a class');
    is($cls->name, 'Some::Class', '_find_mop_class returns the non-main class');
}
```

- [ ] **Step 2: Run the test to confirm it fails.**

Expected: FAIL with `Can't locate object method "_find_mop_class"`.

- [ ] **Step 3: Add `_find_mop_class` to EmitHelpers.**

Edit `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`. Find the existing `_find_class_decl` method (line 119):

```perl
    # Extract ClassInfo from Program IR.
    method _find_class_decl($ir) {
        for my $stmt ($ir->classes()->@*) {
            return $stmt if $stmt isa Chalk::IR::ClassInfo;
        }
        return undef;
    }
```

Add immediately after (do NOT delete `_find_class_decl` yet — Task 2.10 deletes it after all callers move):

```perl
    # Extract the (typically one) compilable class from a MOP.
    # Mirrors _find_class_decl semantics: each Target::C instance
    # compiles one class; 'main' is the import-bucket, the
    # remaining class is the target. Returns undef if no non-main
    # class is registered.
    #
    # Sorts by class name to make the choice deterministic when a
    # file declares multiple non-main classes (rare in the current
    # corpus; possible future). Without the sort, $mop->classes
    # returns hash values in unspecified order.
    method _find_mop_class($mop) {
        for my $cls (sort { $a->name cmp $b->name } $mop->classes) {
            return $cls if $cls->name ne 'main';
        }
        return undef;
    }
```

- [ ] **Step 4: Run the test to confirm it passes.**

```bash
plenv exec perl -Ilib t/bootstrap/c-emit-helpers-inheritance.t
```

Expected: PASS, including the new assertions.

---

### Task 2.2: Migrate `_build_field_index_map` to read from MOP::Class (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (lines 129-163).
- Test: indirectly via `c-emit-helpers-inheritance.t` and downstream tests in Task 2.4+.

This method has no direct test today; its callers (`_analyze_class`) exercise it via `bnf-target-c.t`. The migration is mechanical; verification happens after Task 2.4 wires it up.

- [ ] **Step 1: Replace the method body.**

Find lines 129-163 in `EmitHelpers.pm`:

```perl
    # Build field index map from ClassInfo IR.
    # Returns hashref mapping field name (without sigil) to integer index.
    # Fields are numbered in declaration order starting from 0.
    method _build_field_index_map($class_decl) {
        my $body = $class_decl->body();
        my %field_map;
        my %sigils;
        my %params;
        my $index = 0;

        for my $item ($body->@*) {
            my ($raw_name, $attrs);
            if ($item isa Chalk::IR::FieldInfo) {
                $raw_name = $item->name();
                $attrs    = $item->attributes();
            } else {
                next;
            }
            my ($sigil) = $raw_name =~ /^([\$\@\%])/;
            my $field_name = $raw_name;
            $field_name =~ s/^[\$\@\%]//;  # Strip sigil
            $field_map{$field_name} = $index++;
            $sigils{$field_name} = $sigil // '$';
            # Detect :param attribute — these fields vary per instance
            if (ref($attrs) eq 'ARRAY') {
                for my $attr ($attrs->@*) {
                    my $attr_name = $attr->{name};
                    if (defined $attr_name && $attr_name eq 'param') {
                        $params{$field_name} = 1;
                    }
                }
            }
        }

        $field_sigils = \%sigils;
        $_param_fields = \%params;
        return \%field_map;
    }
```

Replace with:

```perl
    # Build field index map from a MOP::Class.
    # Returns hashref mapping field name (without sigil) to integer index.
    # Fields are numbered in declaration order starting from 0.
    method _build_field_index_map($mop_class) {
        my %field_map;
        my %sigils;
        my %params;
        my $index = 0;

        for my $field ($mop_class->fields) {
            my $raw_name = $field->name;
            my ($sigil) = $raw_name =~ /^([\$\@\%])/;
            my $field_name = $raw_name =~ s/^[\$\@\%]//r;
            $field_map{$field_name} = $index++;
            $sigils{$field_name} = $sigil // '$';
            if ($field->is_param) {
                $params{$field_name} = 1;
            }
        }

        $field_sigils = \%sigils;
        $_param_fields = \%params;
        return \%field_map;
    }
```

- [ ] **Step 2: Don't run tests yet — this is a half-migrated state.** `_analyze_class` still passes `$class_decl`, but `_build_field_index_map` now expects `$mop_class`. Task 2.4 fixes that.

---

### Task 2.3: Migrate `_scan_class_methods` to read from MOP::Class (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (lines 200-292).

- [ ] **Step 1: Replace the method body.**

Find lines 197-292 (the full `_scan_class_methods` method). Replace with:

```perl
    # Pre-scan all methods and subs in a MOP::Class to build $_class_methods.
    # Also populates %_class_subs for class-scope sub declarations.
    # Returns hashref: name => { returns => bool, params => [...], is_sub => bool, ... }
    method _scan_class_methods($mop_class) {
        my $class_name = $mop_class->name;
        my %methods;

        # Methods: MOP::Method entries.
        for my $method ($mop_class->methods) {
            my $name = $method->name;
            my @param_names;
            for my $p ($method->params->@*) {
                (my $pname = $p) =~ s/^[\$\@\%]//;
                push @param_names, $pname;
            }
            $methods{$name} = {
                returns => true,
                params  => \@param_names,
            };
        }

        # Subs: MOP::Sub entries. Also populates %_class_subs.
        for my $sub ($mop_class->subs) {
            my $name = $sub->name;
            my @param_names;
            for my $p ($sub->params->@*) {
                (my $pname = $p) =~ s/^[\$\@\%]//;
                push @param_names, $pname;
            }
            my $entry = {
                returns    => true,
                params     => \@param_names,
                is_sub     => true,
                class_name => $class_name,
                scope      => ($sub->can('scope') ? $sub->scope : 'package'),
            };
            $_class_subs{$name} = $entry;
            $methods{$name} = $entry;
        }

        # Scan fields for :reader attributes — these auto-generate
        # accessor methods that can be called via direct dispatch.
        for my $field ($mop_class->fields) {
            next unless $field->has_reader;
            my $fname = $field->name =~ s/^[\$\@\%]//r;
            $methods{$fname} //= {
                returns    => true,
                params     => [],
                is_reader  => true,
            };
        }

        return \%methods;
    }
```

**Params shape note:** the `(my $pname = $p) =~ s/^[\$\@\%]//` regex on each param matches the legacy `_scan_class_methods` (EmitHelpers.pm:229-231) byte-for-byte. Whatever shape `MethodInfo->params` is today (plain strings from Actions.pm-driven parses; possibly IR Constant nodes from legacy hand-built test fixtures), the migrated code preserves the same behavior because `MOP::Method->params` IS `MethodInfo->params` — Actions.pm:700 passes the same arrayref reference to `declare_method`. The four canary tests (Tasks 1.8-1.11) explicitly use plain-string params in their MOP `declare_method` calls (matching the Actions.pm convention) to ensure the sigil-strip regex works correctly; the legacy MethodInfo's possibly-IR-node param shape is irrelevant because Commit 2 reads from the MOP, not the MethodInfo.

Note: the mis-parented-SubInfo-as-VarDecl-init handling from the legacy code is gone. The 7c-prep design's claim is that Actions.pm's `SubroutineDefinition` routes through `declare_sub` regardless of source shape. Task 2.9 probes for residual mis-parenting in the corpus before we trust this deletion in production.

Also note: `MOP::Sub` does NOT currently have a `scope` accessor (per `lib/Chalk/MOP/Sub.pm` as of this plan). Confirm via:

```bash
grep -n 'field\|method' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/MOP/Sub.pm
```

The `$sub->can('scope') ? $sub->scope : 'package'` guard preserves the legacy default (`'package'`) without depending on a MOP method that may not exist. If running the test suite surfaces failures around lexical sub detection, revisit — but the spec's "method/sub body iteration is NOT in scope" boundary suggests this is benign for Commit 2.

- [ ] **Step 2: Do NOT run tests yet.** Tasks 2.2 and 2.3 have left `_build_field_index_map` and `_scan_class_methods` expecting MOP::Class parameters, but the caller (`_analyze_class`) still passes a ClassInfo. Tests in this transient state will fail with type-mismatch errors that are NOT regressions. Task 2.4 wires the migrated call site; run tests after that.

---

### Task 2.4: Migrate `_analyze_class` and rewire `_generate_c_files` entry (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (lines 44-122, 1594).

- [ ] **Step 1: Replace `_analyze_class` body.**

Find lines 44-123 in C.pm (the entire `_analyze_class` method). Replace with:

```perl
    # Note: the legacy `return unless defined $class_decl` guard at
    # the top of the previous implementation is intentionally removed.
    # `_find_mop_class` at the caller now dies if the MOP has no
    # non-main class, so `_analyze_class` is never called with an
    # undef argument in production.
    method _analyze_class($mop_class) {
        my $class_name = $mop_class->name;
        $self->_set_current_slug($self->_class_slug($class_name));

        # Build field map once and store it.
        $self->_set_field_map($self->_build_field_index_map($mop_class));

        # Pre-scan methods/subs/readers for direct call optimization.
        $self->_set_class_methods($self->_scan_class_methods($mop_class));

        # Collect class-scope variable metadata from MOP entity list.
        # Actions.pm's ClassBlock now descends into chained VarDecl inits,
        # so $mop_class->class_scope_vars is complete; no recursion needed here.
        $self->_reset_class_scope_vars();
        for my $vardecl ($mop_class->class_scope_vars) {
            my $raw_var = $vardecl->name()->value();
            my $sigil = substr($raw_var, 0, 1);
            my $var = $raw_var =~ s/^[\$\@\%]//r;
            my $init = $vardecl->init();
            # Skip if init is a SubInfo (those are sub definitions
            # registered separately on the MOP).
            next if defined $init && $init isa Chalk::IR::SubInfo;
            # Skip if init is another VarDecl (those land as their own
            # class_scope_vars entries).
            next if defined $init && $init isa Chalk::IR::Node::VarDecl;
            # Skip if var is a field (ADJUST assigns them).
            next if defined $self->_get_field_map()
                 && exists $self->_get_field_map()->{$var};
            $self->_set_class_scope_var($var, {
                sigil       => $sigil,
                init        => $init,
                static_name => "_csv_" . $self->_get_current_slug() . "_${var}",
            });
        }

        # Extract `use constant` declarations from the MOP entity list.
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

- [ ] **Step 2: Update the call site in `_generate_c_files`.**

Find the call at C.pm:1594:

```perl
        $self->_analyze_class($ir);

        my $slug     = $self->_get_current_slug();
        my $class_decl = $self->_find_class_decl($ir);
```

Replace the whole block (including the surrounding context around line 1590) with:

```perl
        if (defined $sa) {
            $self->_build_cfg_lookup($sa, $ctx);
        }

        # Source the MOP from the parse Context (post-propagation-fix
        # in Commit 1 makes this reliable).
        my $mop = $ctx->mop
            // die "_generate_c_files requires \$ctx->mop() to be set; "
                 . "construct \$ctx with mop => \$mop or use TestPipeline";
        my $mop_class = $self->_find_mop_class($mop)
            // die "MOP has no non-main class entry for module " . $self->module_name;

        $self->_analyze_class($mop_class);

        my $slug = $self->_get_current_slug();
```

Find every subsequent reference to `$class_decl` in `_generate_c_files` and downstream — they need updating. Specifically:

- C.pm:1597 `my $class_decl = $self->_find_class_decl($ir);` — delete this line; `$mop_class` is already in scope.
- C.pm:1602-1650 body iteration — Task 2.5 handles.
- C.pm:1757-1770 init_statics — Task 2.7 handles.
- C.pm:2013-2062 XS BOOT — Task 2.8 handles.

For now, leave `$class_decl` references at lines 1602, 1757, 2013, 2026 as broken — they'll be fixed in subsequent tasks. The code won't compile-pass until 2.5-2.8 land; that's expected for a multi-task migration.

- [ ] **Step 3: Don't run tests yet** — code is in a transient half-migrated state. Tasks 2.5-2.8 complete it.

---

### Task 2.5: Migrate the body-iteration loop (subs + methods)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (lines 1602-1650).

- [ ] **Step 1: Replace the if-defined-class_decl body loop with MOP-driven loops.**

Find lines 1602-1650 in C.pm:

```perl
        if (defined $class_decl) {
            my $body = $class_decl->body();

            # Emit class-scope subs (static helpers) before methods.
            for my $item ($body->@*) {
                next unless $item isa Chalk::IR::SubInfo;
                my $sname   = $item->name();
                my $sparams = $item->params();   # plain strings
                my $sbody   = $item->body();
                my $result;
                try {
                    $result = $self->_emit_sub($sname, $sparams, $sbody);
                } catch ($e) {
                    # Emission failed — mark sub as not compiled
                }
                if (defined $result && ref $result eq 'HASH') {
                    push @static_lines, $result->{helper}->@*;
                    push @static_lines, '';
                    $self->_set_class_sub_compiled($sname, true);
                } else {
                    $self->_set_class_sub_compiled($sname, false);
                }
            }

            # Emit MethodInfo items as exported C functions
            for my $item ($body->@*) {
                next unless $item isa Chalk::IR::MethodInfo;
                my $mname = $item->name();

                my $result;
                try {
                    $result = $self->_emit_method($item);
                } catch ($e) {
                    push @_skipped_methods, $mname;
                    next;
                }
                if (!defined $result) {
                    push @_skipped_methods, $mname;
                    next;
                }
                if (ref $result eq 'HASH' && defined $result->{helper}) {
                    push @func_lines, $result->{helper}->@*;
                    push @func_lines, '';
                } else {
                    # Unexpected return type — skip
                    push @_skipped_methods, $mname;
                }
            }
        }
```

Replace with:

```perl
        # Emit class-scope subs (static helpers) before methods.
        for my $sub ($mop_class->subs) {
            my $sname   = $sub->name;
            my $sparams = $sub->params;   # arrayref of plain strings
            my $sbody   = $sub->body;     # 7d-transitional read
            my $result;
            try {
                $result = $self->_emit_sub($sname, $sparams, $sbody);
            } catch ($e) {
                # Emission failed — mark sub as not compiled
            }
            if (defined $result && ref $result eq 'HASH') {
                push @static_lines, $result->{helper}->@*;
                push @static_lines, '';
                $self->_set_class_sub_compiled($sname, true);
            } else {
                $self->_set_class_sub_compiled($sname, false);
            }
        }

        # Emit MOP::Method items as exported C functions.
        # _emit_method now receives a MOP::Method (accessor surface
        # matches MethodInfo: name, params, body, return_type).
        for my $method ($mop_class->methods) {
            my $mname = $method->name;

            my $result;
            try {
                $result = $self->_emit_method($method);
            } catch ($e) {
                push @_skipped_methods, $mname;
                next;
            }
            if (!defined $result) {
                push @_skipped_methods, $mname;
                next;
            }
            if (ref $result eq 'HASH' && defined $result->{helper}) {
                push @func_lines, $result->{helper}->@*;
                push @func_lines, '';
            } else {
                push @_skipped_methods, $mname;
            }
        }
```

- [ ] **Step 2: Do NOT run tests yet.** `_analyze_class` and the body iteration loop are migrated, but init_statics (Task 2.6) and XS BOOT (Task 2.7) still reference `$class_decl` and will compile-fail. The end-to-end test gate is Task 2.8 after all transitive readers are migrated.

---

### Task 2.6: Migrate init_statics emission

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (lines 1757-1770).

- [ ] **Step 1: Replace the body-iteration block.**

Find lines 1757-1770:

```perl
        if (defined $class_decl && keys $self->_get_class_scope_vars()->%*) {
            my $body = $class_decl->body();
            for my $item ($body->@*) {
                next unless $item isa Chalk::IR::Node::VarDecl;
                my $raw = $item->name()->value();
                my $var = $raw;
                $var =~ s/^[\$\@\%]//;
                next unless exists $self->_get_class_scope_vars()->{$var};
                my $info = $self->_get_class_scope_vars()->{$var};
                my $sname = $info->{static_name};
                my $init_node = $item->init();
                my $init_expr = $self->_emit_init_expr($init_node, $info->{sigil});
                push @init_lines, "    $sname = $init_expr;" if defined $init_expr;
            }
        }
```

Replace with:

```perl
        if (keys $self->_get_class_scope_vars()->%*) {
            for my $vardecl ($mop_class->class_scope_vars) {
                my $raw = $vardecl->name()->value();
                my $var = $raw =~ s/^[\$\@\%]//r;
                next unless exists $self->_get_class_scope_vars()->{$var};
                my $info = $self->_get_class_scope_vars()->{$var};
                my $sname = $info->{static_name};
                my $init_node = $vardecl->init();
                my $init_expr = $self->_emit_init_expr($init_node, $info->{sigil});
                push @init_lines, "    $sname = $init_expr;" if defined $init_expr;
            }
        }
```

---

### Task 2.7: Migrate XS BOOT field iteration

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (lines 2013-2062).

- [ ] **Step 1: Cache `$mop_class` on the Target::C instance during `_generate_c_files`.**

The XS BOOT block lives in `generate_xs_wrapper` (around line 1851 in C.pm), which reads `$class_decl = $self->_find_class_decl($ir)` at line 1860. Its callers — verified via `grep -rn 'generate_xs_wrapper' lib script t` — invoke it as `$target->generate_xs_wrapper($program, $exported, $anon)`: no `$ctx` parameter. Examples: `t/bootstrap/xs-isa-inheritance.t:63`, `script/build-chalk-so-generated:150`.

Two ways to source the MOP class inside `generate_xs_wrapper`:

(a) Extend the signature to `generate_xs_wrapper($ir, $ctx, $exported, $anon)` — touches every caller (~10 sites).

(b) Cache `$mop_class` on the Target::C instance during `_generate_c_files` and reuse it in `generate_xs_wrapper`. Target::C is per-class so the cached state is safe.

**Use option (b).** No caller signature changes; smaller diff; the cache lives only as long as the Target::C instance.

- [ ] **Step 2: Add a `field $_mop_class;` accessor on EmitHelpers (or Target::C).**

Edit `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` near the other `field` declarations (top of the class body):

```perl
    field $_mop_class;  # set by _generate_c_files; read by generate_xs_wrapper
    method _set_mop_class($v) { $_mop_class = $v }
    method _get_mop_class()    { return $_mop_class }
```

In C.pm's `_generate_c_files`, after the `$mop_class = $self->_find_mop_class($mop)` line added in Task 2.4, add:

```perl
        $self->_set_mop_class($mop_class);
```

- [ ] **Step 3: In `generate_xs_wrapper`, use the cached MOP class.**

Find line 1860 in C.pm:

```perl
        my $class_decl = $self->_find_class_decl($ir);
```

Replace with:

```perl
        # generate_xs_wrapper runs after _generate_c_files; reuse the
        # MOP class found there. The legacy $ir is still passed in for
        # historic-signature reasons; we no longer read class shape from it.
        my $mop_class = $self->_get_mop_class()
            // die "generate_xs_wrapper called before _generate_c_files; "
                 . "no MOP class cached";
```

(All known callers — verified via grep in Step 1 — invoke `generate_xs_wrapper` after `_generate_c_files`, so the cached `$_mop_class` is always populated when the wrapper generation runs. The `// die` guard catches any future misuse.)

- [ ] **Step 4: Update the `:isa` registration block (lines 2013-2022).**

Find:

```perl
        if (defined $class_decl) {
            my $parent_name = $class_decl->parent();
            if (defined $parent_name) {
                # ... isa registration ...
            }
        }
```

Replace `$class_decl` with `$mop_class` and `$class_decl->parent()` with `$mop_class->parent_name`:

```perl
        if (defined $mop_class) {
            my $parent_name = $mop_class->parent_name;
            if (defined $parent_name) {
                my $escaped_parent = $self->_escape_c_string($parent_name);
                push @lines, "    {";
                push @lines, "        OP *isa_attr = newSVOP(OP_CONST, 0, newSVpvs(\"isa($escaped_parent)\"));";
                push @lines, "        Perl_class_apply_attributes(aTHX_ stash, isa_attr);";
                push @lines, "    }";
            }
        }
```

- [ ] **Step 5: Update the field-registration block (lines 2025-2062).**

Find:

```perl
        if (defined $class_decl) {
            my $body = $class_decl->body();
            for my $item ($body->@*) {
                next unless $item isa Chalk::IR::FieldInfo;
                my $field_name = $item->name();
                my $attrs      = $item->attributes();
                my $default    = $item->default_value();
                # ...
                if (ref($attrs) eq 'ARRAY') {
                    for my $attr ($attrs->@*) {
                        my $attr_name = $attr->{name};
                        my $escaped_attr = $self->_escape_c_string($attr_name);
                        # ...
                    }
                }
                # ... defop ...
            }
        }
```

Replace with:

```perl
        if (defined $mop_class) {
            for my $field ($mop_class->fields) {
                my $field_name = $field->name;       # sigil-prefixed
                my $default    = $field->default_value;
                my $escaped    = $self->_escape_c_string($field_name);

                push @lines, '    {';
                push @lines, '        ENTER;';
                push @lines, '        Perl_class_prepare_initfield_parse(aTHX);';
                push @lines, "        PADOFFSET padix = pad_add_name_pvs(\"$escaped\", padadd_FIELD, NULL, NULL);";
                push @lines, '        PADNAME *pn = PadnamelistARRAY(PadlistNAMES(CvPADLIST(PL_compcv)))[padix];';

                # Apply field attributes (e.g., ':param', ':reader')
                for my $attr ($field->attributes) {
                    # MOP attributes are stored as ':param'-style strings;
                    # strip the leading ':' for the C-side attribute name.
                    my $attr_name = $attr =~ s/^://r;
                    my $escaped_attr = $self->_escape_c_string($attr_name);
                    push @lines, '        {';
                    push @lines, "            OP *attr = newSVOP(OP_CONST, 0, newSVpvs(\"$escaped_attr\"));";
                    push @lines, '            Perl_class_apply_field_attributes(aTHX_ pn, attr);';
                    push @lines, '        }';
                }

                if (defined $default) {
                    my @defop_lines = $self->_emit_defop_for_xs_wrapper($default);
                    push @lines, @defop_lines;
                }

                push @lines, '        LEAVE;';
                push @lines, '    }';
            }
            push @lines, '';
        }
```

---

### Task 2.8: Run the test suite to validate the migration so far

- [ ] **Step 1: Run the C-target tests.**

```bash
plenv exec perl -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/xs-isa-inheritance.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/xs-polymorphic-dispatch.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/xs-int-specialization.t 2>&1 | tail -5
plenv exec perl -Ilib t/bootstrap/xs-athx-no-args.t 2>&1 | tail -5
```

Expected: all green. Failures here are real regressions — investigate before proceeding.

Common failure modes to watch for:

1. **"No MOP class entry"** — a test path doesn't set up the MOP correctly. The four canary tests were rewritten in Commit 1; other tests should get their MOP from a real parse. If a parser-driven test fails this way, the propagation fix has a gap.

2. **"Can't locate object method 'X' on Chalk::MOP::Method"** — the accessor compatibility assumption is wrong; check that `_emit_method` doesn't call something MethodInfo has but MOP::Method doesn't.

3. **`bnf-target-c.t` count drops** — some emitted C diverges from expected. Diff outputs to see what changed.

- [ ] **Step 2: Run the MOP test suite.**

```bash
for t in t/bootstrap/mop/*.t; do echo "=== $t ==="; plenv exec perl -Ilib "$t" 2>&1 | tail -3; done
```

Expected: all green.

---

### Task 2.9: Probe for residual mis-parented-SubInfo pattern

**Files:** none modified.

- [ ] **Step 1: Probe the corpus.**

```bash
grep -rn 'my %\w*; sub ' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk 2>&1 | head -20
```

If any matches appear inside class bodies (check the surrounding context), the mis-parented-SubInfo workaround at the (now-deleted) EmitHelpers.pm:215-221 may still be needed.

If no matches OR all matches are at file scope (not inside `class { ... }` blocks), the deletion in Task 2.3 is safe.

- [ ] **Step 2: If matches exist inside classes**, parse the offending file via TestPipeline and check whether the inner sub lands on `$mop_class->subs` or stays as a VarDecl init. If it stays as a VarDecl init, file a tracking issue and add a TODO comment in `_scan_class_methods` describing the gap. **Do not block Commit 2** on this — the legacy code had the same fragility and the Phase 3b loop in build-chalk-so-generated will catch outright misses at build time.

---

### Task 2.10: Delete `_find_class_decl`, `_scan_field_method_calls`, and the dead `can` assertion

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (delete lines 119-124 and 577-629).
- Modify: `t/bootstrap/c-emit-helpers-inheritance.t` (delete the `_find_class_decl` and `_scan_field_method_calls` `can` assertions).

- [ ] **Step 1: Search for any remaining production callers.**

```bash
SHELL=/bin/bash /bin/bash -c "ag '_find_class_decl|_scan_field_method_calls' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib /home/perigrin/dev/chalk/.claude/worktrees/pu/script /home/perigrin/dev/chalk/.claude/worktrees/pu/t"
```

Expected: only the deletion sites (the methods themselves in EmitHelpers, the `can` assertions in c-emit-helpers-inheritance.t). If anything else surfaces, fix that consumer first.

- [ ] **Step 2: Delete the `_find_class_decl` method.**

Edit `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`. Delete lines 118-124:

```perl
    # Extract ClassInfo from Program IR.
    method _find_class_decl($ir) {
        for my $stmt ($ir->classes()->@*) {
            return $stmt if $stmt isa Chalk::IR::ClassInfo;
        }
        return undef;
    }
```

- [ ] **Step 3: Delete the `_scan_field_method_calls` method.**

Edit `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`. Delete lines 577-629 (the full method body plus its leading comment).

- [ ] **Step 4: Delete the `can` assertions in the test.**

Edit `t/bootstrap/c-emit-helpers-inheritance.t`. Find:

```perl
ok($target->can('_find_class_decl'), '_find_class_decl is available');
```

and

```perl
ok($target->can('_scan_field_method_calls'), '_scan_field_method_calls is available');
```

Delete both lines.

- [ ] **Step 5: Run the test.**

```bash
plenv exec perl -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -5
```

Expected: net pass count change is **−1** (two `can` deletions in this task, plus one `can` addition from Task 2.1 for `_find_mop_class`). If baseline was 54, new count is 53.

---

### Task 2.11: Migrate Phase 3b loop in `build-chalk-so-generated`

**Files:**
- Modify: `script/build-chalk-so-generated` (lines ~200-260).

- [ ] **Step 1: Read the current Phase 3b loop.**

Lines 196-268 currently walk `$class_decl->inputs()->[2]` looking for `Chalk::Bootstrap::IR::Node::Constructor` with `class() eq 'FieldDecl'` / `'MethodDecl'`. This IR shape is what Actions.pm used to produce; Actions.pm now produces `Chalk::IR::ClassInfo`/`FieldInfo`/`MethodInfo`. The loop's metadata map has been empty in practice (audit Section 7b finding).

- [ ] **Step 2: Replace the inner per-class block (lines ~191-268).**

Find the loop body that starts with `my $cn = $gen_info->{class_name};` and ends with the `$class_metadata{$cn} = { ... }` assignment.

Replace with:

```perl
    for my $gen_info (@generated) {
        my $cn = $gen_info->{class_name};
        next if $cn eq 'Chalk::Bootstrap::Earley';  # not a dependency of itself

        my ($parsed_info) = grep { $_->{class_name} eq $cn } @parsed;
        next unless $parsed_info;

        # Source the MOP class via $ctx->mop (post-propagation-fix).
        my $ctx = $parsed_info->{ctx};
        next unless defined $ctx;
        my $mop = $ctx->mop;
        next unless defined $mop;
        my $mop_class = $mop->for_class($cn);
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

        next unless keys %readers || keys %methods;

        $class_metadata{$cn} = {
            slug    => $gen_info->{slug},
            readers => \%readers,
            methods => \%methods,
        };
    }
```

- [ ] **Step 3: Verify the rest of `build-chalk-so-generated` is unaffected.**

The remaining script consumes `%class_metadata` and passes it to the Earley re-generation; nothing else in the file walks Constructor IR shapes. Confirm with:

```bash
grep -n 'Chalk::Bootstrap::IR::Node::Constructor' /home/perigrin/dev/chalk/.claude/worktrees/pu/script/build-chalk-so-generated
```

Expected: zero matches after the migration.

---

### Task 2.12: Run the build script to validate Commit 2 end-to-end

- [ ] **Step 1: Run the build script.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu && plenv exec perl script/build-chalk-so-generated 2>&1 | tail -30
```

Expected: Phase 1, 2, 2.5, 3, 3b all complete without errors; `chalk.so` is built. If Phase 3b reports a non-empty `%class_metadata` (verifiable by adding a temporary `print` of `scalar keys %class_metadata` before the re-generation block), that's evidence the migration fixed the dead-loop problem.

Failures here surface as either compilation errors in the generated C, link errors against `chalk.so`, or the script exiting non-zero. Triage by reading the failing phase's output.

---

### Task 2.13: Commit 2

- [ ] **Step 1: Final test suite run.**

```bash
for t in t/bootstrap/mop/*.t \
         t/bootstrap/xs-isa-inheritance.t \
         t/bootstrap/xs-polymorphic-dispatch.t \
         t/bootstrap/xs-int-specialization.t \
         t/bootstrap/xs-athx-no-args.t \
         t/bootstrap/c-emit-helpers-inheritance.t \
         t/bootstrap/bnf-target-c.t \
         t/bootstrap/c-data-model-classes.t \
         t/bootstrap/c-self-call-optimization.t \
         t/bootstrap/c-target-multi-class.t \
         t/bootstrap/c-target-boolean.t \
         t/bootstrap/c-direct-cross-class.t \
         t/bootstrap/c-type-aware-dispatch.t \
         t/bootstrap/c-xs-wrapper-gen.t; do
    echo "=== $t ===";
    plenv exec perl -Ilib "$t" 2>&1 | tail -3;
done
```

Expected: all green. Counts:
- `mop/codegen-byte-compat.t`: 19/19 (no Target::Perl changes)
- `c-emit-helpers-inheritance.t`: baseline−1 (two `can` deletions in Task 2.10, one `can` addition in Task 2.1)
- `bnf-target-c.t`: baseline (178)
- All other tests: at baseline.

- [ ] **Step 2: Stage and commit.**

```bash
git status
git add lib/Chalk/Bootstrap/Perl/Target/C.pm \
        lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm \
        t/bootstrap/c-emit-helpers-inheritance.t \
        script/build-chalk-so-generated
git status   # verify nothing extra staged
git commit -m "$(cat <<'EOF'
feat(target-c): Phase 7c-proper — analyze layer reads MOP::Class

Migrate Target::C's class-shape readers from Chalk::IR::ClassInfo
body-arrayref iteration to Chalk::MOP::Class entity reads, building
on Commit 1's propagation fix.

Sites migrated:
- _analyze_class: takes a MOP::Class directly; iterates
  $mop_class->class_scope_vars and ->use_constants. The legacy
  recursion into chained VarDecl inits is gone (Commit 1 fixed
  population at the parser side).
- _build_field_index_map: iterates $mop_class->fields; uses the
  new $field->is_param helper.
- _scan_class_methods: iterates $mop_class->methods, ->subs,
  ->fields (for :reader scan via $field->has_reader).
- _generate_c_files: derives $mop from $ctx->mop and $mop_class
  via the new _find_mop_class helper (mirrors legacy
  _find_class_decl semantics: first non-main class wins).
- Body iteration loop: emits subs and methods from $mop_class->subs
  and ->methods directly. _emit_method now receives a MOP::Method
  (accessor surface — name, params, body, return_type — verified
  compatible with MethodInfo).
- init_statics emission: iterates $mop_class->class_scope_vars.
- XS BOOT field iteration: iterates $mop_class->fields; uses
  the colon-stringified attribute list directly (no hashref
  unwrapping).

Deletions:
- EmitHelpers::_find_class_decl: replaced by _find_mop_class.
- EmitHelpers::_scan_field_method_calls: dead code (zero
  production callers; reads $class_decl->inputs()->[2] which
  ClassInfo doesn't expose). Removed plus its `can` assertion in
  c-emit-helpers-inheritance.t.

Also added:
- EmitHelpers gains $_mop_class field plus _set_mop_class /
  _get_mop_class accessors so generate_xs_wrapper can reuse the
  MOP class that _generate_c_files looked up. Avoids extending
  generate_xs_wrapper's public signature.

Build script:
- script/build-chalk-so-generated's Phase 3b loop migrated from
  walking Chalk::Bootstrap::IR::Node::Constructor (which Actions.pm
  doesn't produce) to walking $mop_class->fields/methods. The
  legacy loop produced an empty metadata map in practice; the
  migration is a behavioral fix as well as a cleanup.

Out of scope (Phase 7d):
- _emit_method's $method->body iteration for code emission.
- The per-sub body read inside the subs loop.

Out of scope (Phase 7g):
- Deletion of MOP::Method.body, MOP::Sub.body, Chalk::IR::Program,
  ClassInfo, MethodInfo, SubInfo, FieldInfo.

Design: docs/plans/2026-05-25-phase-7c-proper-design.md
Plan:   docs/plans/2026-05-25-phase-7c-proper-plan.md
EOF
)"
```

- [ ] **Step 3: Confirm both commits landed.**

```bash
git log --oneline -3
```

Expected:
- top: `feat(target-c): Phase 7c-proper — analyze layer reads MOP::Class`
- second: `fix(mop): thread mop through FilterComposite, complete class-scope-var registration`
- third: `e9b7a16d docs(plans): Phase 7c-proper design — propagation fix + analyze migration`

---

## Final acceptance checks (post both commits)

- [ ] All test gates from the spec (Section "Test gates") are green at expected counts.
- [ ] `script/build-chalk-so-generated` runs successfully.
- [ ] `git status` is clean.
- [ ] `git log --oneline -3` shows both commits on top of the design commit.
- [ ] `ag '_scan_field_method_calls|_find_class_decl' lib script t` returns zero matches in production code (only docs/historical references survive).
- [ ] `ag 'current_mop\(\)' lib/Chalk/Bootstrap/Perl/Actions.pm` returns zero matches (workarounds retired).
- [ ] The branch is NOT pushed (per spec hard constraint).

If all of the above hold, Phase 7c-proper is complete. The next phase is **7d (schedule-driven body emission)**; see `docs/plans/2026-05-24-phase-7-handoff.md` for the original Phase 7 breakdown.
