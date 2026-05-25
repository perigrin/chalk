# Phase 7c-prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand `Chalk::MOP::Class` with a `$scope` lexical-environment field plus two typed entity lists (`@class_scope_vars`, `@use_constants`) and `declare_*` methods, and update Actions.pm's ClassBlock action to populate them. Unblocks Target::C migration in 7c-proper.

**Architecture:** Strict TDD: each new MOP API gains a unit test before its implementation; the Actions.pm population gains a parse-integration test before the wiring change. One commit. No Target::C surface touched.

**Tech Stack:** Perl 5.42.0 (`feature class`, postfix deref, `true`/`false`), `Chalk::Bootstrap::Scope` for the lex-env, existing `Chalk::IR::Node::VarDecl` and `Chalk::IR::UseInfo` for the IR shapes. Test runner: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/...`.

**Predecessor spec:** `docs/plans/2026-05-25-phase-7c-prep-design.md` (read before starting). The spec has been through three iterations of review; the design is locked.

**Required skills for every code step:**
- `superpowers:writing-perl-5.42.0`
- `superpowers:test-driven-development`

---

## File Structure

**New files:**
- `t/bootstrap/mop/class-scope-vars.t` — MOP unit tests for `declare_class_scope_var`
- `t/bootstrap/mop/use-constants.t` — MOP unit tests for `declare_use_constant`

**Modified files:**
- `lib/Chalk/MOP/Class.pm` — add `$scope` field, two arrayref fields, two `declare_*` methods, two accessors
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — extend ClassBlock body-loop with VarDecl branch + split `use constant` out of `declare_import`
- `t/bootstrap/mop/parse-integration.t` — extend with class-scope-var + use-constant assertions on inline source

**No file is over-decomposed.** MOP::Class.pm currently has 128 lines and gains ~25 more; Actions.pm's ClassBlock action grows by ~20 lines. No file split is needed.

---

## Pre-flight checks

- [ ] **Step 0a: Confirm branch + working tree clean**

Run: `git status && git log --oneline -1`
Expected: `working tree clean`; HEAD at `1fe8441c` ("docs(plans): Phase 7c-prep design — apply iteration-3 review recs") or a later docs-only commit. If not, stop and ask before continuing.

- [ ] **Step 0b: Confirm test baseline**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -3`
Expected: `1..19` with no failures.

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-no-backchannel.t 2>&1 | tail -3`
Expected: `1..2` with no failures.

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -5`
Expected: pass (currently 21 tests).

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/hand-constructed.t 2>&1 | tail -3`
Expected: pass.

If any of these fails before changes, stop and ask.

---

## Task 1: `declare_class_scope_var` (MOP unit test + implementation)

**Files:**
- Create: `t/bootstrap/mop/class-scope-vars.t`
- Modify: `lib/Chalk/MOP/Class.pm` (add `$scope` field, `@class_scope_vars` field, `class_scope_vars()` accessor, `declare_class_scope_var()` method, and a `use Chalk::Bootstrap::Scope;` at the top)

### Step 1.1: Write the failing test

- [ ] Create `t/bootstrap/mop/class-scope-vars.t` with this exact content:

```perl
# ABOUTME: MOP unit tests for Chalk::MOP::Class.declare_class_scope_var.
# ABOUTME: Verifies class-scope `my $x = ...;` declarations are recorded and bound in $scope.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Constant;

# Helper: construct a synthetic VarDecl(name => '$VAR', init => undef).
# id/inputs are honest — Constant for the name; control/init undef
# because this is a hand-built test fixture, not a parser-derived node.
my $id_counter = 0;
sub make_vardecl ($var_name) {
    my $name_const = Chalk::IR::Node::Constant->new(
        id    => 'c_' . $id_counter++,
        inputs => [],
        const_type => 'variable',
        value      => $var_name,
    );
    return Chalk::IR::Node::VarDecl->new(
        id     => 'vd_' . $id_counter++,
        inputs => [undef, $name_const, undef],
    );
}

# Test 1: empty class has empty class_scope_vars + empty scope
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my @empty = $cls->class_scope_vars;
    is(scalar @empty, 0,
        'fresh class has zero class_scope_vars');
    ok(defined $cls->scope, 'fresh class has defined scope');
    is($cls->scope->lookup('$missing'), undef,
        'fresh scope returns undef for unknown name');
}

# Test 2: single declare records the VarDecl and binds in scope
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my $vd  = make_vardecl('$ZERO');

    my $returned = $cls->declare_class_scope_var($vd);

    is($returned, $vd, 'declare_class_scope_var returns the node passed in');

    my @list = $cls->class_scope_vars;
    is(scalar @list, 1, 'class_scope_vars has 1 entry after one declare');
    is($list[0], $vd, 'class_scope_vars entry is the same VarDecl object');

    is($cls->scope->lookup('$ZERO'), $vd,
        'scope->lookup($ZERO) returns the VarDecl');
}

# Test 3: multiple declarations preserve insertion order in the list,
# and all bindings are reachable via scope->lookup.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my $a = make_vardecl('$A');
    my $b = make_vardecl('$B');
    my $c = make_vardecl('$C');

    $cls->declare_class_scope_var($a);
    $cls->declare_class_scope_var($b);
    $cls->declare_class_scope_var($c);

    my @list = $cls->class_scope_vars;
    is(scalar @list, 3, 'class_scope_vars has 3 entries');
    is($list[0], $a, 'insertion order [0] is $A');
    is($list[1], $b, 'insertion order [1] is $B');
    is($list[2], $c, 'insertion order [2] is $C');

    is($cls->scope->lookup('$A'), $a, 'scope->lookup($A) returns $a');
    is($cls->scope->lookup('$B'), $b, 'scope->lookup($B) returns $b');
    is($cls->scope->lookup('$C'), $c, 'scope->lookup($C) returns $c');
}

# Test 4: scope is immutable copy-on-write — each declare returns a new Scope.
# (We don't expose the intermediate scope to callers, but the field itself
# must follow Scope's contract: $scope = $scope->define(...).)
# This test ensures the scope-after-3-declarations contains all 3 bindings;
# if declare_class_scope_var forgot to assign back, only the last would be
# visible.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    $cls->declare_class_scope_var(make_vardecl('$A'));
    $cls->declare_class_scope_var(make_vardecl('$B'));

    ok(defined $cls->scope->lookup('$A'),
        '$A still visible after later declare ($scope reassignment works)');
    ok(defined $cls->scope->lookup('$B'),
        '$B visible after its own declare');
}

done_testing();
```

### Step 1.2: Run the test to confirm it fails

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/class-scope-vars.t 2>&1 | tail -10`

Expected: failure with a message like `Can't locate object method "class_scope_vars" via package "Chalk::MOP::Class"` — the method doesn't exist yet.

### Step 1.3: Add the `$scope` field, `@class_scope_vars` field, accessor, and `declare_class_scope_var` method

- [ ] Open `lib/Chalk/MOP/Class.pm`.

- [ ] At the top of the file, after the existing `use Chalk::MOP::Phaser::Adjust;` line, add:

```perl
use Chalk::Bootstrap::Scope;
```

- [ ] Inside the `class Chalk::MOP::Class { ... }` block, after the existing `field @adjust_blocks;` line (currently line 22), add the new fields:

```perl
    field $scope :reader = Chalk::Bootstrap::Scope->new;
    field @class_scope_vars;
```

  - Note: `$scope` is NOT `:param`. The class always default-constructs its scope. There is no use case for callers injecting a custom Scope at construction time, and exposing one would let a caller pre-bind class-scope vars without the corresponding `@class_scope_vars` entry, breaking the dual-access-pattern invariant.

- [ ] After the existing `method adjust_blocks() { ... }` line, add the new accessor:

```perl
    method class_scope_vars() { return @class_scope_vars }
```

- [ ] After the existing `declare_adjust` method (currently ending at line 84), add the new declare method:

```perl
    method declare_class_scope_var($vardecl_node) {
        # $vardecl_node is a Chalk::IR::Node::VarDecl already merged
        # into its upstream graph by Actions.pm. We do NOT merge it
        # into a class-side graph here — no class graph exists in this
        # commit (see Phase 7c-prep design Risk #2). Record in the
        # insertion-ordered list (for codegen iteration) and bind the
        # name in $scope (for lookup-by-name semantics).
        push @class_scope_vars, $vardecl_node;
        my $name = $vardecl_node->name->value;
        $scope = $scope->define($name, $vardecl_node);
        return $vardecl_node;
    }
```

### Step 1.4: Run the test to confirm it passes

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/class-scope-vars.t 2>&1 | tail -10`

Expected: all 14 assertions pass; final line `1..14` (or similar — count is whatever `done_testing` produces).

### Step 1.5: Run the pre-existing MOP suite to confirm no regressions

Run each command, expected output: all tests pass.

- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-no-backchannel.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/hand-constructed.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -5`

If any regress, stop and diagnose before continuing.

### Step 1.6: Stage Task 1 changes (do NOT commit yet)

```bash
git add lib/Chalk/MOP/Class.pm t/bootstrap/mop/class-scope-vars.t
git status
```

Verify only those two files are staged. **Do not commit yet** — the whole prep ships as one commit per the spec.

---

## Task 2: `declare_use_constant` (MOP unit test + implementation)

**Files:**
- Create: `t/bootstrap/mop/use-constants.t`
- Modify: `lib/Chalk/MOP/Class.pm` (add `@use_constants` field, `use_constants()` accessor, `declare_use_constant()` method)

### Step 2.1: Write the failing test

- [ ] Create `t/bootstrap/mop/use-constants.t` with this exact content:

```perl
# ABOUTME: MOP unit tests for Chalk::MOP::Class.declare_use_constant.
# ABOUTME: Verifies `use constant { K => V };` decls are recorded as named/value pairs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;
use Chalk::IR::Node::Constant;

my $id_counter = 0;
sub make_const ($val) {
    return Chalk::IR::Node::Constant->new(
        id         => 'c_' . $id_counter++,
        inputs     => [],
        const_type => 'integer',
        value      => $val,
    );
}

# Test 1: empty class has empty use_constants list
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my @empty = $cls->use_constants;
    is(scalar @empty, 0, 'fresh class has zero use_constants');
}

# Test 2: single declare records the {name, value} entry
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my $val = make_const(42);

    my $returned = $cls->declare_use_constant('FOO', $val);

    is(ref $returned, 'HASH', 'declare_use_constant returns a hashref');
    is($returned->{name}, 'FOO', 'returned entry name matches input');
    is($returned->{value}, $val, 'returned entry value is the same node');

    my @list = $cls->use_constants;
    is(scalar @list, 1, 'use_constants has 1 entry after one declare');
    is($list[0]{name}, 'FOO', 'list[0] name is FOO');
    is($list[0]{value}, $val, 'list[0] value is the const node');
}

# Test 3: multiple declarations preserve insertion order
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my $v1 = make_const(1);
    my $v2 = make_const(2);
    my $v3 = make_const(3);

    $cls->declare_use_constant('A', $v1);
    $cls->declare_use_constant('B', $v2);
    $cls->declare_use_constant('C', $v3);

    my @list = $cls->use_constants;
    is(scalar @list, 3, 'use_constants has 3 entries');
    is($list[0]{name}, 'A', 'insertion order [0] is A');
    is($list[1]{name}, 'B', 'insertion order [1] is B');
    is($list[2]{name}, 'C', 'insertion order [2] is C');
}

done_testing();
```

### Step 2.2: Run the test to confirm it fails

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/use-constants.t 2>&1 | tail -10`

Expected: failure — `Can't locate object method "use_constants"`.

### Step 2.3: Add the `@use_constants` field, accessor, and method

- [ ] Open `lib/Chalk/MOP/Class.pm`.

- [ ] Inside the class block, immediately after the `field @class_scope_vars;` line you added in Task 1, add:

```perl
    field @use_constants;
```

- [ ] After the `class_scope_vars()` accessor you added in Task 1, add:

```perl
    method use_constants() { return @use_constants }
```

- [ ] After the `declare_class_scope_var` method you added in Task 1, add:

```perl
    method declare_use_constant($name, $value_node) {
        # $name is a plain string (the constant name, no sigil).
        # $value_node is a Chalk::IR::Node::Constant (or similar IR node).
        my $entry = { name => $name, value => $value_node };
        push @use_constants, $entry;
        return $entry;
    }
```

### Step 2.4: Run the test to confirm it passes

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/use-constants.t 2>&1 | tail -10`

Expected: all assertions pass.

### Step 2.5: Re-run the MOP suite

Same four commands as Step 1.5. Expected: all green; class-scope-vars.t still passes.

### Step 2.6: Stage Task 2 changes

```bash
git add lib/Chalk/MOP/Class.pm t/bootstrap/mop/use-constants.t
git status
```

Verify staging is correct.

---

## Task 3: Actions.pm — populate the new MOP entities

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (extend the ClassBlock action's body-item loop)
- Modify: `t/bootstrap/mop/parse-integration.t` (add inline-source tests for the new behavior)

This task is split into two sub-tasks: 3A populates class-scope vars; 3B splits `use constant` out of `declare_import`. Each has its own failing test first.

### Sub-task 3A: VarDecl branch in ClassBlock action

#### Step 3A.1: Write the failing integration assertion

- [ ] Open `t/bootstrap/mop/parse-integration.t`. Find the existing inner SKIP block (currently ending around line 130 with the `main class assertions` block).

- [ ] **Inside** the inner `SKIP: { skip ... unless ... }` block (i.e., after the existing assertions but before the closing `}`), add a new inline-source test. The new test parses a *separate* synthetic class with a class-scope `my` declaration. Add this code immediately after the `main class assertions` block (after `is(scalar @main_methods, 0, 'main has no methods');` and the closing brace of that inner SKIP, but before the outer SKIP's closing brace at line 130):

```perl
        # ============================================================
        # Test: class-scope `my $VAR = expr;` populates class_scope_vars
        # ============================================================
        # Parse a second source against the same singleton MOP (matches
        # the convention established by parse-toplevel-sub.t line 130:
        # current_mop() is read by semantic actions; classes accumulate
        # across parses on the same singleton). No reset needed.
        {
            my $csv_source = q{
class Sentinel {
    my $ZERO = -1;
    field $x :param;

    method get_zero() {
        return $ZERO;
    }
}
};

            my $csv_parser = build_perl_ir_parser($gen_grammar, start => 'Program');
            my $csv_result = $csv_parser->parse_value($csv_source);

            ok(defined $csv_result && !$csv_result->is_zero(),
                'class with class-scope `my` parses successfully');

            SKIP: {
                skip 'csv source did not parse', 3
                    unless defined $csv_result && !$csv_result->is_zero();

                # Reuse the $mop variable from line 64 above — the
                # singleton accumulates classes across parses, so
                # Sentinel is now alongside main and Point.
                my $sentinel = $mop->for_class('Sentinel');
                ok(defined $sentinel, 'Sentinel class is on MOP');

                SKIP: {
                    skip 'Sentinel not on MOP', 2 unless defined $sentinel;
                    my @csv = $sentinel->class_scope_vars;
                    is(scalar @csv, 1, 'Sentinel has 1 class_scope_var');

                    SKIP: {
                        skip 'no class_scope_vars on Sentinel', 1
                            unless scalar @csv >= 1;
                        is($csv[0]->name->value, '$ZERO',
                            'class_scope_var name is $ZERO');
                    }
                }
            }
        }
```

- [ ] Verify the singleton-reuse convention is what `parse-toplevel-sub.t` uses. Open `t/bootstrap/mop/parse-toplevel-sub.t` and check around line 130 — the second test reuses `Chalk::Bootstrap::Semiring::SemanticAction::current_mop()` against a fresh parser+source, asserting against accumulated classes. The new Sentinel test follows that pattern: no `set_mop`, just reuse the existing `$mop` from line 64.

This avoids the previously-considered `set_current_mop`/`set_mop` reset — neither matches the established test convention, and accumulation on the singleton is the intended semantics.

#### Step 3A.2: Run the integration test to confirm the new assertion fails

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -15`

Expected: existing assertions still pass; the new `Sentinel has 1 class_scope_var` assertion fails (got 0). If the test fails earlier (e.g., on parsing), the source string may need adjustment — try removing the method body or simplifying.

#### Step 3A.3: Add the VarDecl branch to the ClassBlock action

- [ ] Open `lib/Chalk/Bootstrap/Perl/Actions.pm`. Find the body-item dispatch loop in the ClassBlock action — currently around line 670-722. The loop has the shape:

```perl
for my $item (@body) {
    if ($item isa Chalk::IR::FieldInfo) { ... }
    elsif ($item isa Chalk::IR::MethodInfo) { ... }
    elsif ($item isa Chalk::IR::SubInfo) { ... }
    elsif ($item isa Chalk::IR::UseInfo) { ... }
    elsif (ref($item) eq 'HASH' && exists $item->{__adjust_body}) { ... }
}
```

- [ ] Before the existing `} elsif (ref($item) eq 'HASH' && exists $item->{__adjust_body})` branch, add a new branch for VarDecl:

```perl
                } elsif ($item isa Chalk::IR::Node::VarDecl) {
                    $mop_class->declare_class_scope_var($item);
```

  Position matters: this branch goes after the `UseInfo` branch (line 716-719 currently) and before the `__adjust_body` branch (currently line 720). The full updated tail of the loop should look like:

```perl
                } elsif ($item isa Chalk::IR::UseInfo) {
                    $mop_class->declare_import($item->name(),
                        args => [$item->args->@*],
                    );
                } elsif ($item isa Chalk::IR::Node::VarDecl) {
                    $mop_class->declare_class_scope_var($item);
                } elsif (ref($item) eq 'HASH' && exists $item->{__adjust_body}) {
                    $mop_class->declare_adjust();
                }
```

  Note: `Chalk::IR::Node::VarDecl` is already imported via `use Chalk::IR::Node::VarDecl;` at the top of Actions.pm (verified at line 9).

#### Step 3A.4: Run the integration test — new assertion should now pass

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -15`

Expected: all assertions pass, including the new Sentinel ones. If the original Point/main assertions regress, the new branch is firing on body items it shouldn't — recheck the elsif ordering.

#### Step 3A.5: Re-run the rest of the MOP suite

Same four commands as Step 1.5, plus:
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/class.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/method.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/field.t 2>&1 | tail -3`

Expected: all pass.

### Sub-task 3B: split `use constant` out of `declare_import`

#### Step 3B.1: Write the failing test

- [ ] Open `t/bootstrap/mop/parse-integration.t`. Inside the same outer SKIP block, immediately after the Sentinel class-scope-var test you added in 3A, add a use-constant test:

```perl
        # ============================================================
        # Test: class-scope `use constant { K => V };` populates
        # use_constants (and is NOT routed to imports)
        # ============================================================
        {
            my $uc_source = q{
class Counters {
    use constant { MIN => 0, MAX => 255 };

    method min() { return MIN; }
}
};

            my $uc_parser = build_perl_ir_parser($gen_grammar, start => 'Program');
            my $uc_result = $uc_parser->parse_value($uc_source);

            ok(defined $uc_result && !$uc_result->is_zero(),
                'class with `use constant` parses successfully');

            SKIP: {
                skip 'uc source did not parse', 4
                    unless defined $uc_result && !$uc_result->is_zero();

                # Reuse the singleton $mop from line 64; Counters
                # accumulates alongside main/Point/Sentinel.
                my $counters = $mop->for_class('Counters');
                ok(defined $counters, 'Counters class is on MOP');

                SKIP: {
                    skip 'Counters not on MOP', 3 unless defined $counters;

                    my @uc = $counters->use_constants;
                    is(scalar @uc, 2, 'Counters has 2 use_constants');

                    my %by_name = map { $_->{name} => $_ } @uc;
                    ok(exists $by_name{MIN}, 'use_constants has MIN');
                    ok(exists $by_name{MAX}, 'use_constants has MAX');

                    # Critically: use_constants does NOT also leak into
                    # imports. The pre-split code routed every UseInfo
                    # through declare_import, so this would have failed.
                    my @imps = $counters->imports;
                    my @constant_imps = grep { $_->module eq 'constant' } @imps;
                    is(scalar @constant_imps, 0,
                        '`use constant` does not appear in imports');
                }
            }
        }
```

  Counters follows the same singleton-reuse convention as Sentinel — no `set_mop`, just `$mop->for_class('Counters')`.

#### Step 3B.2: Run the test to confirm the new assertions fail

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -15`

Expected: the `Counters has 2 use_constants` assertion fails (got 0); the `use constant does not appear in imports` assertion may also fail (got 1 — the legacy `declare_import` is still firing on `use constant`).

#### Step 3B.3: Split the `use constant` route in Actions.pm

- [ ] Open `lib/Chalk/Bootstrap/Perl/Actions.pm`. Find the existing `} elsif ($item isa Chalk::IR::UseInfo)` branch (currently around line 716-719). It currently reads:

```perl
                } elsif ($item isa Chalk::IR::UseInfo) {
                    $mop_class->declare_import($item->name(),
                        args => [$item->args->@*],
                    );
```

- [ ] Replace it with a split version that handles `use constant` separately. Use the existing iteration shape from Target::C `_analyze_class` (currently `lib/Chalk/Bootstrap/Perl/Target/C.pm` lines 97-119) as a reference for walking the `HashRef` pairs:

```perl
                } elsif ($item isa Chalk::IR::UseInfo) {
                    if ($item->name eq 'constant') {
                        # `use constant { K => V, ... };` — extract
                        # constant pairs from args[0]'s HashRef and
                        # route each to declare_use_constant. Do NOT
                        # also declare_import; conflating the two
                        # forced Target::C to walk the body twice.
                        my $args = $item->args;
                        if (ref($args) eq 'ARRAY' && @$args) {
                            my $hash = $args->[0];
                            if (defined $hash
                                    && $hash isa Chalk::IR::Node::HashRef) {
                                my $pairs = $hash->inputs->[0];
                                if (ref($pairs) eq 'ARRAY') {
                                    for (my $i = 0; $i < @$pairs; $i += 2) {
                                        my $k = $pairs->[$i];
                                        my $v = $pairs->[$i + 1];
                                        next unless $k isa Chalk::IR::Node::Constant;
                                        next unless $v isa Chalk::IR::Node::Constant;
                                        $mop_class->declare_use_constant(
                                            $k->value, $v);
                                    }
                                }
                            }
                        }
                    } else {
                        $mop_class->declare_import($item->name(),
                            args => [$item->args->@*],
                        );
                    }
```

- [ ] Verify `Chalk::IR::Node::HashRef` is importable. Run: `grep -n "use Chalk::IR::Node::HashRef" lib/Chalk/Bootstrap/Perl/Actions.pm`. If the import is absent, add `use Chalk::IR::Node::HashRef;` near the top of Actions.pm (next to the other `Chalk::IR::Node::*` uses around line 9-15).

  Same for `Chalk::IR::Node::Constant`. If either is missing, add it.

#### Step 3B.4: Run the integration test — new assertions should pass

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -20`

Expected: all assertions pass, including both Sentinel and Counters blocks.

#### Step 3B.5: Run the whole MOP suite + Target::Perl tests that touch imports

Run each command, expected: pass.

- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-no-backchannel.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/class.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/import.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/hand-constructed.t 2>&1 | tail -3`
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -5`

Expected: all green. If `mop/import.t` regresses, that's the canary for "an existing test asserted `imports` includes `'constant'`" — read the failure and decide whether the test needs to be updated (the spec says no such site exists, but verify).

---

## Task 4: Cross-target regression check

The audit's risk #1 (Risk #1 in the design doc) said `use constant` re-routing might break callers that asserted `imports` contains `'constant'`. The spec-review iteration 1 grepped and found no such site, but the implementation should re-confirm now that the change has actually landed.

### Step 4.1: Re-grep the test surface

Run: `ag "'constant'" t/bootstrap/ 2>&1 | head -20`

Expected: matches for IR class names (`'Constant'` capitalized) and for the new tests you just wrote. Verify none of them assert `'constant'` (lowercase) as a module name in an `imports` context.

If you find an assertion like `is($main_imports[0]->module, 'constant', ...)`, that test depended on the old conflation and needs to be updated to assert against `use_constants` instead. Update it in the same commit; document in the commit message.

### Step 4.2: Run Target::Perl regression tests

Target::Perl iterates `$main->imports` at `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:96`. If any source in the codegen-byte-compat golden corpus used `use constant`, Target::Perl might have emitted `use constant` and now stops. Check:

Run: `ag "use constant" t/bootstrap/mop/golden/ 2>&1 | head -5`

If the golden corpus contains `use constant` in any class file, the golden output for that file may need regeneration. Re-run codegen-byte-compat to verify:

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -5`

Expected: 19/19. If any fail, inspect the diff between expected and actual — if the only difference is the disappearance of a `use constant` line, the design has a bug (Target::Perl needs to also consume use_constants) and you must stop and surface this back to the design phase before committing.

### Step 4.2.5: Regenerate the Chalk__MOP__Class golden

**Why this step exists:** `t/bootstrap/mop/codegen-byte-compat.t` test 14 regenerates `lib/Chalk/MOP/Class.pm` through Target::Perl and diffs the output against `t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden`. Tasks 1 and 2 legitimately add source (`$scope` field, `@class_scope_vars`, `@use_constants`, accessors, `declare_*` methods) to MOP/Class.pm. The regenerated output is correct but no longer matches the pre-Task-1 golden. This step regenerates the golden so the comparison passes at commit time.

The regenerated golden is **part of the single Phase 7c-prep commit**, not a separate change.

Use the existing regeneration script. Find it:

```bash
ls script/*golden* 2>&1 || ls t/bootstrap/regenerate* 2>&1 || grep -l "Chalk__MOP" script/ -r 2>&1 || grep -rl "golden_to_source\|codegen-goldens" script/ t/bootstrap/ 2>&1 | head -5
```

If a regeneration script exists (e.g., `script/regenerate-codegen-goldens` or similar), use it for just the Class golden. If none exists, the regeneration is a manual call to the Target::Perl pipeline:

1. Inspect `t/bootstrap/mop/codegen-byte-compat.t` lines 1-65 to see exactly how `regenerate($src)` derives the output for a single source. Reproduce that call for `lib/Chalk/MOP/Class.pm`, capture the output, and write it to `t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden`.

2. Re-run `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -3`. Expected: **`1..19` with no `not ok`**.

3. Inspect the diff between the old and new golden:

   ```bash
   git diff t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden | head -80
   ```

   The diff must show **only** the new `use Chalk::Bootstrap::Scope;`, the new `field $scope`, `field @class_scope_vars`, `field @use_constants`, the new accessors, the new `declare_class_scope_var` and `declare_use_constant` methods — and *nothing else*. If the diff includes unrelated reordering, whitespace changes, or other unexpected churn, STOP — that's symptomatic of a Target::Perl regression and must be diagnosed before continuing.

4. Stage the new golden:

   ```bash
   git add t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden
   ```

### Step 4.3: Broader regression check

Run these as a final sanity pass; expected: all pre-existing pass/fail counts unchanged from `docs/plans/2026-05-24-phase-7-baseline.md`.

- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -3` — 54/54
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3` — 178/178
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/xs-build.t 2>&1 | tail -3` — 63/63
- `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/xs-ast.t 2>&1 | tail -3` — 69/69

---

## Task 5: Final review + commit

### Step 5.1: Inspect the staged diff

Run: `git diff --cached --stat && git diff --cached`

Expected files staged:
- `lib/Chalk/MOP/Class.pm` (+ ~25 lines)
- `lib/Chalk/Bootstrap/Perl/Actions.pm` (+ ~22 lines, the elsif additions)
- `t/bootstrap/mop/class-scope-vars.t` (new)
- `t/bootstrap/mop/use-constants.t` (new)
- `t/bootstrap/mop/parse-integration.t` (+ inline tests for Sentinel + Counters)
- `t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden` (regenerated in Step 4.2.5)

If anything else is staged (e.g., from a tool-induced side-effect), unstage it.

### Step 5.2: Sanity check no extra files dirty

Run: `git status`

Expected: working tree clean except staged files.

### Step 5.3: Stage anything from Task 3/4 you haven't already

```bash
git add lib/Chalk/MOP/Class.pm lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/mop/class-scope-vars.t t/bootstrap/mop/use-constants.t t/bootstrap/mop/parse-integration.t
git status
```

### Step 5.4: Commit

```bash
git commit -m "$(cat <<'EOF'
feat(mop): Phase 7c-prep — MOP::Class gains class-body shape

Add lexical-environment and entity-list infrastructure to
Chalk::MOP::Class so Target::C (in 7c-proper) can stop iterating
the legacy ClassInfo body arrayref to recover class-scope `my`
declarations and `use constant` decls.

MOP::Class additions:
- $scope :reader — Chalk::Bootstrap::Scope, default-constructed.
  Lexical environment for the class body. Populated by
  declare_class_scope_var; read by no consumer in this commit, but
  the producer (declare_class_scope_var) needs a destination and
  the consumer (method bodies closing over class scope) is a
  known near-term commit.
- @class_scope_vars + class_scope_vars() — insertion-ordered list
  of VarDecl IR nodes for codegen iteration.
- @use_constants + use_constants() — insertion-ordered list of
  {name, value} hashrefs.
- declare_class_scope_var($vardecl_node) — records in list,
  binds in $scope. Does NOT merge into a class-side graph (no
  class graph exists in this commit; cross-graph ownership risk
  resolved by scope reduction — see design doc Risk #2).
- declare_use_constant($name, $value_node) — records the
  {name, value} pair.

Actions.pm changes:
- ClassBlock body-loop gains a VarDecl branch routing to
  declare_class_scope_var (positioned between UseInfo and the
  __adjust_body hash check).
- The existing UseInfo branch splits: `use constant { K => V }`
  routes to declare_use_constant; non-constant `use` decls keep
  declare_import. The conflation was forcing Target::C to walk
  the body twice; it stops now.

Tests:
- t/bootstrap/mop/class-scope-vars.t — 14 assertions covering the
  declare/list/scope API.
- t/bootstrap/mop/use-constants.t — 12 assertions covering the
  declare/list/order API.
- t/bootstrap/mop/parse-integration.t — extended with inline
  Sentinel class (class-scope-vars assertions) and Counters class
  (use-constants assertions plus "does not leak to imports" guard).

Out of scope (deferred to 7c-proper or later):
- Target::C migration off ClassInfo body iteration.
- Method-scope-inherits-class-scope wiring.
- StructPromotion body→graph migration.

Refs: docs/plans/2026-05-25-phase-7c-prep-design.md (3-iteration
spec review), docs/plans/2026-05-24-phase-7c-blocker.md.
EOF
)"
```

### Step 5.5: Verify commit landed

Run: `git log --oneline -1 && git status`

Expected: HEAD is the new feat(mop) commit; working tree clean.

---

## Done criteria

All of the following must hold at commit time:

1. `t/bootstrap/mop/codegen-byte-compat.t` — 19/19.
2. `t/bootstrap/mop/codegen-no-backchannel.t` — 2/2.
3. `t/bootstrap/mop/class-scope-vars.t` — passes (new).
4. `t/bootstrap/mop/use-constants.t` — passes (new).
5. `t/bootstrap/mop/parse-integration.t` — passes including the new Sentinel and Counters inline tests.
6. `t/bootstrap/mop/hand-constructed.t`, `class.t`, `method.t`, `field.t`, `import.t` — unchanged pass.
7. `t/bootstrap/c-emit-helpers-inheritance.t`, `bnf-target-c.t`, `xs-build.t`, `xs-ast.t` — pass counts identical to baseline.
8. Single commit on `fixup-audit-baseline` titled `feat(mop): Phase 7c-prep — MOP::Class gains class-body shape`.
9. No Target::C or Target::Perl code touched (verify with `git show --stat HEAD`).

---

## Rollback if needed

If any step fails and the failure is not a TDD red→green expected failure, run:

```bash
git status            # confirm what's dirty
git diff              # inspect uncommitted changes
git checkout -- .     # ONLY if you want to throw away the working tree
```

If you've already staged but not committed, `git reset HEAD` unstages without losing changes. Per CLAUDE.md: NEVER use `git reset --hard` or `git checkout --` to bypass an obstacle. Diagnose and fix.

If a test asserts something the spec didn't anticipate (e.g., `mop/import.t` asserts `'constant'` is a module — the spec said grep found no such site), STOP and surface back to the design author. Do not paper over with a test edit.
