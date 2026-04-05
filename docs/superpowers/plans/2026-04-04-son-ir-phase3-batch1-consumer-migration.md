# SoN IR Phase 3 Batch 1: Consumer Migration (ToSoN + StructPromotion)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the first two consumer files from `isa Constructor` + `->class()` dispatch to typed `isa Chalk::IR::Node::*` checks. Enable shim translation for the migrated Constructor classes. Prove the migration pattern works end-to-end.

**Architecture:** Each `$node isa Chalk::Bootstrap::IR::Node::Constructor && $node->class() eq 'X'` becomes `$node isa Chalk::IR::Node::X`. Structural types (Program, ClassDecl, MethodDecl, SubDecl, FieldDecl) keep their `isa Constructor` checks since they stay as Constructor until Phase 4. The shim's `if (0)` guard gets replaced with a `%ENABLED` set that grows as consumers migrate.

**Tech Stack:** Perl 5.42.0, `feature class`. Modifying existing production code.

**Design doc:** `docs/plans/2026-04-04-son-ir-polymorphic-migration.md`

**Prerequisite:** Phase 1 (types exist) and Phase 2 (shim built, disabled) complete.

---

## File Map

### Deleted files
- `lib/Chalk/Bootstrap/IR/ToSoN.pm` — adapter no longer needed

### Modified files
- `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` — migrate isa/class checks
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm` — replace `if (0)` with `%ENABLED` set
- `lib/Chalk/IR/Shim.pm` — export `%ENABLED` for factory to check

### Test files
- Delete: `t/bootstrap/ir-shim-son-*.t` or similar ToSoN tests (if any)
- Modify: existing StructPromotion tests (if `isa` checks fail)
- Create: `t/bootstrap/ir-shim-activation.t` — verify shim produces typed nodes when enabled

---

## Task 1: Delete ToSoN.pm

ToSoN.pm is the adapter that translates Chalk IR to SoN IR. With typed
nodes that ARE SoN-compatible, the adapter is unnecessary.

**Files:**
- Delete: `lib/Chalk/Bootstrap/IR/ToSoN.pm`
- Check: any test files that import ToSoN

- [ ] **Step 1: Find all references to ToSoN**

Run: `grep -r 'ToSoN' lib/ t/ --include='*.pm' --include='*.t' -l`

- [ ] **Step 2: Check if any test files depend on ToSoN**

If there are test files that `use Chalk::Bootstrap::IR::ToSoN`, they need
to be updated or deleted.

- [ ] **Step 3: Delete ToSoN.pm**

```bash
git rm lib/Chalk/Bootstrap/IR/ToSoN.pm
```

- [ ] **Step 4: Delete or update any ToSoN test files**

- [ ] **Step 5: Run all IR tests to verify no breakage**

Run: `SHELL=/bin/bash /bin/bash -c '$HOME/.local/share/pvm/versions/5.42.0/bin/perl -MTAP::Harness -e "TAP::Harness->new({verbosity => 0, lib => [qw(lib)]})->runtests(glob q{t/bootstrap/ir-*.t})"'`

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: delete ToSoN adapter — typed nodes replace it"
```

---

## Task 2: Add Shim Activation Mechanism

Replace the `if (0)` guard in the old factory with a `%ENABLED` set that
controls which Constructor classes get translated.

**Files:**
- Modify: `lib/Chalk/IR/Shim.pm` — add `%ENABLED` and `enable_class()` / `is_enabled()`
- Modify: `lib/Chalk/Bootstrap/IR/NodeFactory.pm` — check `%ENABLED` instead of `if (0)`
- Create: `t/bootstrap/ir-shim-activation.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-shim-activation.t`:

```perl
# ABOUTME: Tests that the shim activation mechanism works correctly.
# ABOUTME: Verifies enabled classes produce typed nodes, disabled produce Constructor.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::IR::Shim;

# Reset everything
Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
Chalk::IR::Shim::reset_enabled();

my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

# Before enabling: BinaryExpr produces old Constructor
my $op = $f->make('Constant', const_type => 'string', value => '+');
my $left = $f->make('Constant', const_type => 'integer', value => '1');
my $right = $f->make('Constant', const_type => 'integer', value => '2');

# Need fresh factory after enabling
Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $f1 = Chalk::Bootstrap::IR::NodeFactory->instance();

my $add_old = $f1->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right);
isa_ok($add_old, 'Chalk::Bootstrap::IR::Node::Constructor',
    'Before enable: BinaryExpr is Constructor');

# Enable BinaryExpr
Chalk::IR::Shim::enable_class('BinaryExpr');

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $f2 = Chalk::Bootstrap::IR::NodeFactory->instance();

# Re-create constants through new factory instance
my $op2 = $f2->make('Constant', const_type => 'string', value => '+');
my $left2 = $f2->make('Constant', const_type => 'integer', value => '1');
my $right2 = $f2->make('Constant', const_type => 'integer', value => '2');

my $add_new = $f2->make('Constructor', class => 'BinaryExpr',
    op => $op2, left => $left2, right => $right2);
isa_ok($add_new, 'Chalk::IR::Node::Add',
    'After enable: BinaryExpr produces Add');
is($add_new->class(), 'BinaryExpr', 'class() compat still works');

# Program is NOT enabled — still Constructor
my $prog = $f2->make('Constructor', class => 'Program', statements => []);
isa_ok($prog, 'Chalk::Bootstrap::IR::Node::Constructor',
    'Program still Constructor (not enabled)');

# Clean up
Chalk::IR::Shim::reset_enabled();

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Add activation API to Shim.pm**

Add to `lib/Chalk/IR/Shim.pm`:

```perl
# Set of Constructor classes enabled for shim translation.
# Populated incrementally as consumer files are migrated.
my %ENABLED;

sub enable_class ($class_name)   { $ENABLED{$class_name} = 1; }
sub disable_class ($class_name)  { delete $ENABLED{$class_name}; }
sub is_enabled ($class_name)     { exists $ENABLED{$class_name} }
sub reset_enabled ()             { %ENABLED = (); }
```

Modify the `translate()` function to check `%ENABLED` at the top:

```perl
sub translate($factory, $constructor_class, %params) {
    return undef unless $ENABLED{$constructor_class};
    # ... rest of existing translate logic ...
}
```

- [ ] **Step 4: Update old NodeFactory to use activation**

In `lib/Chalk/Bootstrap/IR/NodeFactory.pm`, replace the `if (0)` block:

```perl
# Shim translation — enabled per-class as consumers are migrated
$self->_ensure_new_factory();
my $typed = Chalk::IR::Shim::translate($_new_factory, $class, %params);
if (defined $typed) {
    my $key = $typed->content_hash();
    return $node_cache->{$key} if exists $node_cache->{$key};
    $node_cache->{$key} = $typed;
    return $typed;
}
```

(Remove the `if (0)` guard — the activation check is now inside `translate()`.)

- [ ] **Step 5: Run test to verify it passes**

- [ ] **Step 6: Run all IR tests + assignment-scope to verify no regressions**

With no classes enabled, behavior should be identical to the disabled state.

- [ ] **Step 7: Commit**

```bash
git add lib/Chalk/IR/Shim.pm lib/Chalk/Bootstrap/IR/NodeFactory.pm \
        t/bootstrap/ir-shim-activation.t
git commit -m "feat: shim activation mechanism — enable_class() controls per-type translation"
```

---

## Task 3: Migrate StructPromotion.pm

StructPromotion has 14 `isa Constructor` checks and 15 `->class() eq` checks.
Some are for structural types (MethodDecl, SubDecl, ClassDecl, Program)
which stay as Constructor. The rest are computation types that get migrated.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm`

**Computation types to migrate** (replace `isa Constructor && class eq 'X'`
with `isa Chalk::IR::Node::X`):
- `VarDecl` → `isa Chalk::IR::Node::VarDecl`
- `HashRefExpr` → `isa Chalk::IR::Node::HashRef`
- `BinaryExpr` → `isa Chalk::IR::Node::BinOp` (or specific subtype)
- `SubscriptExpr` → `isa Chalk::IR::Node::Subscript`

**Structural types to keep as-is** (still Constructor until Phase 4):
- `MethodDecl`, `SubDecl`, `ClassDecl`, `Program`

**Mixed checks** where both structural and computation types are tested:
Some guards check `isa Constructor` then branch on class(). These need
splitting: the structural branch keeps `isa Constructor`, the computation
branch uses typed `isa`.

- [ ] **Step 1: Read StructPromotion.pm fully**

Read the entire file to understand each `isa Constructor` site in context.

- [ ] **Step 2: Categorize each site**

For each of the 14 `isa Constructor` checks, determine:
- Is it checking a computation type? → Migrate to typed isa
- Is it checking a structural type? → Keep as Constructor
- Is it a guard before a `->class()` dispatch? → Split the dispatch

- [ ] **Step 3: Add `use` statements for new node types**

Add at the top of StructPromotion.pm:

```perl
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::Subscript;
```

- [ ] **Step 4: Migrate computation-type checks**

Replace patterns like:
```perl
# Before:
next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
if ($item->class() eq 'VarDecl') { ... }

# After:
if ($item isa Chalk::IR::Node::VarDecl) { ... }
```

For guards that check `isa Constructor` then branch on multiple classes:
```perl
# Before:
return unless $node isa Chalk::Bootstrap::IR::Node::Constructor;
my $class = $node->class();
if ($class eq 'VarDecl') { ... }
elsif ($class eq 'BinaryExpr') { ... }
elsif ($class eq 'SubscriptExpr') { ... }

# After:
if ($node isa Chalk::IR::Node::VarDecl) { ... }
elsif ($node isa Chalk::IR::Node::BinOp) { ... }
elsif ($node isa Chalk::IR::Node::Subscript) { ... }
# (removed the isa Constructor guard — typed isa handles it)
```

For sites that mix structural and computation checks:
```perl
# Before:
next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
next unless $item->class() eq 'MethodDecl' || $item->class() eq 'SubDecl';

# After (structural types stay as Constructor):
next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
next unless $item->class() eq 'MethodDecl' || $item->class() eq 'SubDecl';
# (no change — these are structural)
```

- [ ] **Step 5: Enable shim for migrated types**

The types StructPromotion checks are: VarDecl, HashRefExpr, BinaryExpr,
SubscriptExpr. However, we should only enable types whose `isa Constructor`
checks have been migrated in ALL consumer files, not just StructPromotion.

For now, DON'T enable the shim yet. This task only migrates the isa checks
in StructPromotion. The shim gets enabled after all consumer files for each
type are migrated.

Instead, make the migrated isa checks work with BOTH old Constructor nodes
AND new typed nodes. The typed `isa` check works for new types. For old
Constructor nodes, we need a fallback.

**Key insight:** During the transition period, StructPromotion receives
Constructor nodes (shim disabled). The new typed `isa` checks will fail
on Constructor nodes. We need to handle both:

```perl
# Works for both old and new:
if ($node isa Chalk::IR::Node::VarDecl
    || ($node isa Chalk::Bootstrap::IR::Node::Constructor
        && $node->class() eq 'VarDecl')) { ... }
```

This is ugly but temporary. Once the shim is enabled for VarDecl, all
nodes are typed and the Constructor fallback is dead code. It gets
removed in Phase 5.

- [ ] **Step 6: Run StructPromotion tests**

Find and run any tests that exercise StructPromotion:
```bash
grep -rl 'StructPromotion' t/ --include='*.t'
```

- [ ] **Step 7: Run all bootstrap tests**

Verify no regressions.

- [ ] **Step 8: Commit**

```bash
git add lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm
git commit -m "feat: migrate StructPromotion isa checks to typed nodes (dual-path)"
```

---

## Task 4: Full Regression + Enable Shim for Safe Types

After StructPromotion is migrated, check if any computation types are now
safe to enable (all their `isa Constructor` checks migrated across ALL files).

- [ ] **Step 1: For each computation type, grep for remaining isa Constructor checks**

```bash
# For each type: VarDecl, HashRefExpr, BinaryExpr, SubscriptExpr
grep -r "class() eq 'VarDecl'" lib/ --include='*.pm' | grep -v StructPromotion
```

If a type has zero remaining `isa Constructor` checks outside StructPromotion,
it's safe to enable in the shim.

- [ ] **Step 2: Enable safe types (if any)**

Add to a startup file or test setup:
```perl
Chalk::IR::Shim::enable_class('VarDecl');  # if safe
```

- [ ] **Step 3: Run full test suite**

- [ ] **Step 4: Commit**
