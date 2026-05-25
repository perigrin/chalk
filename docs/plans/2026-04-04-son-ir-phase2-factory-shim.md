# SoN IR Phase 2: Factory Shim

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modify `Chalk::Bootstrap::IR::NodeFactory` to eagerly translate old-style `make('Constructor', class => 'X', ...)` calls to new `Chalk::IR::Node::*` typed nodes. Unmigrated consumers keep working via `->class()` shim methods and preserved input layouts.

**Architecture:** The old singleton factory delegates to a `Chalk::IR::NodeFactory` instance internally. Old-style Constructor creation is intercepted, translated to the new typed node, and the new node responds to `->class()` for backward compat. BinaryExpr/UnaryExpr input layouts are preserved (3 inputs / 2 inputs) during migration, with named fields on the typed nodes for clean accessor semantics.

**Tech Stack:** Perl 5.42.0, `feature class`. Modifies existing files for the first time.

**Design doc:** `docs/plans/2026-04-04-son-ir-polymorphic-migration.md`

**Skills required:** `writing-perl-5.42.0`, `test-driven-development`

**Prerequisite:** Phase 1 complete (all `Chalk::IR::Node::*` classes exist)

---

## File Map

### Modified files
- `lib/Chalk/IR/Node/BinOp.pm` — add named left/right fields
- `lib/Chalk/IR/Node/UnaryOp.pm` — add named operand field
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm` — add translation layer

### New files
- `lib/Chalk/IR/Shim.pm` — translation logic: old Constructor params → new typed nodes
- `t/bootstrap/ir-shim.t` — tests for the translation layer

### Test files to update
- `t/bootstrap/ir-node-binop.t` — update for named field constructors
- `t/bootstrap/ir-node-unaryop.t` — update for named field constructors

---

## Task 1: Add Named Fields to BinOp

BinOp currently gets left/right from `inputs->[0]` and `inputs->[1]`. During migration, inputs will be `[op_const, left, right]` (3 elements). Named fields decouple accessors from input position.

**Files:**
- Modify: `lib/Chalk/IR/Node/BinOp.pm`
- Modify: `t/bootstrap/ir-node-binop.t`

- [ ] **Step 1: Update test to use named fields**

In `t/bootstrap/ir-node-binop.t`, change the Add construction to pass named fields:

```perl
# Change from:
my $add = Chalk::IR::Node::Add->new(id => 'add_0', inputs => [$left, $right]);

# To:
my $add = Chalk::IR::Node::Add->new(
    id => 'add_0', inputs => [$left, $right], left => $left, right => $right,
);
```

Also update the loop that constructs all 29 types:

```perl
# Change from:
my $node = $class->new(id => "${type}_test", inputs => [$left, $right]);

# To:
my $node = $class->new(
    id => "${type}_test", inputs => [$left, $right],
    left => $left, right => $right,
);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-node-binop.t`
Expected: FAIL — BinOp doesn't accept left/right params yet

- [ ] **Step 3: Update BinOp to use named fields**

`lib/Chalk/IR/Node/BinOp.pm`:
```perl
# ABOUTME: Intermediate base class for binary operation IR nodes.
# ABOUTME: Provides left(), right(), and abstract op_str() accessors.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::BinOp :isa(Chalk::IR::Node) {
    field $left  :param :reader;
    field $right :param :reader;

    method op_str() {
        die "Subclass must implement op_str()";
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-node-binop.t`
Expected: All tests PASS

- [ ] **Step 5: Run all IR tests for regression**

Run: `SHELL=/bin/bash /bin/bash -c '$HOME/.local/share/pvm/versions/5.42.0/bin/perl -MTAP::Harness -e "TAP::Harness->new({verbosity => 0, lib => [qw(lib)]})->runtests(glob q{t/bootstrap/ir-*.t})"'`
Expected: All tests PASS (factory test also uses BinOp — may need updating)

- [ ] **Step 6: Commit**

```bash
git add lib/Chalk/IR/Node/BinOp.pm t/bootstrap/ir-node-binop.t
git commit -m "refactor: BinOp uses named left/right fields for migration compat"
```

---

## Task 2: Add Named Field to UnaryOp

Same pattern as Task 1 but for UnaryOp's operand.

**Files:**
- Modify: `lib/Chalk/IR/Node/UnaryOp.pm`
- Modify: `t/bootstrap/ir-node-unaryop.t`

- [ ] **Step 1: Update test to use named field**

In `t/bootstrap/ir-node-unaryop.t`, change constructions to pass `operand =>`:

```perl
# Change from:
my $not = Chalk::IR::Node::Not->new(id => 'not_0', inputs => [$operand]);

# To:
my $not = Chalk::IR::Node::Not->new(
    id => 'not_0', inputs => [$operand], operand => $operand,
);
```

Same for the loop over all 4 types.

- [ ] **Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-node-unaryop.t`
Expected: FAIL

- [ ] **Step 3: Update UnaryOp to use named field**

`lib/Chalk/IR/Node/UnaryOp.pm`:
```perl
# ABOUTME: Intermediate base class for unary operation IR nodes.
# ABOUTME: Provides operand() and abstract op_str() accessors.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::UnaryOp :isa(Chalk::IR::Node) {
    field $operand :param :reader;

    method op_str() {
        die "Subclass must implement op_str()";
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-node-unaryop.t`
Expected: All PASS

- [ ] **Step 5: Run all IR tests for regression**

- [ ] **Step 6: Commit**

```bash
git add lib/Chalk/IR/Node/UnaryOp.pm t/bootstrap/ir-node-unaryop.t
git commit -m "refactor: UnaryOp uses named operand field for migration compat"
```

---

## Task 3: Translation Module (Chalk::IR::Shim)

The core translation logic mapping old Constructor params to new typed nodes.

**Files:**
- Create: `lib/Chalk/IR/Shim.pm`
- Test: `t/bootstrap/ir-shim.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-shim.t`:

```perl
# ABOUTME: Tests for Chalk::IR::Shim — old Constructor API to new typed node translation.
# ABOUTME: Verifies that make_from_constructor produces correct typed nodes with class() compat.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Shim;

my $f = Chalk::IR::NodeFactory->new();

# Helper: create Constant nodes for test inputs
sub const ($val) { $f->make('Constant', value => $val, const_type => 'string') }

# BinaryExpr → typed BinOp
{
    my $op = const('+');
    my $left = const('1');
    my $right = const('2');
    my $node = Chalk::IR::Shim::translate($f, 'BinaryExpr',
        op => $op, left => $left, right => $right);

    isa_ok($node, 'Chalk::IR::Node::Add', 'BinaryExpr(+) → Add');
    isa_ok($node, 'Chalk::IR::Node::BinOp', 'Add isa BinOp');
    is($node->class(), 'BinaryExpr', 'class() compat returns BinaryExpr');
    is($node->op_str(), '+', 'op_str is +');
    is($node->left(), $left, 'left accessor works');
    is($node->right(), $right, 'right accessor works');
    # Old-style inputs preserved: [op, left, right]
    is(scalar $node->inputs()->@*, 3, '3 inputs for migration compat');
    is($node->inputs()->[0], $op, 'inputs[0] is op Constant');
}

# BinaryExpr with string comparison op
{
    my $node = Chalk::IR::Shim::translate($f, 'BinaryExpr',
        op => const('eq'), left => const('a'), right => const('b'));
    isa_ok($node, 'Chalk::IR::Node::StrEq', 'BinaryExpr(eq) → StrEq');
    is($node->class(), 'BinaryExpr', 'class() compat');
}

# UnaryExpr → typed UnaryOp
{
    my $op = const('!');
    my $operand = const('true');
    my $node = Chalk::IR::Shim::translate($f, 'UnaryExpr',
        op => $op, operand => $operand);

    isa_ok($node, 'Chalk::IR::Node::Not', 'UnaryExpr(!) → Not');
    is($node->class(), 'UnaryExpr', 'class() compat returns UnaryExpr');
    is($node->operand(), $operand, 'operand accessor works');
    is(scalar $node->inputs()->@*, 2, '2 inputs for migration compat');
    is($node->inputs()->[0], $op, 'inputs[0] is op Constant');
}

# MethodCallExpr → Call(method)
{
    my $invocant = const('$self');
    my $method = const('foo');
    my $args = [const('arg1')];
    my $node = Chalk::IR::Shim::translate($f, 'MethodCallExpr',
        invocant => $invocant, method_name => $method, args => $args);

    isa_ok($node, 'Chalk::IR::Node::Call', 'MethodCallExpr → Call');
    is($node->class(), 'MethodCallExpr', 'class() compat');
    is($node->dispatch_kind(), 'method', 'dispatch_kind is method');
}

# BuiltinCall → Call(builtin)
{
    my $name = const('push');
    my $args = [const('x')];
    my $node = Chalk::IR::Shim::translate($f, 'BuiltinCall',
        name => $name, args => $args);

    isa_ok($node, 'Chalk::IR::Node::Call', 'BuiltinCall → Call');
    is($node->class(), 'BuiltinCall', 'class() compat');
    is($node->dispatch_kind(), 'builtin', 'dispatch_kind is builtin');
}

# SubscriptExpr → Subscript
{
    my $node = Chalk::IR::Shim::translate($f, 'SubscriptExpr',
        target => const('$h'), index => const('key'), style => const('hash'));
    isa_ok($node, 'Chalk::IR::Node::Subscript', 'SubscriptExpr → Subscript');
    is($node->class(), 'SubscriptExpr', 'class() compat');
}

# PostfixDerefExpr → PostfixDeref
{
    my $node = Chalk::IR::Shim::translate($f, 'PostfixDerefExpr',
        target => const('$ref'), sigil => const('@'));
    isa_ok($node, 'Chalk::IR::Node::PostfixDeref', 'PostfixDerefExpr → PostfixDeref');
    is($node->class(), 'PostfixDerefExpr', 'class() compat');
}

# HashRefExpr → HashRef
{
    my $node = Chalk::IR::Shim::translate($f, 'HashRefExpr',
        pairs => [const('k'), const('v')]);
    isa_ok($node, 'Chalk::IR::Node::HashRef', 'HashRefExpr → HashRef');
    is($node->class(), 'HashRefExpr', 'class() compat');
}

# VarDecl → VarDecl
{
    my $node = Chalk::IR::Shim::translate($f, 'VarDecl',
        variable => const('$x'), initializer => const('0'));
    isa_ok($node, 'Chalk::IR::Node::VarDecl', 'VarDecl → VarDecl');
    is($node->class(), 'VarDecl', 'class() compat');
}

# Structural types return undef (not translated)
{
    my $result = Chalk::IR::Shim::translate($f, 'Program', statements => []);
    is($result, undef, 'Program not translated (structural)');
}

# BNF types return undef
{
    my $result = Chalk::IR::Shim::translate($f, 'Symbol',
        type => const('terminal'), value => const('x'), quantifier => undef);
    is($result, undef, 'Symbol not translated (BNF)');
}

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-shim.t`
Expected: FAIL — `Can't locate Chalk/IR/Shim.pm`

- [ ] **Step 3: Write Chalk::IR::Shim**

Create `lib/Chalk/IR/Shim.pm`. This is a module (not a class) with a single function `translate($factory, $constructor_class, %params)`. Returns the new typed node, or `undef` if the Constructor class should not be translated (structural/BNF types).

The function:
1. Maps `$constructor_class` to the translation handler
2. For BinaryExpr: extracts op string from `$params{op}->value()`, looks up BinOp type name, creates node via factory with `inputs => [$params{op}, $params{left}, $params{right}]` and named fields `left => $params{left}, right => $params{right}`
3. For UnaryExpr: same pattern — extracts op, looks up UnaryOp type, `inputs => [$params{op}, $params{operand}]`, named field `operand => $params{operand}`
4. For MethodCallExpr: creates Call with `dispatch_kind => 'method'`, `name` from method_name Constant's value, `inputs => [$params{invocant}, $params{method_name}, $params{args}]`
5. For simple mappings (HashRefExpr→HashRef, etc.): creates the typed node with the same inputs layout
6. Each returned node gets a `class()` method injected that returns the original Constructor class name

The `class()` compat method is injected by creating a wrapper role/mixin. Since `feature class` doesn't support roles, use a per-node method installation approach: after creating the typed node, install a `class` method on the object's package that returns the compat name. BUT — this would affect all instances of that class. Instead, store the compat name in the node and provide it via a method on the base class.

**Better approach:** Add a `field $compat_class :param :reader = undef;` to `Chalk::IR::Node` base. The `class()` method returns `$compat_class // $self->operation()`. The shim passes `compat_class => 'BinaryExpr'` when creating the node. This is clean, no monkey-patching.

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Run all IR tests for regression**

- [ ] **Step 6: Commit**

```bash
git add lib/Chalk/IR/Shim.pm lib/Chalk/IR/Node.pm t/bootstrap/ir-shim.t
git commit -m "feat: Chalk::IR::Shim translates old Constructor API to typed nodes"
```

---

## Task 4: Update NodeFactory to Add compat_class Field

Add `compat_class` field to `Chalk::IR::Node` base and a `class()` method.

**Files:**
- Modify: `lib/Chalk/IR/Node.pm`
- Modify: `t/bootstrap/ir-node-base.t`

- [ ] **Step 1: Add test for class() method**

Add to `t/bootstrap/ir-node-base.t`:
```perl
# class() returns compat_class if set, otherwise operation()
my $compat = Chalk::IR::Node->new(id => 'compat_1', compat_class => 'BinaryExpr');
is($compat->class(), 'BinaryExpr', 'class() returns compat_class');

# class() falls back to operation() when no compat_class
# (can't test on base — operation() dies; tested via subclasses in other tests)
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Add compat_class field and class() method to Node.pm**

Add to `Chalk::IR::Node`:
```perl
field $compat_class :param :reader = undef;

method class() {
    return $compat_class if defined $compat_class;
    return $self->operation();
}
```

- [ ] **Step 4: Run tests**

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/Node.pm t/bootstrap/ir-node-base.t
git commit -m "feat: Node.class() returns compat_class for migration backward compat"
```

---

## Task 5: Wire Shim into Old NodeFactory

Modify `Chalk::Bootstrap::IR::NodeFactory::make()` to intercept Constructor creation and delegate to the shim.

**Files:**
- Modify: `lib/Chalk/Bootstrap/IR/NodeFactory.pm`
- Test: `t/bootstrap/ir-factory-shim-integration.t`

- [ ] **Step 1: Write integration test**

Create `t/bootstrap/ir-factory-shim-integration.t`:

```perl
# ABOUTME: Integration test: old NodeFactory produces new typed nodes via shim.
# ABOUTME: Verifies that make('Constructor', class=>'X', ...) returns Chalk::IR::Node::* types.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset singleton for clean test state
Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

# BinaryExpr produces typed Add node
my $op = $f->make('Constant', const_type => 'string', value => '+');
my $left = $f->make('Constant', const_type => 'integer', value => '1');
my $right = $f->make('Constant', const_type => 'integer', value => '2');
my $add = $f->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right);

isa_ok($add, 'Chalk::IR::Node::Add', 'Old API produces Add node');
isa_ok($add, 'Chalk::IR::Node::BinOp', 'Add isa BinOp');
is($add->class(), 'BinaryExpr', 'class() returns BinaryExpr for compat');
is($add->op_str(), '+', 'op_str() works on translated node');

# MethodCallExpr produces Call node
my $invocant = $f->make('Constant', const_type => 'variable', value => '$self');
my $method = $f->make('Constant', const_type => 'string', value => 'foo');
my $call = $f->make('Constructor', class => 'MethodCallExpr',
    invocant => $invocant, method_name => $method, args => []);

isa_ok($call, 'Chalk::IR::Node::Call', 'MethodCallExpr produces Call');
is($call->class(), 'MethodCallExpr', 'class() compat');

# Structural types still produce Constructor
my $program = $f->make('Constructor', class => 'Program', statements => []);
isa_ok($program, 'Chalk::Bootstrap::IR::Node::Constructor',
    'Program still produces Constructor');
is($program->class(), 'Program', 'Program class unchanged');

# BNF types still produce Constructor
my $sym_type = $f->make('Constant', const_type => 'string', value => 'terminal');
my $sym_val = $f->make('Constant', const_type => 'string', value => 'x');
my $symbol = $f->make('Constructor', class => 'Symbol',
    type => $sym_type, value => $sym_val, quantifier => undef);
isa_ok($symbol, 'Chalk::Bootstrap::IR::Node::Constructor',
    'Symbol still produces Constructor');

# Hash consing: same BinaryExpr produces same typed node
my $add2 = $f->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right);
ok($add == $add2, 'Translated nodes are hash-consed');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Modify old NodeFactory**

In `Chalk::Bootstrap::IR::NodeFactory::make()`, add shim interception at the top of the Constructor branch:

```perl
if ($operation eq 'Constructor') {
    my $class = $params{class}
        or die "Constructor requires 'class' parameter";

    # Try translating to new typed node
    require Chalk::IR::Shim;
    my $typed = Chalk::IR::Shim::translate($self->_new_factory(), $class, %params);
    if (defined $typed) {
        # Cache under old-style key for deduplication
        my $key = $typed->content_hash();
        return $node_cache->{$key} if exists $node_cache->{$key};
        $node_cache->{$key} = $typed;
        return $typed;
    }

    # Fall through to old Constructor for untranslated types
    $lookup_key = "Constructor:$class";
}
```

The `_new_factory()` method lazily creates and caches a `Chalk::IR::NodeFactory` instance.

- [ ] **Step 4: Run integration test**

- [ ] **Step 5: Run ALL existing tests (not just IR tests)**

This is the critical step — the old factory change must not break any existing functionality.

Run: `SHELL=/bin/bash /bin/bash -c '$HOME/.local/share/pvm/versions/5.42.0/bin/perl -MTAP::Harness -e "TAP::Harness->new({verbosity => 0, lib => [qw(lib)]})->runtests(glob q{t/bootstrap/*.t})"'`
Expected: All existing tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/IR/NodeFactory.pm t/bootstrap/ir-factory-shim-integration.t
git commit -m "feat: old NodeFactory delegates Constructor creation to Chalk::IR::Shim"
```

---

## Task 6: Verify Existing Test Suite

Run the full existing test suite to confirm the shim doesn't break anything. The old factory now returns typed nodes for computation Constructor classes, and those nodes respond to `->class()` for backward compat.

- [ ] **Step 1: Run all bootstrap tests**

Run: `SHELL=/bin/bash /bin/bash -c '$HOME/.local/share/pvm/versions/5.42.0/bin/perl -MTAP::Harness -e "TAP::Harness->new({verbosity => 0, lib => [qw(lib)]})->runtests(glob q{t/bootstrap/*.t})"'`
Expected: All tests PASS

- [ ] **Step 2: If failures, diagnose and fix**

Common failure modes:
- Consumer code checks `$node isa Chalk::Bootstrap::IR::Node::Constructor` — the typed nodes are NOT Constructor subclasses. These sites need the `isa` check updated, or the shim needs to leave that Constructor class untranslated until Phase 4.
- Consumer code reads `$node->inputs()` with position assumptions that differ from the shim's input layout.

If too many failures, selectively disable translation for problematic Constructor classes in the shim (return undef for them) and file issues for Phase 4.

- [ ] **Step 3: Commit any fixes**
