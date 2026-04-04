# SoN IR Phase 1: Scaffold New Type Hierarchy

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `Chalk::IR::Node::*` type hierarchy, `Chalk::IR::Graph`, and `Chalk::IR::Program` metadata structs — the foundation for replacing Constructor type-case dispatch.

**Architecture:** Inline SoN's node protocol (operation, content_hash, hash consing) into Chalk's own namespace. Intermediate base classes (BinOp, UnaryOp, Access, Aggregate, Regex) provide shared accessors. Metadata structs (Program, ClassInfo, MethodInfo, FieldInfo, SubInfo) are plain `feature class` containers. Nothing in this phase changes existing code — it's purely additive.

**Tech Stack:** Perl 5.42.0 with `feature class`, `use utf8`, `true`/`false` builtins. Follow SoN node patterns from `perl5-son/lib/SoN/IR/Node/*.pm`.

**Design doc:** `docs/plans/2026-04-04-son-ir-polymorphic-migration.md`

**Skills required:** `writing-perl-5.42.0`, `test-driven-development`

---

## File Map

### New directories
- `lib/Chalk/IR/` — new type hierarchy root
- `lib/Chalk/IR/Node/` — computation node classes

### New files: Core
- `lib/Chalk/IR/Node.pm` — base class (id, inputs, consumers, stamp, operation, content_hash)
- `lib/Chalk/IR/Graph.pm` — per-method graph container (start, returns, nodes)
- `lib/Chalk/IR/NodeFactory.pm` — factory with make/make_cfg and hash consing

### New files: CFG nodes
- `lib/Chalk/IR/Node/Start.pm`
- `lib/Chalk/IR/Node/Return.pm`
- `lib/Chalk/IR/Node/Unwind.pm`
- `lib/Chalk/IR/Node/If.pm`
- `lib/Chalk/IR/Node/Proj.pm`
- `lib/Chalk/IR/Node/Region.pm`
- `lib/Chalk/IR/Node/Loop.pm`

### New files: Intermediate base classes
- `lib/Chalk/IR/Node/BinOp.pm` — left(), right(), op_str()
- `lib/Chalk/IR/Node/UnaryOp.pm` — operand(), op_str()
- `lib/Chalk/IR/Node/Access.pm` — grouping base
- `lib/Chalk/IR/Node/Aggregate.pm` — grouping base
- `lib/Chalk/IR/Node/Regex.pm` — grouping base

### New files: BinOp leaf nodes (29 classes)
- `lib/Chalk/IR/Node/Add.pm` through `lib/Chalk/IR/Node/Assign.pm`
- Full list: Add, Subtract, Multiply, Divide, Modulo, Power, Concat,
  NumEq, NumNe, NumLt, NumGt, NumLe, NumGe, NumCmp,
  StrEq, StrNe, StrLt, StrGt, StrLe, StrGe, StrCmp,
  And, Or, BitAnd, BitOr, BitXor, LeftShift, RightShift, Assign

### New files: UnaryOp leaf nodes (4 classes)
- `lib/Chalk/IR/Node/Not.pm`
- `lib/Chalk/IR/Node/Negate.pm`
- `lib/Chalk/IR/Node/Complement.pm`
- `lib/Chalk/IR/Node/Defined.pm`

### New files: Data nodes
- `lib/Chalk/IR/Node/Constant.pm` — value, stamp, const_type
- `lib/Chalk/IR/Node/Phi.pm` — region field, set_backedge

### New files: Access nodes
- `lib/Chalk/IR/Node/PadAccess.pm` — targ, varname
- `lib/Chalk/IR/Node/FieldAccess.pm` — field_index, field_stash
- `lib/Chalk/IR/Node/StashAccess.pm`
- `lib/Chalk/IR/Node/Subscript.pm`

### New files: Call and misc computation nodes
- `lib/Chalk/IR/Node/Call.pm` — dispatch_kind, name
- `lib/Chalk/IR/Node/HashRef.pm`
- `lib/Chalk/IR/Node/ArrayRef.pm`
- `lib/Chalk/IR/Node/Interpolate.pm`
- `lib/Chalk/IR/Node/AnonSub.pm` — holds nested Graph
- `lib/Chalk/IR/Node/RegexMatch.pm` — flags
- `lib/Chalk/IR/Node/RegexSubst.pm` — flags
- `lib/Chalk/IR/Node/TryCatch.pm`
- `lib/Chalk/IR/Node/PostfixDeref.pm` — sigil
- `lib/Chalk/IR/Node/CompoundAssign.pm` — op
- `lib/Chalk/IR/Node/BacktickExpr.pm`
- `lib/Chalk/IR/Node/VarDecl.pm`

### New files: Metadata structs
- `lib/Chalk/IR/Program.pm` — use_decls, classes, top_level_subs
- `lib/Chalk/IR/ClassInfo.pm` — name, parent, fields, methods, subs
- `lib/Chalk/IR/MethodInfo.pm` — name, params, return_type, graph
- `lib/Chalk/IR/SubInfo.pm` — name, params, scope, graph
- `lib/Chalk/IR/FieldInfo.pm` — name, attributes, default_value

### New files: Tests
- `t/bootstrap/ir-node-base.t` — base class, operation, content_hash
- `t/bootstrap/ir-node-binop.t` — BinOp hierarchy, left/right/op_str
- `t/bootstrap/ir-node-unaryop.t` — UnaryOp hierarchy, operand/op_str
- `t/bootstrap/ir-node-cfg.t` — CFG nodes, uniqueness (not hash-consed)
- `t/bootstrap/ir-node-data.t` — Constant, Phi, Access, Call, misc
- `t/bootstrap/ir-node-factory.t` — hash consing, make/make_cfg
- `t/bootstrap/ir-graph.t` — Graph container, topological sort
- `t/bootstrap/ir-metadata.t` — Program, ClassInfo, MethodInfo, etc.

---

## Task 1: Base Node Class

**Files:**
- Create: `lib/Chalk/IR/Node.pm`
- Test: `t/bootstrap/ir-node-base.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-node-base.t`:

```perl
# ABOUTME: Tests for Chalk::IR::Node base class.
# ABOUTME: Verifies id, inputs, consumers, stamp, operation, and content_hash.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;

# Base class exists and can be instantiated
my $node = Chalk::IR::Node->new(id => 'test_1');
isa_ok($node, 'Chalk::IR::Node');

# Fields have correct defaults
is($node->id(), 'test_1', 'id is set');
is_deeply($node->inputs(), [], 'inputs default to empty array');
is_deeply($node->consumers(), [], 'consumers default to empty array');
is($node->stamp(), undef, 'stamp defaults to undef');

# operation() is abstract — base class dies
eval { $node->operation() };
like($@, qr/Subclass must implement/, 'base operation() dies');

# content_hash() uses operation + input ids
# (Can only test this via a subclass — tested in later tasks)

# Consumer tracking
my $producer = Chalk::IR::Node->new(id => 'p1');
my $consumer = Chalk::IR::Node->new(id => 'c1');
$producer->add_consumer($consumer);
is(scalar $producer->consumers()->@*, 1, 'add_consumer adds one');
is($producer->consumers()->[0]->id(), 'c1', 'consumer is correct node');

$producer->remove_consumer($consumer);
is(scalar $producer->consumers()->@*, 0, 'remove_consumer removes it');

# Stamp can be set via constructor
my $stamped = Chalk::IR::Node->new(id => 's1', stamp => 'Int');
is($stamped->stamp(), 'Int', 'stamp is set from constructor');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-node-base.t`
Expected: FAIL — `Can't locate Chalk/IR/Node.pm`

- [ ] **Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node.pm`:

```perl
# ABOUTME: Base class for all IR nodes in the Chalk Sea of Nodes representation.
# ABOUTME: Provides id, inputs, consumers, stamp fields with use-def chain tracking.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node {
    field $id        :param :reader;
    field $inputs    :param :reader = [];
    field $consumers :reader        = [];
    field $stamp     :param :reader = undef;

    method add_consumer($node) {
        push $consumers->@*, $node;
    }

    method remove_consumer($node) {
        my $target_id = $node->id();
        $consumers->@* = grep { $_->id() ne $target_id } $consumers->@*;
    }

    method operation() {
        die "Subclass must implement operation()";
    }

    method content_hash() {
        my $op = $self->operation();
        my @input_ids = map { $_->id() } $inputs->@*;
        return $op . '|' . join('|', @input_ids);
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-node-base.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/Node.pm t/bootstrap/ir-node-base.t
git commit -m "feat: Chalk::IR::Node base class with use-def chains"
```

---

## Task 2: CFG Node Classes

**Files:**
- Create: `lib/Chalk/IR/Node/Start.pm`, `lib/Chalk/IR/Node/Return.pm`,
  `lib/Chalk/IR/Node/Unwind.pm`, `lib/Chalk/IR/Node/If.pm`,
  `lib/Chalk/IR/Node/Proj.pm`, `lib/Chalk/IR/Node/Region.pm`,
  `lib/Chalk/IR/Node/Loop.pm`
- Test: `t/bootstrap/ir-node-cfg.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-node-cfg.t`:

```perl
# ABOUTME: Tests for Chalk::IR CFG node classes.
# ABOUTME: Verifies Start, Return, Unwind, If, Proj, Region, Loop.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Loop;

# Start
my $start = Chalk::IR::Node::Start->new(id => 'start_0');
isa_ok($start, 'Chalk::IR::Node::Start');
isa_ok($start, 'Chalk::IR::Node');
is($start->operation(), 'Start', 'Start operation');

# Return
my $val = Chalk::IR::Node->new(id => 'val_0');
my $ret = Chalk::IR::Node::Return->new(id => 'ret_0', inputs => [$start, $val]);
is($ret->operation(), 'Return', 'Return operation');
is(scalar $ret->inputs()->@*, 2, 'Return has control + value inputs');

# Unwind (exceptional exit for die)
my $exc = Chalk::IR::Node->new(id => 'exc_0');
my $unwind = Chalk::IR::Node::Unwind->new(id => 'unw_0', inputs => [$start, $exc]);
is($unwind->operation(), 'Unwind', 'Unwind operation');
isa_ok($unwind, 'Chalk::IR::Node');

# If
my $cond = Chalk::IR::Node->new(id => 'cond_0');
my $if = Chalk::IR::Node::If->new(id => 'if_0', inputs => [$start, $cond]);
is($if->operation(), 'If', 'If operation');

# Proj
my $proj = Chalk::IR::Node::Proj->new(id => 'proj_0', inputs => [$if], index => 0);
is($proj->operation(), 'Proj', 'Proj operation');
is($proj->index(), 0, 'Proj index');

# Region
my $proj2 = Chalk::IR::Node::Proj->new(id => 'proj_1', inputs => [$if], index => 1);
my $region = Chalk::IR::Node::Region->new(id => 'reg_0', inputs => [$proj, $proj2]);
is($region->operation(), 'Region', 'Region operation');

# Loop
my $loop = Chalk::IR::Node::Loop->new(id => 'loop_0', inputs => [$start, undef]);
is($loop->operation(), 'Loop', 'Loop operation');

# Loop backedge mutation
my $back = Chalk::IR::Node->new(id => 'back_0');
$loop->set_backedge_ctrl($back);
is($loop->inputs()->[1]->id(), 'back_0', 'Loop backedge set');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-node-cfg.t`
Expected: FAIL — `Can't locate Chalk/IR/Node/Start.pm`

- [ ] **Step 3: Write minimal implementation**

Create each CFG node. All follow the same pattern. Example for Start:

`lib/Chalk/IR/Node/Start.pm`:
```perl
# ABOUTME: CFG entry point node for a Chalk computation graph.
# ABOUTME: Has no inputs; produces the initial control token.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Start :isa(Chalk::IR::Node) {
    method operation() { 'Start' }
}
```

`lib/Chalk/IR/Node/Return.pm`:
```perl
# ABOUTME: CFG normal exit node carrying a return value.
# ABOUTME: Inputs: [control, value]. Terminates the graph's normal path.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Return :isa(Chalk::IR::Node) {
    method operation() { 'Return' }
}
```

`lib/Chalk/IR/Node/Unwind.pm`:
```perl
# ABOUTME: CFG exceptional exit node for die/throw.
# ABOUTME: Inputs: [control, exception_value]. Terminates the exceptional path.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Unwind :isa(Chalk::IR::Node) {
    method operation() { 'Unwind' }
}
```

`lib/Chalk/IR/Node/If.pm`:
```perl
# ABOUTME: CFG conditional branch node.
# ABOUTME: Inputs: [control, condition]. Produces two outputs via Proj nodes.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::If :isa(Chalk::IR::Node) {
    method operation() { 'If' }
}
```

`lib/Chalk/IR/Node/Proj.pm`:
```perl
# ABOUTME: Projects one output from a multi-output node (e.g. true/false from If).
# ABOUTME: Carries an index selecting which output.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Proj :isa(Chalk::IR::Node) {
    field $index :param :reader;

    method operation() { 'Proj' }
}
```

`lib/Chalk/IR/Node/Region.pm`:
```perl
# ABOUTME: CFG merge point where multiple control flow paths converge.
# ABOUTME: Inputs are control tokens from each incoming path.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Region :isa(Chalk::IR::Node) {
    method operation() { 'Region' }
}
```

`lib/Chalk/IR/Node/Loop.pm`:
```perl
# ABOUTME: CFG loop header with entry and backedge control inputs.
# ABOUTME: Phi nodes at a Loop select between initial and loop-carried values.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Loop :isa(Chalk::IR::Node) {
    method operation() { 'Loop' }

    method set_backedge_ctrl($ctrl) {
        $self->inputs()->[1] = $ctrl;
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-node-cfg.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Start.pm lib/Chalk/IR/Node/Return.pm \
        lib/Chalk/IR/Node/Unwind.pm lib/Chalk/IR/Node/If.pm \
        lib/Chalk/IR/Node/Proj.pm lib/Chalk/IR/Node/Region.pm \
        lib/Chalk/IR/Node/Loop.pm t/bootstrap/ir-node-cfg.t
git commit -m "feat: Chalk::IR CFG node classes (Start, Return, Unwind, If, Proj, Region, Loop)"
```

---

## Task 3: BinOp Base Class and Leaf Nodes

**Files:**
- Create: `lib/Chalk/IR/Node/BinOp.pm` and 29 leaf files
- Test: `t/bootstrap/ir-node-binop.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-node-binop.t`:

```perl
# ABOUTME: Tests for Chalk::IR::Node::BinOp hierarchy.
# ABOUTME: Verifies intermediate base class accessors and all 29 leaf node types.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Power;
use Chalk::IR::Node::Concat;
use Chalk::IR::Node::NumEq;
use Chalk::IR::Node::NumNe;
use Chalk::IR::Node::NumLt;
use Chalk::IR::Node::NumGt;
use Chalk::IR::Node::NumLe;
use Chalk::IR::Node::NumGe;
use Chalk::IR::Node::NumCmp;
use Chalk::IR::Node::StrEq;
use Chalk::IR::Node::StrNe;
use Chalk::IR::Node::StrLt;
use Chalk::IR::Node::StrGt;
use Chalk::IR::Node::StrLe;
use Chalk::IR::Node::StrGe;
use Chalk::IR::Node::StrCmp;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::BitAnd;
use Chalk::IR::Node::BitOr;
use Chalk::IR::Node::BitXor;
use Chalk::IR::Node::LeftShift;
use Chalk::IR::Node::RightShift;
use Chalk::IR::Node::Assign;

my $left  = Chalk::IR::Node->new(id => 'left_0');
my $right = Chalk::IR::Node->new(id => 'right_0');

# BinOp base class accessors via Add
my $add = Chalk::IR::Node::Add->new(id => 'add_0', inputs => [$left, $right]);
isa_ok($add, 'Chalk::IR::Node::BinOp', 'Add isa BinOp');
isa_ok($add, 'Chalk::IR::Node', 'Add isa Node');
is($add->left()->id(), 'left_0', 'left() returns inputs->[0]');
is($add->right()->id(), 'right_0', 'right() returns inputs->[1]');
is($add->operation(), 'Add', 'Add operation');
is($add->op_str(), '+', 'Add op_str is +');

# content_hash includes operation name
like($add->content_hash(), qr/^Add\|/, 'Add content_hash starts with Add');

# Verify all 29 leaf types: operation, op_str, isa BinOp
my %expected = (
    Add        => '+',   Subtract   => '-',   Multiply => '*',
    Divide     => '/',   Modulo     => '%',   Power    => '**',
    Concat     => '.',
    NumEq      => '==',  NumNe      => '!=',  NumLt    => '<',
    NumGt      => '>',   NumLe      => '<=',  NumGe    => '>=',
    NumCmp     => '<=>',
    StrEq      => 'eq',  StrNe      => 'ne',  StrLt    => 'lt',
    StrGt      => 'gt',  StrLe      => 'le',  StrGe    => 'ge',
    StrCmp     => 'cmp',
    And        => '&&',  Or         => '||',
    BitAnd     => '&',   BitOr      => '|',   BitXor   => '^',
    LeftShift  => '<<',  RightShift => '>>',
    Assign     => '=',
);

for my $type (sort keys %expected) {
    my $class = "Chalk::IR::Node::$type";
    my $node = $class->new(id => "${type}_test", inputs => [$left, $right]);
    isa_ok($node, 'Chalk::IR::Node::BinOp', "$type isa BinOp");
    is($node->operation(), $type, "$type operation");
    is($node->op_str(), $expected{$type}, "$type op_str is $expected{$type}");
}

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-node-binop.t`
Expected: FAIL — `Can't locate Chalk/IR/Node/BinOp.pm`

- [ ] **Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/BinOp.pm`:
```perl
# ABOUTME: Intermediate base class for binary operation IR nodes.
# ABOUTME: Provides left(), right(), and abstract op_str() accessors.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::BinOp :isa(Chalk::IR::Node) {
    method left()  { $self->inputs()->[0] }
    method right() { $self->inputs()->[1] }

    method op_str() {
        die "Subclass must implement op_str()";
    }
}
```

Each leaf node follows the same 10-line pattern. Example `lib/Chalk/IR/Node/Add.pm`:
```perl
# ABOUTME: Addition operation node in the Chalk IR.
# ABOUTME: Binary data node producing the sum of its inputs.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Add :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Add' }
    method op_str()    { '+' }
}
```

Create all 29 leaf files following this exact pattern with the
operation/op_str pairs from the `%expected` hash in the test. Each file
is 10 lines. The ABOUTME comments describe the specific operation (e.g.,
"Subtraction operation", "Numeric equality comparison", etc.).

Full list of files to create:
- `lib/Chalk/IR/Node/Add.pm` (op_str: `+`)
- `lib/Chalk/IR/Node/Subtract.pm` (op_str: `-`)
- `lib/Chalk/IR/Node/Multiply.pm` (op_str: `*`)
- `lib/Chalk/IR/Node/Divide.pm` (op_str: `/`)
- `lib/Chalk/IR/Node/Modulo.pm` (op_str: `%`)
- `lib/Chalk/IR/Node/Power.pm` (op_str: `**`)
- `lib/Chalk/IR/Node/Concat.pm` (op_str: `.`)
- `lib/Chalk/IR/Node/NumEq.pm` (op_str: `==`)
- `lib/Chalk/IR/Node/NumNe.pm` (op_str: `!=`)
- `lib/Chalk/IR/Node/NumLt.pm` (op_str: `<`)
- `lib/Chalk/IR/Node/NumGt.pm` (op_str: `>`)
- `lib/Chalk/IR/Node/NumLe.pm` (op_str: `<=`)
- `lib/Chalk/IR/Node/NumGe.pm` (op_str: `>=`)
- `lib/Chalk/IR/Node/NumCmp.pm` (op_str: `<=>`)
- `lib/Chalk/IR/Node/StrEq.pm` (op_str: `eq`)
- `lib/Chalk/IR/Node/StrNe.pm` (op_str: `ne`)
- `lib/Chalk/IR/Node/StrLt.pm` (op_str: `lt`)
- `lib/Chalk/IR/Node/StrGt.pm` (op_str: `gt`)
- `lib/Chalk/IR/Node/StrLe.pm` (op_str: `le`)
- `lib/Chalk/IR/Node/StrGe.pm` (op_str: `ge`)
- `lib/Chalk/IR/Node/StrCmp.pm` (op_str: `cmp`)
- `lib/Chalk/IR/Node/And.pm` (op_str: `&&`)
- `lib/Chalk/IR/Node/Or.pm` (op_str: `||`)
- `lib/Chalk/IR/Node/BitAnd.pm` (op_str: `&`)
- `lib/Chalk/IR/Node/BitOr.pm` (op_str: `|`)
- `lib/Chalk/IR/Node/BitXor.pm` (op_str: `^`)
- `lib/Chalk/IR/Node/LeftShift.pm` (op_str: `<<`)
- `lib/Chalk/IR/Node/RightShift.pm` (op_str: `>>`)
- `lib/Chalk/IR/Node/Assign.pm` (op_str: `=`)

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-node-binop.t`
Expected: All tests PASS (29 leaf types x 3 assertions each + BinOp accessor tests)

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/BinOp.pm lib/Chalk/IR/Node/Add.pm \
        lib/Chalk/IR/Node/Subtract.pm lib/Chalk/IR/Node/Multiply.pm \
        lib/Chalk/IR/Node/Divide.pm lib/Chalk/IR/Node/Modulo.pm \
        lib/Chalk/IR/Node/Power.pm lib/Chalk/IR/Node/Concat.pm \
        lib/Chalk/IR/Node/NumEq.pm lib/Chalk/IR/Node/NumNe.pm \
        lib/Chalk/IR/Node/NumLt.pm lib/Chalk/IR/Node/NumGt.pm \
        lib/Chalk/IR/Node/NumLe.pm lib/Chalk/IR/Node/NumGe.pm \
        lib/Chalk/IR/Node/NumCmp.pm lib/Chalk/IR/Node/StrEq.pm \
        lib/Chalk/IR/Node/StrNe.pm lib/Chalk/IR/Node/StrLt.pm \
        lib/Chalk/IR/Node/StrGt.pm lib/Chalk/IR/Node/StrLe.pm \
        lib/Chalk/IR/Node/StrGe.pm lib/Chalk/IR/Node/StrCmp.pm \
        lib/Chalk/IR/Node/And.pm lib/Chalk/IR/Node/Or.pm \
        lib/Chalk/IR/Node/BitAnd.pm lib/Chalk/IR/Node/BitOr.pm \
        lib/Chalk/IR/Node/BitXor.pm lib/Chalk/IR/Node/LeftShift.pm \
        lib/Chalk/IR/Node/RightShift.pm lib/Chalk/IR/Node/Assign.pm \
        t/bootstrap/ir-node-binop.t
git commit -m "feat: BinOp base class and 29 leaf node types with op_str()"
```

---

## Task 4: UnaryOp Base Class and Leaf Nodes

**Files:**
- Create: `lib/Chalk/IR/Node/UnaryOp.pm`, `lib/Chalk/IR/Node/Not.pm`,
  `lib/Chalk/IR/Node/Negate.pm`, `lib/Chalk/IR/Node/Complement.pm`,
  `lib/Chalk/IR/Node/Defined.pm`
- Test: `t/bootstrap/ir-node-unaryop.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-node-unaryop.t`:

```perl
# ABOUTME: Tests for Chalk::IR::Node::UnaryOp hierarchy.
# ABOUTME: Verifies intermediate base class accessors and all 4 leaf node types.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Complement;
use Chalk::IR::Node::Defined;

my $operand = Chalk::IR::Node->new(id => 'op_0');

# UnaryOp accessors via Not
my $not = Chalk::IR::Node::Not->new(id => 'not_0', inputs => [$operand]);
isa_ok($not, 'Chalk::IR::Node::UnaryOp', 'Not isa UnaryOp');
isa_ok($not, 'Chalk::IR::Node', 'Not isa Node');
is($not->operand()->id(), 'op_0', 'operand() returns inputs->[0]');
is($not->operation(), 'Not', 'Not operation');
is($not->op_str(), '!', 'Not op_str is !');

# Verify all 4 leaf types
my %expected = (
    Not        => '!',
    Negate     => '-',
    Complement => '~',
    Defined    => 'defined',
);

for my $type (sort keys %expected) {
    my $class = "Chalk::IR::Node::$type";
    my $node = $class->new(id => "${type}_test", inputs => [$operand]);
    isa_ok($node, 'Chalk::IR::Node::UnaryOp', "$type isa UnaryOp");
    is($node->operation(), $type, "$type operation");
    is($node->op_str(), $expected{$type}, "$type op_str");
}

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-node-unaryop.t`
Expected: FAIL — `Can't locate Chalk/IR/Node/UnaryOp.pm`

- [ ] **Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/UnaryOp.pm`:
```perl
# ABOUTME: Intermediate base class for unary operation IR nodes.
# ABOUTME: Provides operand() and abstract op_str() accessors.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::UnaryOp :isa(Chalk::IR::Node) {
    method operand() { $self->inputs()->[0] }

    method op_str() {
        die "Subclass must implement op_str()";
    }
}
```

Create 4 leaf files following same pattern as BinOp leaves:

`lib/Chalk/IR/Node/Not.pm`:
```perl
# ABOUTME: Logical negation operation node in the Chalk IR.
# ABOUTME: Unary data node producing the logical inverse of its operand.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Not :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Not' }
    method op_str()    { '!' }
}
```

Same pattern for Negate (`'-'`), Complement (`'~'`), Defined (`'defined'`).

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-node-unaryop.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/UnaryOp.pm lib/Chalk/IR/Node/Not.pm \
        lib/Chalk/IR/Node/Negate.pm lib/Chalk/IR/Node/Complement.pm \
        lib/Chalk/IR/Node/Defined.pm t/bootstrap/ir-node-unaryop.t
git commit -m "feat: UnaryOp base class and 4 leaf node types with op_str()"
```

---

## Task 5: Data and Access Nodes

**Files:**
- Create: `lib/Chalk/IR/Node/Constant.pm`, `lib/Chalk/IR/Node/Phi.pm`,
  `lib/Chalk/IR/Node/Access.pm`, `lib/Chalk/IR/Node/PadAccess.pm`,
  `lib/Chalk/IR/Node/FieldAccess.pm`, `lib/Chalk/IR/Node/StashAccess.pm`,
  `lib/Chalk/IR/Node/Subscript.pm`
- Test: `t/bootstrap/ir-node-data.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-node-data.t`:

```perl
# ABOUTME: Tests for Chalk::IR data and access node classes.
# ABOUTME: Verifies Constant, Phi, PadAccess, FieldAccess, StashAccess, Subscript.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Access;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::FieldAccess;
use Chalk::IR::Node::StashAccess;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::Region;

# Constant
my $c = Chalk::IR::Node::Constant->new(
    id => 'c_0', value => '42', stamp => 'Int', const_type => 'integer',
);
is($c->operation(), 'Constant', 'Constant operation');
is($c->value(), '42', 'Constant value');
is($c->const_type(), 'integer', 'Constant const_type');
is($c->stamp(), 'Int', 'Constant stamp');
like($c->content_hash(), qr/Constant\|value=42/, 'Constant content_hash includes value');

# Constant with undef value
my $undef_c = Chalk::IR::Node::Constant->new(
    id => 'c_u', value => undef, stamp => 'Undef', const_type => 'string',
);
like($undef_c->content_hash(), qr/value=undef/, 'undef value in content_hash');

# Phi
my $region = Chalk::IR::Node::Region->new(id => 'reg_0', inputs => []);
my $v1 = Chalk::IR::Node->new(id => 'v1');
my $v2 = Chalk::IR::Node->new(id => 'v2');
my $phi = Chalk::IR::Node::Phi->new(
    id => 'phi_0', region => $region, inputs => [$v1, $v2],
);
is($phi->operation(), 'Phi', 'Phi operation');
is($phi->region()->id(), 'reg_0', 'Phi region');
like($phi->content_hash(), qr/Phi\|region=reg_0/, 'Phi content_hash includes region');

# Phi set_backedge
my $v3 = Chalk::IR::Node->new(id => 'v3');
$phi->set_backedge($v3);
is($phi->inputs()->[1]->id(), 'v3', 'Phi backedge updated');

# PadAccess
my $pad = Chalk::IR::Node::PadAccess->new(
    id => 'pad_0', targ => 3, varname => '$x',
);
isa_ok($pad, 'Chalk::IR::Node::Access', 'PadAccess isa Access');
is($pad->operation(), 'PadAccess', 'PadAccess operation');
is($pad->targ(), 3, 'PadAccess targ');
is($pad->varname(), '$x', 'PadAccess varname');
like($pad->content_hash(), qr/PadAccess\|targ=3\|varname=\$x/,
    'PadAccess content_hash');

# FieldAccess
my $fa = Chalk::IR::Node::FieldAccess->new(
    id => 'fa_0', field_index => 0, field_stash => 'MyClass',
);
isa_ok($fa, 'Chalk::IR::Node::Access', 'FieldAccess isa Access');
is($fa->operation(), 'FieldAccess', 'FieldAccess operation');
is($fa->field_index(), 0, 'FieldAccess field_index');
is($fa->field_stash(), 'MyClass', 'FieldAccess field_stash');

# StashAccess
my $sa = Chalk::IR::Node::StashAccess->new(id => 'sa_0');
isa_ok($sa, 'Chalk::IR::Node::Access', 'StashAccess isa Access');
is($sa->operation(), 'StashAccess', 'StashAccess operation');

# Subscript
my $target = Chalk::IR::Node->new(id => 'tgt_0');
my $index  = Chalk::IR::Node->new(id => 'idx_0');
my $sub = Chalk::IR::Node::Subscript->new(
    id => 'sub_0', inputs => [$target, $index],
);
isa_ok($sub, 'Chalk::IR::Node::Access', 'Subscript isa Access');
is($sub->operation(), 'Subscript', 'Subscript operation');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-node-data.t`
Expected: FAIL — `Can't locate Chalk/IR/Node/Constant.pm`

- [ ] **Step 3: Write minimal implementation**

`lib/Chalk/IR/Node/Constant.pm`:
```perl
# ABOUTME: Compile-time constant value node in the Chalk IR.
# ABOUTME: Stores value, stamp (type), and const_type (string/integer/variable/enum).
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Constant :isa(Chalk::IR::Node) {
    field $value      :param :reader;
    field $const_type :param :reader = 'string';

    method operation() { 'Constant' }

    method content_hash() {
        return "Constant|value=" . (defined $value ? $value : 'undef');
    }
}
```

`lib/Chalk/IR/Node/Phi.pm`:
```perl
# ABOUTME: Value selection node at Region or Loop merge points.
# ABOUTME: Selects among incoming values based on which control path was taken.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Phi :isa(Chalk::IR::Node) {
    field $region :param :reader;

    method operation() { 'Phi' }

    method content_hash() {
        my @input_ids = map { $_->id() } $self->inputs()->@*;
        return "Phi|region=" . $region->id()
             . "|" . join('|', @input_ids);
    }

    method set_backedge($value) {
        $self->inputs()->[1] = $value;
    }
}
```

`lib/Chalk/IR/Node/Access.pm`:
```perl
# ABOUTME: Intermediate base class for variable/field/subscript access nodes.
# ABOUTME: Groups PadAccess, FieldAccess, StashAccess, Subscript.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Access :isa(Chalk::IR::Node) {
}
```

`lib/Chalk/IR/Node/PadAccess.pm`:
```perl
# ABOUTME: Lexical variable access node in the Chalk IR.
# ABOUTME: Identifies a pad slot by targ index and variable name.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::PadAccess :isa(Chalk::IR::Node::Access) {
    field $targ    :param :reader;
    field $varname :param :reader;

    method operation() { 'PadAccess' }

    method content_hash() {
        my @input_ids = map { $_->id() } $self->inputs()->@*;
        return "PadAccess|targ=" . $targ
             . "|varname=" . $varname
             . "|" . join('|', @input_ids);
    }
}
```

`lib/Chalk/IR/Node/FieldAccess.pm`:
```perl
# ABOUTME: Class field access node in the Chalk IR.
# ABOUTME: Identifies a field by its index and stash (class name).
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::FieldAccess :isa(Chalk::IR::Node::Access) {
    field $field_index :param :reader;
    field $field_stash :param :reader;

    method operation() { 'FieldAccess' }

    method content_hash() {
        my @input_ids = map { $_->id() } $self->inputs()->@*;
        return "FieldAccess|field_index=" . $field_index
             . "|field_stash=" . $field_stash
             . "|" . join('|', @input_ids);
    }
}
```

`lib/Chalk/IR/Node/StashAccess.pm`:
```perl
# ABOUTME: Package-level variable access node in the Chalk IR.
# ABOUTME: Accesses variables in the package stash.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::StashAccess :isa(Chalk::IR::Node::Access) {
    method operation() { 'StashAccess' }
}
```

`lib/Chalk/IR/Node/Subscript.pm`:
```perl
# ABOUTME: Array/hash element access node in the Chalk IR.
# ABOUTME: Binary data node taking a container and index.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Subscript :isa(Chalk::IR::Node::Access) {
    method operation() { 'Subscript' }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-node-data.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Constant.pm lib/Chalk/IR/Node/Phi.pm \
        lib/Chalk/IR/Node/Access.pm lib/Chalk/IR/Node/PadAccess.pm \
        lib/Chalk/IR/Node/FieldAccess.pm lib/Chalk/IR/Node/StashAccess.pm \
        lib/Chalk/IR/Node/Subscript.pm t/bootstrap/ir-node-data.t
git commit -m "feat: Constant, Phi, and Access node hierarchy"
```

---

## Task 6: Call, Aggregate, and Remaining Computation Nodes

**Files:**
- Create: `lib/Chalk/IR/Node/Call.pm`, `lib/Chalk/IR/Node/Aggregate.pm`,
  `lib/Chalk/IR/Node/HashRef.pm`, `lib/Chalk/IR/Node/ArrayRef.pm`,
  `lib/Chalk/IR/Node/Interpolate.pm`, `lib/Chalk/IR/Node/AnonSub.pm`,
  `lib/Chalk/IR/Node/Regex.pm`, `lib/Chalk/IR/Node/RegexMatch.pm`,
  `lib/Chalk/IR/Node/RegexSubst.pm`, `lib/Chalk/IR/Node/TryCatch.pm`,
  `lib/Chalk/IR/Node/PostfixDeref.pm`, `lib/Chalk/IR/Node/CompoundAssign.pm`,
  `lib/Chalk/IR/Node/BacktickExpr.pm`, `lib/Chalk/IR/Node/VarDecl.pm`
- Test: `t/bootstrap/ir-node-misc.t` (renamed from planned ir-node-data.t part 2)

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-node-misc.t`:

```perl
# ABOUTME: Tests for Call, Aggregate, Regex, and remaining computation nodes.
# ABOUTME: Verifies all non-BinOp/UnaryOp/Access computation node types.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Aggregate;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::AnonSub;
use Chalk::IR::Node::Regex;
use Chalk::IR::Node::RegexMatch;
use Chalk::IR::Node::RegexSubst;
use Chalk::IR::Node::TryCatch;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::BacktickExpr;
use Chalk::IR::Node::VarDecl;

# Call
my $arg = Chalk::IR::Node->new(id => 'arg_0');
my $call = Chalk::IR::Node::Call->new(
    id => 'call_0', dispatch_kind => 'method', name => 'foo',
    inputs => [$arg],
);
is($call->operation(), 'Call', 'Call operation');
is($call->dispatch_kind(), 'method', 'Call dispatch_kind');
is($call->name(), 'foo', 'Call name');
like($call->content_hash(), qr/Call\|dispatch_kind=method\|name=foo/,
    'Call content_hash');

# Aggregate hierarchy
my $hr = Chalk::IR::Node::HashRef->new(id => 'hr_0', inputs => []);
isa_ok($hr, 'Chalk::IR::Node::Aggregate', 'HashRef isa Aggregate');
is($hr->operation(), 'HashRef', 'HashRef operation');

my $ar = Chalk::IR::Node::ArrayRef->new(id => 'ar_0', inputs => []);
isa_ok($ar, 'Chalk::IR::Node::Aggregate', 'ArrayRef isa Aggregate');
is($ar->operation(), 'ArrayRef', 'ArrayRef operation');

my $interp = Chalk::IR::Node::Interpolate->new(id => 'int_0', inputs => []);
isa_ok($interp, 'Chalk::IR::Node::Aggregate', 'Interpolate isa Aggregate');
is($interp->operation(), 'Interpolate', 'Interpolate operation');

# AnonSub (holds a nested graph reference — tested more in ir-graph.t)
my $anon = Chalk::IR::Node::AnonSub->new(id => 'anon_0', graph => undef);
is($anon->operation(), 'AnonSub', 'AnonSub operation');
is($anon->graph(), undef, 'AnonSub graph initially undef');

# Regex hierarchy
my $rm = Chalk::IR::Node::RegexMatch->new(
    id => 'rm_0', inputs => [], flags => 'gi',
);
isa_ok($rm, 'Chalk::IR::Node::Regex', 'RegexMatch isa Regex');
is($rm->operation(), 'RegexMatch', 'RegexMatch operation');
is($rm->flags(), 'gi', 'RegexMatch flags');

my $rs = Chalk::IR::Node::RegexSubst->new(
    id => 'rs_0', inputs => [], flags => 's',
);
isa_ok($rs, 'Chalk::IR::Node::Regex', 'RegexSubst isa Regex');
is($rs->operation(), 'RegexSubst', 'RegexSubst operation');

# TryCatch
my $tc = Chalk::IR::Node::TryCatch->new(id => 'tc_0', inputs => []);
is($tc->operation(), 'TryCatch', 'TryCatch operation');

# PostfixDeref
my $pd = Chalk::IR::Node::PostfixDeref->new(
    id => 'pd_0', inputs => [], sigil => '@',
);
is($pd->operation(), 'PostfixDeref', 'PostfixDeref operation');
is($pd->sigil(), '@', 'PostfixDeref sigil');

# CompoundAssign
my $ca = Chalk::IR::Node::CompoundAssign->new(
    id => 'ca_0', inputs => [], op => '+=',
);
is($ca->operation(), 'CompoundAssign', 'CompoundAssign operation');
is($ca->op(), '+=', 'CompoundAssign op');

# BacktickExpr
my $bt = Chalk::IR::Node::BacktickExpr->new(id => 'bt_0', inputs => []);
is($bt->operation(), 'BacktickExpr', 'BacktickExpr operation');

# VarDecl
my $vd = Chalk::IR::Node::VarDecl->new(id => 'vd_0', inputs => []);
is($vd->operation(), 'VarDecl', 'VarDecl operation');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-node-misc.t`
Expected: FAIL — `Can't locate Chalk/IR/Node/Call.pm`

- [ ] **Step 3: Write minimal implementation**

`lib/Chalk/IR/Node/Call.pm`:
```perl
# ABOUTME: Method, subroutine, or builtin call node in the Chalk IR.
# ABOUTME: Carries dispatch kind (method/sub/builtin) and callee name.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Call :isa(Chalk::IR::Node) {
    field $dispatch_kind :param :reader;
    field $name          :param :reader;

    method operation() { 'Call' }

    method content_hash() {
        my @input_ids = map { $_->id() } $self->inputs()->@*;
        return "Call|dispatch_kind=" . $dispatch_kind
             . "|name=" . $name
             . "|" . join('|', @input_ids);
    }
}
```

`lib/Chalk/IR/Node/Aggregate.pm`:
```perl
# ABOUTME: Intermediate base class for collection constructor nodes.
# ABOUTME: Groups HashRef, ArrayRef, and Interpolate.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Aggregate :isa(Chalk::IR::Node) {
}
```

`lib/Chalk/IR/Node/HashRef.pm`:
```perl
# ABOUTME: Hash reference constructor node in the Chalk IR.
# ABOUTME: Inputs are key-value pairs.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::HashRef :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'HashRef' }
}
```

`lib/Chalk/IR/Node/ArrayRef.pm`:
```perl
# ABOUTME: Array reference constructor node in the Chalk IR.
# ABOUTME: Inputs are array elements.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::ArrayRef :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'ArrayRef' }
}
```

`lib/Chalk/IR/Node/Interpolate.pm`:
```perl
# ABOUTME: String interpolation node in the Chalk IR.
# ABOUTME: Inputs are the parts (literal strings and expressions).
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Interpolate :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'Interpolate' }
}
```

`lib/Chalk/IR/Node/AnonSub.pm`:
```perl
# ABOUTME: Anonymous subroutine (closure) node in the Chalk IR.
# ABOUTME: Holds a nested Chalk::IR::Graph for the sub body.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::AnonSub :isa(Chalk::IR::Node) {
    field $graph :param :reader = undef;

    method operation() { 'AnonSub' }
}
```

`lib/Chalk/IR/Node/Regex.pm`:
```perl
# ABOUTME: Intermediate base class for regex operation nodes.
# ABOUTME: Groups RegexMatch and RegexSubst.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Regex :isa(Chalk::IR::Node) {
    field $flags :param :reader = '';
}
```

`lib/Chalk/IR/Node/RegexMatch.pm`:
```perl
# ABOUTME: Regex match operation node in the Chalk IR.
# ABOUTME: Matches a pattern against a target string.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::RegexMatch :isa(Chalk::IR::Node::Regex) {
    method operation() { 'RegexMatch' }
}
```

`lib/Chalk/IR/Node/RegexSubst.pm`:
```perl
# ABOUTME: Regex substitution operation node in the Chalk IR.
# ABOUTME: Replaces matches of a pattern in a target string.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::RegexSubst :isa(Chalk::IR::Node::Regex) {
    method operation() { 'RegexSubst' }
}
```

`lib/Chalk/IR/Node/TryCatch.pm`:
```perl
# ABOUTME: Try/catch statement node in the Chalk IR.
# ABOUTME: Holds try body, catch variable, and catch body until exception flow design lowers it.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::TryCatch :isa(Chalk::IR::Node) {
    method operation() { 'TryCatch' }
}
```

`lib/Chalk/IR/Node/PostfixDeref.pm`:
```perl
# ABOUTME: Postfix dereference node in the Chalk IR (->@*, ->%*, etc.).
# ABOUTME: Carries a sigil indicating the dereference type.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::PostfixDeref :isa(Chalk::IR::Node) {
    field $sigil :param :reader;

    method operation() { 'PostfixDeref' }
}
```

`lib/Chalk/IR/Node/CompoundAssign.pm`:
```perl
# ABOUTME: Compound assignment node in the Chalk IR (+=, .=, etc.).
# ABOUTME: Carries the compound operator string.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::CompoundAssign :isa(Chalk::IR::Node) {
    field $op :param :reader;

    method operation() { 'CompoundAssign' }
}
```

`lib/Chalk/IR/Node/BacktickExpr.pm`:
```perl
# ABOUTME: Backtick command execution node in the Chalk IR.
# ABOUTME: Executes a shell command and returns its output.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::BacktickExpr :isa(Chalk::IR::Node) {
    method operation() { 'BacktickExpr' }
}
```

`lib/Chalk/IR/Node/VarDecl.pm`:
```perl
# ABOUTME: Variable declaration node in the Chalk IR.
# ABOUTME: Allocates a pad slot and optionally initializes it.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::VarDecl :isa(Chalk::IR::Node) {
    method operation() { 'VarDecl' }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-node-misc.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Call.pm lib/Chalk/IR/Node/Aggregate.pm \
        lib/Chalk/IR/Node/HashRef.pm lib/Chalk/IR/Node/ArrayRef.pm \
        lib/Chalk/IR/Node/Interpolate.pm lib/Chalk/IR/Node/AnonSub.pm \
        lib/Chalk/IR/Node/Regex.pm lib/Chalk/IR/Node/RegexMatch.pm \
        lib/Chalk/IR/Node/RegexSubst.pm lib/Chalk/IR/Node/TryCatch.pm \
        lib/Chalk/IR/Node/PostfixDeref.pm lib/Chalk/IR/Node/CompoundAssign.pm \
        lib/Chalk/IR/Node/BacktickExpr.pm lib/Chalk/IR/Node/VarDecl.pm \
        t/bootstrap/ir-node-misc.t
git commit -m "feat: Call, Aggregate, Regex, and remaining computation nodes"
```

---

## Task 7: NodeFactory with Hash Consing

**Files:**
- Create: `lib/Chalk/IR/NodeFactory.pm`
- Test: `t/bootstrap/ir-node-factory.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-node-factory.t`:

```perl
# ABOUTME: Tests for Chalk::IR::NodeFactory hash consing and node creation.
# ABOUTME: Verifies make/make_cfg, deduplication, and CFG uniqueness.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;

my $f = Chalk::IR::NodeFactory->new();

# make() creates data nodes with hash consing
my $c1 = $f->make('Constant', value => '42', const_type => 'integer');
isa_ok($c1, 'Chalk::IR::Node::Constant');
is($c1->value(), '42', 'Constant value');

# Same arguments return same object (hash consing)
my $c2 = $f->make('Constant', value => '42', const_type => 'integer');
ok($c1 == $c2, 'identical Constants are same object');

# Different values produce different objects
my $c3 = $f->make('Constant', value => '99', const_type => 'integer');
ok($c1 != $c3, 'different Constants are different objects');

# BinOp nodes via make()
my $left  = $f->make('Constant', value => '1', const_type => 'integer');
my $right = $f->make('Constant', value => '2', const_type => 'integer');
my $add = $f->make('Add', inputs => [$left, $right]);
isa_ok($add, 'Chalk::IR::Node::Add');
isa_ok($add, 'Chalk::IR::Node::BinOp');
is($add->left(), $left, 'Add left is correct');
is($add->right(), $right, 'Add right is correct');

# Same Add is hash-consed
my $add2 = $f->make('Add', inputs => [$left, $right]);
ok($add == $add2, 'identical Add nodes are same object');

# make_cfg() creates unique CFG nodes
my $start1 = $f->make_cfg('Start');
my $start2 = $f->make_cfg('Start');
isa_ok($start1, 'Chalk::IR::Node::Start');
ok($start1 != $start2, 'CFG nodes are always unique');

# make_cfg with inputs
my $cond = $f->make('Constant', value => 'true', const_type => 'string');
my $if = $f->make_cfg('If', inputs => [$start1, $cond]);
isa_ok($if, 'Chalk::IR::Node::If');

# Proj with index
my $proj = $f->make_cfg('Proj', inputs => [$if], index => 0);
isa_ok($proj, 'Chalk::IR::Node::Proj');
is($proj->index(), 0, 'Proj index preserved');

# Return
my $ret = $f->make_cfg('Return', inputs => [$start1, $c1]);
isa_ok($ret, 'Chalk::IR::Node::Return');

# Unwind
my $unw = $f->make_cfg('Unwind', inputs => [$start1, $c1]);
isa_ok($unw, 'Chalk::IR::Node::Unwind');

# Call node
my $call = $f->make('Call',
    dispatch_kind => 'builtin', name => 'push', inputs => [$c1],
);
isa_ok($call, 'Chalk::IR::Node::Call');
is($call->dispatch_kind(), 'builtin');
is($call->name(), 'push');

# PadAccess
my $pad = $f->make('PadAccess', targ => 0, varname => '$x');
isa_ok($pad, 'Chalk::IR::Node::PadAccess');

# FieldAccess
my $fa = $f->make('FieldAccess', field_index => 1, field_stash => 'Foo');
isa_ok($fa, 'Chalk::IR::Node::FieldAccess');

# Consumer registration
is(scalar $left->consumers()->@*, 1, 'left has 1 consumer (add)');
is($left->consumers()->[0], $add, 'left consumer is add');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-node-factory.t`
Expected: FAIL — `Can't locate Chalk/IR/NodeFactory.pm`

- [ ] **Step 3: Write minimal implementation**

Create `lib/Chalk/IR/NodeFactory.pm`:

```perl
# ABOUTME: Factory for Chalk IR nodes with hash consing for data nodes.
# ABOUTME: make() deduplicates data nodes by content hash; make_cfg() creates unique CFG nodes.
use 5.42.0;
use utf8;
use experimental 'class';

# Load all node classes
use Chalk::IR::Node;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Power;
use Chalk::IR::Node::Concat;
use Chalk::IR::Node::NumEq;
use Chalk::IR::Node::NumNe;
use Chalk::IR::Node::NumLt;
use Chalk::IR::Node::NumGt;
use Chalk::IR::Node::NumLe;
use Chalk::IR::Node::NumGe;
use Chalk::IR::Node::NumCmp;
use Chalk::IR::Node::StrEq;
use Chalk::IR::Node::StrNe;
use Chalk::IR::Node::StrLt;
use Chalk::IR::Node::StrGt;
use Chalk::IR::Node::StrLe;
use Chalk::IR::Node::StrGe;
use Chalk::IR::Node::StrCmp;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::BitAnd;
use Chalk::IR::Node::BitOr;
use Chalk::IR::Node::BitXor;
use Chalk::IR::Node::LeftShift;
use Chalk::IR::Node::RightShift;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Complement;
use Chalk::IR::Node::Defined;
use Chalk::IR::Node::Access;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::FieldAccess;
use Chalk::IR::Node::StashAccess;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Aggregate;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::AnonSub;
use Chalk::IR::Node::Regex;
use Chalk::IR::Node::RegexMatch;
use Chalk::IR::Node::RegexSubst;
use Chalk::IR::Node::TryCatch;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::BacktickExpr;
use Chalk::IR::Node::VarDecl;

class Chalk::IR::NodeFactory {
    my %DATA_CLASSES = map { $_ => "Chalk::IR::Node::$_" } qw(
        Constant Phi
        Add Subtract Multiply Divide Modulo Power Concat
        NumEq NumNe NumLt NumGt NumLe NumGe NumCmp
        StrEq StrNe StrLt StrGt StrLe StrGe StrCmp
        And Or BitAnd BitOr BitXor LeftShift RightShift
        Assign Not Negate Complement Defined
        PadAccess FieldAccess StashAccess Subscript
        Call HashRef ArrayRef Interpolate AnonSub
        RegexMatch RegexSubst TryCatch
        PostfixDeref CompoundAssign BacktickExpr VarDecl
    );

    my %CFG_CLASSES = map { $_ => "Chalk::IR::Node::$_" } qw(
        Start Return Unwind If Proj Region Loop
    );

    field %cache;
    field $cfg_counter = 0;

    method make($op_name, %args) {
        my $node_class = $DATA_CLASSES{$op_name}
            // die "Unknown data node type: $op_name";

        my $node = $node_class->new(id => '_tmp', %args);
        my $hash = $node->content_hash();

        if (exists $cache{$hash}) {
            return $cache{$hash};
        }

        # Re-create with the content hash as the stable id
        $node = $node_class->new(id => $hash, %args);

        # Register as consumer of inputs
        my $inputs = $args{inputs} // [];
        for my $input ($inputs->@*) {
            next unless defined $input;
            if (ref($input) eq 'ARRAY') {
                for my $elem ($input->@*) {
                    $elem->add_consumer($node) if defined $elem;
                }
            } else {
                $input->add_consumer($node);
            }
        }

        $cache{$hash} = $node;
        return $node;
    }

    method make_cfg($op_name, %args) {
        my $node_class = $CFG_CLASSES{$op_name}
            // die "Unknown CFG node type: $op_name";

        $cfg_counter++;
        my $id = "${op_name}#${cfg_counter}";
        my $node = $node_class->new(id => $id, %args);

        # Register as consumer of inputs
        my $inputs = $args{inputs} // [];
        for my $input ($inputs->@*) {
            next unless defined $input;
            $input->add_consumer($node);
        }

        return $node;
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-node-factory.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/NodeFactory.pm t/bootstrap/ir-node-factory.t
git commit -m "feat: Chalk::IR::NodeFactory with hash consing and CFG creation"
```

---

## Task 8: Graph Container

**Files:**
- Create: `lib/Chalk/IR/Graph.pm`
- Test: `t/bootstrap/ir-graph.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-graph.t`:

```perl
# ABOUTME: Tests for Chalk::IR::Graph container.
# ABOUTME: Verifies start/returns fields, topological sort, and node lookup.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;

my $f = Chalk::IR::NodeFactory->new();

# Build a simple graph: Start → Add(Const(1), Const(2)) → Return
my $start = $f->make_cfg('Start');
my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
my $add = $f->make('Add', inputs => [$c1, $c2]);
my $ret = $f->make_cfg('Return', inputs => [$start, $add]);

my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);
isa_ok($graph, 'Chalk::IR::Graph');
is($graph->start(), $start, 'graph start');
is(scalar $graph->returns()->@*, 1, 'graph has one return');

# Topological sort: all nodes reachable
my $nodes = $graph->nodes();
ok(scalar $nodes->@* >= 4, 'nodes() finds at least 4 nodes');

# All node types present
my %ops = map { $_->operation() => 1 } $nodes->@*;
ok($ops{Start}, 'Start in topo sort');
ok($ops{Constant}, 'Constant in topo sort');
ok($ops{Add}, 'Add in topo sort');
ok($ops{Return}, 'Return in topo sort');

# Topological order: inputs before consumers
# Find Add and its inputs in the order
my %pos;
for my $i (0 .. $nodes->$#*) {
    $pos{$nodes->[$i]->id()} = $i;
}
ok($pos{$c1->id()} < $pos{$add->id()}, 'Const(1) before Add');
ok($pos{$c2->id()} < $pos{$add->id()}, 'Const(2) before Add');

# Graph with Unwind (dual exits)
my $exc = $f->make('Constant', value => 'error', const_type => 'string');
my $unw = $f->make_cfg('Unwind', inputs => [$start, $exc]);
my $graph2 = Chalk::IR::Graph->new(
    start => $start, returns => [$ret, $unw],
);
is(scalar $graph2->returns()->@*, 2, 'graph with normal + exceptional exit');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-graph.t`
Expected: FAIL — `Can't locate Chalk/IR/Graph.pm`

- [ ] **Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Graph.pm`:

```perl
# ABOUTME: Container for a complete Chalk computation graph.
# ABOUTME: Holds Start/Return/Unwind nodes and provides topological iteration.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Graph {
    field $start   :param :reader;
    field $returns :param :reader = [];

    method nodes() {
        my @order;
        my %visited;

        # BFS to find all reachable nodes
        my @worklist = ($start, $returns->@*);
        my @all;
        my %seen;
        while (my $node = shift @worklist) {
            next unless defined $node;
            next if $seen{$node->id()}++;
            push @all, $node;
            push @worklist, $node->inputs()->@*;
            push @worklist, $node->consumers()->@*;
        }

        # Topological sort via DFS post-order
        my %temp;
        my $visit;
        $visit = sub ($n) {
            return if $visited{$n->id()};
            return if $temp{$n->id()};
            $temp{$n->id()} = 1;
            for my $input ($n->inputs()->@*) {
                next unless defined $input;
                $visit->($input);
            }
            delete $temp{$n->id()};
            $visited{$n->id()} = 1;
            push @order, $n;
        };

        for my $node (@all) {
            $visit->($node);
        }

        return \@order;
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-graph.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/Graph.pm t/bootstrap/ir-graph.t
git commit -m "feat: Chalk::IR::Graph with topological sort"
```

---

## Task 9: Metadata Structs

**Files:**
- Create: `lib/Chalk/IR/Program.pm`, `lib/Chalk/IR/ClassInfo.pm`,
  `lib/Chalk/IR/MethodInfo.pm`, `lib/Chalk/IR/SubInfo.pm`,
  `lib/Chalk/IR/FieldInfo.pm`
- Test: `t/bootstrap/ir-metadata.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/ir-metadata.t`:

```perl
# ABOUTME: Tests for Chalk::IR metadata structs (Program, ClassInfo, etc.).
# ABOUTME: Verifies plain data containers for program structure.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Program;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::FieldInfo;

# FieldInfo
my $fi = Chalk::IR::FieldInfo->new(
    name => '$type',
    attributes => [{name => 'param'}, {name => 'reader'}],
);
is($fi->name(), '$type', 'FieldInfo name');
is(scalar $fi->attributes()->@*, 2, 'FieldInfo has 2 attributes');
is($fi->default_value(), undef, 'FieldInfo default_value is undef');

# FieldInfo with default
my $fi2 = Chalk::IR::FieldInfo->new(
    name => '$count', default_value => '0',
);
is($fi2->default_value(), '0', 'FieldInfo default_value');
is_deeply($fi2->attributes(), [], 'FieldInfo attributes default empty');

# MethodInfo
my $mi = Chalk::IR::MethodInfo->new(
    name => 'foo', params => ['$self', '$x'], graph => undef,
);
is($mi->name(), 'foo', 'MethodInfo name');
is(scalar $mi->params()->@*, 2, 'MethodInfo params');
is($mi->graph(), undef, 'MethodInfo graph');
is($mi->return_type(), undef, 'MethodInfo return_type default');

# SubInfo
my $si = Chalk::IR::SubInfo->new(
    name => '_helper', params => ['$a'], scope => 'my',
);
is($si->name(), '_helper', 'SubInfo name');
is($si->scope(), 'my', 'SubInfo scope');

# SubInfo default scope
my $si2 = Chalk::IR::SubInfo->new(name => 'pkg_sub', params => []);
is($si2->scope(), 'package', 'SubInfo default scope is package');

# ClassInfo
my $ci = Chalk::IR::ClassInfo->new(
    name    => 'MyClass',
    parent  => 'BaseClass',
    fields  => [$fi],
    methods => [$mi],
    subs    => [$si],
);
is($ci->name(), 'MyClass', 'ClassInfo name');
is($ci->parent(), 'BaseClass', 'ClassInfo parent');
is(scalar $ci->fields()->@*, 1, 'ClassInfo fields');
is(scalar $ci->methods()->@*, 1, 'ClassInfo methods');
is(scalar $ci->subs()->@*, 1, 'ClassInfo subs');

# ClassInfo defaults
my $ci2 = Chalk::IR::ClassInfo->new(name => 'Bare');
is($ci2->parent(), undef, 'ClassInfo parent defaults undef');
is_deeply($ci2->fields(), [], 'ClassInfo fields default empty');

# Program
my $prog = Chalk::IR::Program->new(
    use_decls      => [{module => 'strict'}],
    classes        => [$ci],
    top_level_subs => [$si],
);
is(scalar $prog->use_decls()->@*, 1, 'Program use_decls');
is(scalar $prog->classes()->@*, 1, 'Program classes');
is(scalar $prog->top_level_subs()->@*, 1, 'Program top_level_subs');

# Program defaults
my $prog2 = Chalk::IR::Program->new();
is_deeply($prog2->use_decls(), [], 'Program use_decls default empty');
is_deeply($prog2->classes(), [], 'Program classes default empty');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/bootstrap/ir-metadata.t`
Expected: FAIL — `Can't locate Chalk/IR/Program.pm`

- [ ] **Step 3: Write minimal implementation**

`lib/Chalk/IR/FieldInfo.pm`:
```perl
# ABOUTME: Metadata struct for a class field declaration.
# ABOUTME: Stores name, attributes (param/reader/writer), and optional default value.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::FieldInfo {
    field $name          :param :reader;
    field $attributes    :param :reader = [];
    field $default_value :param :reader = undef;
}
```

`lib/Chalk/IR/MethodInfo.pm`:
```perl
# ABOUTME: Metadata struct for a method declaration.
# ABOUTME: Stores name, params, return type, and the per-method computation graph.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::MethodInfo {
    field $name        :param :reader;
    field $params      :param :reader = [];
    field $return_type :param :reader = undef;
    field $graph       :param :reader = undef;
}
```

`lib/Chalk/IR/SubInfo.pm`:
```perl
# ABOUTME: Metadata struct for a subroutine declaration.
# ABOUTME: Stores name, params, scope (my/our/package), and the computation graph.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::SubInfo {
    field $name   :param :reader;
    field $params :param :reader = [];
    field $scope  :param :reader = 'package';
    field $graph  :param :reader = undef;
}
```

`lib/Chalk/IR/ClassInfo.pm`:
```perl
# ABOUTME: Metadata struct for a class declaration.
# ABOUTME: Stores name, parent, fields, methods, and subs.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::ClassInfo {
    field $name    :param :reader;
    field $parent  :param :reader = undef;
    field $fields  :param :reader = [];
    field $methods :param :reader = [];
    field $subs    :param :reader = [];
}
```

`lib/Chalk/IR/Program.pm`:
```perl
# ABOUTME: Metadata struct for a complete Perl program.
# ABOUTME: Stores use declarations, classes, and top-level subroutines.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Program {
    field $use_decls      :param :reader = [];
    field $classes        :param :reader = [];
    field $top_level_subs :param :reader = [];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/bootstrap/ir-metadata.t`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/Chalk/IR/FieldInfo.pm lib/Chalk/IR/MethodInfo.pm \
        lib/Chalk/IR/SubInfo.pm lib/Chalk/IR/ClassInfo.pm \
        lib/Chalk/IR/Program.pm t/bootstrap/ir-metadata.t
git commit -m "feat: metadata structs (Program, ClassInfo, MethodInfo, SubInfo, FieldInfo)"
```

---

## Task 10: Run All Existing Tests (Regression Check)

This task verifies that the new code doesn't break anything. The new
`Chalk::IR::*` namespace is purely additive — nothing in the existing
codebase loads it yet.

- [ ] **Step 1: Run all bootstrap tests**

Run: `perl -Ilib t/bootstrap/*.t 2>&1 | tail -20`
Expected: All existing tests still pass. The new `Chalk::IR::*` files
are not loaded by any existing code, so there should be zero regressions.

- [ ] **Step 2: Run new tests together**

Run: `perl -Ilib t/bootstrap/ir-node-base.t t/bootstrap/ir-node-cfg.t t/bootstrap/ir-node-binop.t t/bootstrap/ir-node-unaryop.t t/bootstrap/ir-node-data.t t/bootstrap/ir-node-misc.t t/bootstrap/ir-node-factory.t t/bootstrap/ir-graph.t t/bootstrap/ir-metadata.t`
Expected: All new tests PASS

- [ ] **Step 3: Commit (if any test fixes were needed)**

Only commit if Step 1 or 2 revealed issues that needed fixing.
