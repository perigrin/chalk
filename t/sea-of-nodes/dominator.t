# ABOUTME: Tests for dominator-based optimization in the IR graph
# ABOUTME: Validates idom()/idepth() calculation and nested If optimization with identical predicates

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(refaddr);

# Load type system
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::Ctrl;
use Chalk::IR::Type::Tuple;
use Chalk::IR::Type::Bool;
use Chalk::IR::Type::Integer;

# Load node classes
use_ok('Chalk::IR::Node::Base');
use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Node::If');
use_ok('Chalk::IR::Node::Proj');
use_ok('Chalk::IR::Node::Region');
use_ok('Chalk::IR::Node::Phi');
use_ok('Chalk::IR::Node::GT');
use_ok('Chalk::IR::Graph');

# Test 1: CFG nodes have idom() method
subtest 'CFG nodes have idom() and idepth() methods' => sub {
    my $start = Chalk::IR::Node::Start->new(
        function => 'test',
        params => [],
    );

    ok($start->can('idom'), 'Start node has idom() method');
    ok($start->can('idepth'), 'Start node has idepth() method');

    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => [],
        index => 0,
        label => '$ctrl',
        source => $start,
    );

    ok($ctrl->can('idom'), 'Proj node has idom() method');
    ok($ctrl->can('idepth'), 'Proj node has idepth() method');
};

# Test 2: Start node is the dominator root (idom returns undef, idepth returns 0)
subtest 'Start node is dominator root' => sub {
    my $start = Chalk::IR::Node::Start->new(
        function => 'test',
        params => [],
    );

    is($start->idom(), undef, 'Start idom() returns undef (it is the root)');
    is($start->idepth(), 0, 'Start idepth() returns 0');
};

# Test 3: Proj from Start has Start as its idom
subtest 'Proj from Start has depth 1' => sub {
    my $start = Chalk::IR::Node::Start->new(
        function => 'test',
        params => [],
    );

    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => [$start->id],
        index => 0,
        label => '$ctrl',
        source => $start,
    );

    is(refaddr($ctrl->idom()), refaddr($start), 'Proj from Start has Start as idom');
    is($ctrl->idepth(), 1, 'Proj from Start has depth 1');
};

# Test 4: If projections have correct dominator depth
subtest 'If projections have If control as idom' => sub {
    my $start = Chalk::IR::Node::Start->new(
        function => 'test',
        params => [],
    );

    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => [$start->id],
        index => 0,
        label => '$ctrl',
        source => $start,
    );

    my $cond = Chalk::IR::Node::Constant->new(
        value => true,
        type => Chalk::IR::Type::Bool->constant(true),
    );

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $cond->id],
        condition_id => $cond->id,
        control => $ctrl,
        condition => $cond,
    );

    my $true_proj = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'true',
        source => $if_node,
    );

    my $false_proj = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'false',
        source => $if_node,
    );

    # True/False projections should have depth = if's control depth + 1
    is($true_proj->idepth(), $ctrl->idepth() + 1, 'True proj depth is ctrl depth + 1');
    is($false_proj->idepth(), $ctrl->idepth() + 1, 'False proj depth is ctrl depth + 1');

    # Their idom should be the If's control input (the ctrl Proj)
    is(refaddr($true_proj->idom()), refaddr($ctrl), 'True proj idom is ctrl');
    is(refaddr($false_proj->idom()), refaddr($ctrl), 'False proj idom is ctrl');
};

# Test 5: Region finds lowest common ancestor as idom
subtest 'Region idom is lowest common ancestor of inputs' => sub {
    my $start = Chalk::IR::Node::Start->new(
        function => 'test',
        params => [],
    );

    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => [$start->id],
        index => 0,
        label => '$ctrl',
        source => $start,
    );

    my $cond = Chalk::IR::Node::Constant->new(
        value => true,
        type => Chalk::IR::Type::Bool->constant(true),
    );

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $cond->id],
        condition_id => $cond->id,
        control => $ctrl,
        condition => $cond,
    );

    my $true_proj = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'true',
        source => $if_node,
    );

    my $false_proj = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'false',
        source => $if_node,
    );

    my $region = Chalk::IR::Node::Region->new(
        inputs => [$true_proj->id, $false_proj->id],
    );
    # Manually set control inputs for idom calculation
    $region->set_control_inputs([$true_proj, $false_proj]);

    # Region's idom should be the common ancestor of both branches
    # Both branches come from the same If, so their common ancestor is ctrl
    is(refaddr($region->idom()), refaddr($ctrl), 'Region idom is LCA of branches (ctrl)');
    is($region->idepth(), $ctrl->idepth() + 1, 'Region depth is LCA depth + 1');
};

# Load VariableRead for non-constant test values
use_ok('Chalk::IR::Node::VariableRead');

# Test 6: Nested If with identical predicate - inner If compute() detects dominating If
subtest 'Nested If with identical predicate detected in compute()' => sub {
    # Build: if ($x > 0) { if ($x > 0) { ... } }
    # The inner if should detect that its condition is already determined

    my $start = Chalk::IR::Node::Start->new(
        function => 'test',
        params => [],
    );

    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => [$start->id],
        index => 0,
        label => '$ctrl',
        source => $start,
    );

    # Variable $x - use VariableRead which returns TOP (non-constant)
    my $x = Chalk::IR::Node::VariableRead->new(
        inputs => [],
        var_label => 'lexical:$x',
    );

    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0),
    );

    # Predicate: $x > 0 (non-constant because $x is unknown)
    my $cond = Chalk::IR::Node::GT->new(
        left => $x,
        right => $zero,
    );

    # Outer If
    my $outer_if = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $cond->id],
        condition_id => $cond->id,
        control => $ctrl,
        condition => $cond,
    );

    # True branch of outer If
    my $outer_true = Chalk::IR::Node::Proj->new(
        inputs => [$outer_if->id],
        index => 0,
        label => 'true',
        source => $outer_if,
    );

    # Inner If with SAME predicate (inside true branch)
    my $inner_if = Chalk::IR::Node::If->new(
        inputs => [$outer_true->id, $cond->id],  # Same condition!
        condition_id => $cond->id,
        control => $outer_true,
        condition => $cond,
    );

    # The inner If's compute() should detect that we're inside the true branch
    # of an outer If with the same predicate, so the condition is always true
    my $inner_type = $inner_if->compute();

    # Type should indicate that only the true branch is reachable
    # (IF_TRUE tuple: true branch live, false branch dead)
    ok($inner_type isa Chalk::IR::Type::Tuple, 'Inner If compute() returns TypeTuple');

    my $true_ctrl = $inner_type->at(0);
    my $false_ctrl = $inner_type->at(1);

    ok($true_ctrl isa Chalk::IR::Type::Ctrl, 'True branch is Ctrl (live)');
    ok($false_ctrl isa Chalk::IR::Type::Bottom, 'False branch is Bottom (dead)');
};

# Test 7: Nested If on false branch - condition is always false
subtest 'Nested If on false branch is always false' => sub {
    my $start = Chalk::IR::Node::Start->new(
        function => 'test',
        params => [],
    );

    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => [$start->id],
        index => 0,
        label => '$ctrl',
        source => $start,
    );

    # Variable $x - use VariableRead which returns TOP (non-constant)
    my $x = Chalk::IR::Node::VariableRead->new(
        inputs => [],
        var_label => 'lexical:$x',
    );

    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0),
    );

    # Non-constant predicate
    my $cond = Chalk::IR::Node::GT->new(
        left => $x,
        right => $zero,
    );

    my $outer_if = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $cond->id],
        condition_id => $cond->id,
        control => $ctrl,
        condition => $cond,
    );

    # False branch of outer If
    my $outer_false = Chalk::IR::Node::Proj->new(
        inputs => [$outer_if->id],
        index => 1,
        label => 'false',
        source => $outer_if,
    );

    # Inner If with SAME predicate (inside false branch)
    my $inner_if = Chalk::IR::Node::If->new(
        inputs => [$outer_false->id, $cond->id],  # Same condition!
        condition_id => $cond->id,
        control => $outer_false,
        condition => $cond,
    );

    # The inner If should detect we're on the false branch of outer If
    # with same predicate, so condition is always false
    my $inner_type = $inner_if->compute();

    ok($inner_type isa Chalk::IR::Type::Tuple, 'Inner If compute() returns TypeTuple');

    my $true_ctrl = $inner_type->at(0);
    my $false_ctrl = $inner_type->at(1);

    ok($true_ctrl isa Chalk::IR::Type::Bottom, 'True branch is Bottom (dead)');
    ok($false_ctrl isa Chalk::IR::Type::Ctrl, 'False branch is Ctrl (live)');
};

# Test 8: Different predicates - no optimization
subtest 'Different predicates are not optimized' => sub {
    my $start = Chalk::IR::Node::Start->new(
        function => 'test',
        params => [],
    );

    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => [$start->id],
        index => 0,
        label => '$ctrl',
        source => $start,
    );

    # Variables $x and $y - use VariableRead for non-constant values
    my $x = Chalk::IR::Node::VariableRead->new(
        inputs => [],
        var_label => 'lexical:$x',
    );

    my $y = Chalk::IR::Node::VariableRead->new(
        inputs => [],
        var_label => 'lexical:$y',
    );

    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0),
    );

    # Outer: $x > 0 (non-constant)
    my $cond1 = Chalk::IR::Node::GT->new(
        left => $x,
        right => $zero,
    );

    # Inner: $y > 0 (different predicate, also non-constant)
    my $cond2 = Chalk::IR::Node::GT->new(
        left => $y,
        right => $zero,
    );

    my $outer_if = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $cond1->id],
        condition_id => $cond1->id,
        control => $ctrl,
        condition => $cond1,
    );

    my $outer_true = Chalk::IR::Node::Proj->new(
        inputs => [$outer_if->id],
        index => 0,
        label => 'true',
        source => $outer_if,
    );

    # Inner If with DIFFERENT predicate
    my $inner_if = Chalk::IR::Node::If->new(
        inputs => [$outer_true->id, $cond2->id],  # Different condition!
        condition_id => $cond2->id,
        control => $outer_true,
        condition => $cond2,
    );

    my $inner_type = $inner_if->compute();

    # Both branches should be reachable (IF_BOTH)
    ok($inner_type isa Chalk::IR::Type::Tuple, 'Inner If compute() returns TypeTuple');

    my $true_ctrl = $inner_type->at(0);
    my $false_ctrl = $inner_type->at(1);

    # Both should be live (TypeCtrl or at least not Bottom)
    ok(!($true_ctrl isa Chalk::IR::Type::Bottom), 'True branch is live');
    ok(!($false_ctrl isa Chalk::IR::Type::Bottom), 'False branch is live');
};

done_testing();
