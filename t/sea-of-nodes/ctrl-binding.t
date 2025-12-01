# ABOUTME: Tests for $ctrl scope binding - explicit control flow tracking per Simple Chapter 4
# ABOUTME: Validates $ctrl binding at Start, branch points, merge points, and control killing after return

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(blessed);

use_ok('Chalk::IR::Node::Scope');
use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::If');
use_ok('Chalk::IR::Node::Proj');
use_ok('Chalk::IR::Node::Region');
use_ok('Chalk::IR::Node::Loop');
use_ok('Chalk::IR::Node::Phi');
use_ok('Chalk::IR::Node::Constant');

# =============================================================================
# Phase 1: Core Infrastructure - $ctrl binding at program start
# =============================================================================

subtest '$ctrl bound to Start node at program entry' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    # Create initial scope and bind $ctrl to Start
    my $scope = Chalk::IR::Node::Scope->new();
    $scope = $scope->with_control($start);
    $scope = $scope->with_binding('$ctrl', $start);

    # Verify $ctrl is bound
    my $ctrl = $scope->lookup('$ctrl');
    ok(defined($ctrl), '$ctrl is bound in scope');
    ok(blessed($ctrl), '$ctrl is an object');
    ok($ctrl->can('op'), '$ctrl has op() method');
    is($ctrl->op, 'Start', '$ctrl is bound to Start node');
    is($ctrl->id, $start->id, '$ctrl id matches Start id');
};

subtest '$ctrl accessible via scope lookup' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start);

    # Lookup should return the Start node
    my $found = $scope->lookup('$ctrl');
    ok($found, 'lookup($ctrl) returns value');
    is($found->id, $start->id, 'lookup returns correct node');
};

# =============================================================================
# Phase 2: Control Flow Statements - $ctrl in conditional branches
# =============================================================================

subtest '$ctrl bound to IfTrue Proj in true branch' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');
    my $condition = Chalk::IR::Node::Constant->new(value => 1, type => 'Bool');

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$start->id, $condition->id],
        condition_id => $condition->id,
        condition => $condition,
        control => $start,
    );

    my $if_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );

    # Create true branch scope with $ctrl bound to IfTrue
    my $pre_scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start);

    my $true_scope = $pre_scope->child_scope()
        ->with_control($if_true->id)
        ->with_binding('$ctrl', $if_true);

    my $ctrl = $true_scope->lookup('$ctrl');
    ok(defined($ctrl), '$ctrl bound in true branch');
    is($ctrl->op, 'Proj', '$ctrl is Proj node');
    is($ctrl->label, 'IfTrue', '$ctrl is IfTrue projection');
};

subtest '$ctrl bound to IfFalse Proj in false branch' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');
    my $condition = Chalk::IR::Node::Constant->new(value => 0, type => 'Bool');

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$start->id, $condition->id],
        condition_id => $condition->id,
        condition => $condition,
        control => $start,
    );

    my $if_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );

    # Create false branch scope with $ctrl bound to IfFalse
    my $pre_scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start);

    my $false_scope = $pre_scope->child_scope()
        ->with_control($if_false->id)
        ->with_binding('$ctrl', $if_false);

    my $ctrl = $false_scope->lookup('$ctrl');
    ok(defined($ctrl), '$ctrl bound in false branch');
    is($ctrl->op, 'Proj', '$ctrl is Proj node');
    is($ctrl->label, 'IfFalse', '$ctrl is IfFalse projection');
};

subtest '$ctrl bound to Region at merge point' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    # Simulate If with true/false branches merging at Region
    my $region = Chalk::IR::Node::Region->new(
        inputs => ['if_true_id', 'if_false_id'],
    );

    my $pre_scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start);

    # After merge, $ctrl should be bound to Region
    my $merged_scope = $pre_scope
        ->with_control($region->id)
        ->with_binding('$ctrl', $region);

    my $ctrl = $merged_scope->lookup('$ctrl');
    ok(defined($ctrl), '$ctrl bound at merge point');
    is($ctrl->op, 'Region', '$ctrl is Region node at merge');
};

# =============================================================================
# Phase 2 continued: $ctrl in while loops
# =============================================================================

subtest '$ctrl bound to Loop node at loop entry' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );

    my $pre_scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start);

    my $loop_scope = $pre_scope
        ->with_control($loop->id)
        ->with_binding('$ctrl', $loop);

    my $ctrl = $loop_scope->lookup('$ctrl');
    ok(defined($ctrl), '$ctrl bound at loop entry');
    is($ctrl->op, 'Loop', '$ctrl is Loop node');
};

subtest '$ctrl bound to exit Region after loop' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    my $exit_region = Chalk::IR::Node::Region->new(
        inputs => ['if_false_id'],  # Loop exit
    );

    my $pre_scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start);

    my $exit_scope = $pre_scope
        ->with_control($exit_region->id)
        ->with_binding('$ctrl', $exit_region);

    my $ctrl = $exit_scope->lookup('$ctrl');
    ok(defined($ctrl), '$ctrl bound after loop exit');
    is($ctrl->op, 'Region', '$ctrl is exit Region');
};

# =============================================================================
# Phase 3: $ctrl excluded from Phi generation
# =============================================================================

subtest '$ctrl excluded from Phi generation in merge_scopes' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    # Create If structure
    my $condition = Chalk::IR::Node::Constant->new(value => 1, type => 'Bool');
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$start->id, $condition->id],
        condition_id => $condition->id,
        condition => $condition,
        control => $start,
    );

    my $if_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );

    my $if_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );

    my $region = Chalk::IR::Node::Region->new(
        inputs => [$if_true->id, $if_false->id],
    );

    # Pre-scope with $ctrl at Start
    my $pre_scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start)
        ->with_binding('$x', Chalk::IR::Node::Constant->new(value => 0, type => 'Integer'));

    # True branch: $ctrl at IfTrue, $x = 1
    my $true_scope = $pre_scope->child_scope()
        ->with_control($if_true->id)
        ->with_binding('$ctrl', $if_true)
        ->with_binding('$x', Chalk::IR::Node::Constant->new(value => 1, type => 'Integer'));

    # False branch: $ctrl at IfFalse, $x = 2
    my $false_scope = $pre_scope->child_scope()
        ->with_control($if_false->id)
        ->with_binding('$ctrl', $if_false)
        ->with_binding('$x', Chalk::IR::Node::Constant->new(value => 2, type => 'Integer'));

    # Merge scopes
    my $merged = $pre_scope->merge_scopes($true_scope, $false_scope, $region);

    # $x should be a Phi (different values)
    my $merged_x = $merged->lookup('$x');
    ok(defined($merged_x), '$x is bound after merge');
    is($merged_x->op, 'Phi', '$x is Phi node (values differed)');

    # $ctrl should NOT be a Phi - it should be the Region (control just copied)
    my $merged_ctrl = $merged->lookup('$ctrl');
    ok(defined($merged_ctrl), '$ctrl is bound after merge');

    # Per Simple spec: "control input is just copied" - should NOT be Phi
    isnt($merged_ctrl->op, 'Phi', '$ctrl is NOT a Phi node');
    # After merge, $ctrl should be the Region (merge point control)
    is($merged_ctrl->op, 'Region', '$ctrl is Region at merge point');
};

# =============================================================================
# Phase 4: Kill control after return
# =============================================================================

subtest '$ctrl set to undef after return (dead code marker)' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    my $scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start);

    # Verify $ctrl is initially bound
    ok(defined($scope->lookup('$ctrl')), '$ctrl bound before return');

    # After return, $ctrl should be undef (dead code)
    my $dead_scope = $scope->with_binding('$ctrl', undef);

    my $ctrl = $dead_scope->lookup('$ctrl');
    # lookup returns undef for undef binding
    ok(!defined($ctrl) || !ref($ctrl), '$ctrl is undef/not-a-node after return');
};

# =============================================================================
# Integration test: complex control flow
# =============================================================================

subtest 'Integration: $ctrl tracks through nested control flow' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    # Initial scope
    my $scope = Chalk::IR::Node::Scope->new()
        ->with_control($start)
        ->with_binding('$ctrl', $start);

    is($scope->lookup('$ctrl')->op, 'Start', 'Initial $ctrl is Start');

    # Enter if statement
    my $condition = Chalk::IR::Node::Constant->new(value => 1, type => 'Bool');
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$start->id, $condition->id],
        condition_id => $condition->id,
        condition => $condition,
        control => $start,
    );

    my $if_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );

    my $true_scope = $scope->child_scope()
        ->with_control($if_true->id)
        ->with_binding('$ctrl', $if_true);

    is($true_scope->lookup('$ctrl')->op, 'Proj', '$ctrl is Proj in if branch');
    is($true_scope->lookup('$ctrl')->label, 'IfTrue', '$ctrl is IfTrue');

    # Nested while loop inside if
    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$if_true->id],
    );

    my $loop_scope = $true_scope->child_scope()
        ->with_control($loop->id)
        ->with_binding('$ctrl', $loop);

    is($loop_scope->lookup('$ctrl')->op, 'Loop', '$ctrl is Loop inside if');

    # Exit loop
    my $exit_region = Chalk::IR::Node::Region->new(
        inputs => ['loop_false'],
    );

    my $exit_scope = $loop_scope
        ->with_control($exit_region->id)
        ->with_binding('$ctrl', $exit_region);

    is($exit_scope->lookup('$ctrl')->op, 'Region', '$ctrl is Region after loop');
};

done_testing();
