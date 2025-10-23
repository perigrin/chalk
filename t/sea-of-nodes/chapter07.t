#!/usr/bin/env perl
# ABOUTME: Test Sea of Nodes Chapter 7 - While Loops
# ABOUTME: Validates loop IR nodes, loop phi nodes, and basic while loop semantics

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Chalk::IR::Node;
use Chalk::IR::Graph;
use Chalk::IR::Scope;
use Chalk::IR::Validator;

subtest 'Loop node creation' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    # Loop node is like Region but for loops
    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id],  # Entry control
        attributes => {},
    );
    $graph->add_node($loop);

    is $loop->op, 'Loop', 'Loop node created';
    is scalar($loop->inputs->@*), 1, 'Loop has entry control';

    # Add backedge later (lazy phi pattern)
    push $loop->inputs->@*, 3;  # Backedge from loop body
    is scalar($loop->inputs->@*), 2, 'Loop can add backedge';
};

subtest 'Loop phi node creation' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    # Loop phi has initial value and placeholder for backedge
    my $phi = Chalk::IR::Node->new(
        id => 3,
        op => 'Phi',
        inputs => [$loop->id, 0],  # Control, initial value
        attributes => {},
    );
    $graph->add_node($phi);

    is $phi->op, 'Phi', 'Loop phi node created';
    is scalar($phi->inputs->@*), 2, 'Loop phi has control and initial value';

    # Add loop value later
    push $phi->inputs->@*, 10;  # Loop update value
    is scalar($phi->inputs->@*), 3, 'Loop phi can add loop value';
};

subtest 'Simple while(true) infinite loop IR' => sub {
    # while (true) { }
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id],  # Entry
        attributes => {},
    );
    $graph->add_node($loop);

    my $const_true = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_true);

    my $if_node = Chalk::IR::Node->new(
        id => 4,
        op => 'If',
        inputs => [$loop->id, $const_true->id],
        attributes => {},
    );
    $graph->add_node($if_node);

    my $proj_true = Chalk::IR::Node->new(
        id => 5,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 0 },
    );
    $graph->add_node($proj_true);

    my $proj_false = Chalk::IR::Node->new(
        id => 6,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 1 },
    );
    $graph->add_node($proj_false);

    # Backedge to loop
    push $loop->inputs->@*, $proj_true->id;

    # Exit through false branch
    my $return_node = Chalk::IR::Node->new(
        id => 7,
        op => 'Return',
        inputs => [$proj_false->id, 0],
        attributes => {},
    );
    $graph->add_node($return_node);

    is scalar($loop->inputs->@*), 2, 'Loop has entry and backedge';
    my $json = $graph->to_json();
    my $has_loop = scalar(grep { $_->{op} eq 'Loop' } $json->{nodes}->@*);
    ok $has_loop, 'IR contains Loop node';
};

subtest 'While loop with counter: while(i < 10) { i = i + 1; }' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $scope = Chalk::IR::Scope->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    # Initial value i = 0
    my $init_val = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($init_val);
    $scope->define('i', $init_val);

    # Loop entry
    my $loop = Chalk::IR::Node->new(
        id => 3,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);
    $scope->push_scope();

    # Loop phi for i
    my $phi_i = Chalk::IR::Node->new(
        id => 4,
        op => 'Phi',
        inputs => [$loop->id, $init_val->id],
        attributes => {},
    );
    $graph->add_node($phi_i);
    $scope->define('i', $phi_i);

    # Condition: i < 10
    my $const_10 = Chalk::IR::Node->new(
        id => 5,
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 },
    );
    $graph->add_node($const_10);

    my $cmp = Chalk::IR::Node->new(
        id => 6,
        op => 'LT',
        inputs => [$phi_i->id, $const_10->id],
        attributes => {},
    );
    $graph->add_node($cmp);

    my $if_node = Chalk::IR::Node->new(
        id => 7,
        op => 'If',
        inputs => [$loop->id, $cmp->id],
        attributes => {},
    );
    $graph->add_node($if_node);

    # True branch: loop body
    my $proj_true = Chalk::IR::Node->new(
        id => 8,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 0 },
    );
    $graph->add_node($proj_true);

    # i = i + 1
    my $const_1 = Chalk::IR::Node->new(
        id => 9,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node->new(
        id => 10,
        op => 'Add',
        inputs => [$phi_i->id, $const_1->id],
        attributes => {},
    );
    $graph->add_node($add);

    # Update phi and loop backedge
    push $phi_i->inputs->@*, $add->id;
    push $loop->inputs->@*, $proj_true->id;

    # False branch: exit loop
    my $proj_false = Chalk::IR::Node->new(
        id => 11,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 1 },
    );
    $graph->add_node($proj_false);

    my $return_node = Chalk::IR::Node->new(
        id => 12,
        op => 'Return',
        inputs => [$proj_false->id, $phi_i->id],
        attributes => {},
    );
    $graph->add_node($return_node);

    # Validate structure
    is scalar($loop->inputs->@*), 2, 'Loop has entry and backedge';
    is scalar($phi_i->inputs->@*), 3, 'Loop phi has control, init, and loop value';

    my $validator = Chalk::IR::Validator->new();
    my @cfg_errors = $validator->validate_cfg($graph);
    if (@cfg_errors) {
        diag("CFG errors: " . join(", ", @cfg_errors));
    }
    is scalar(@cfg_errors), 0, 'CFG is valid';
    my @phi_errors = $validator->validate_phi_placement($graph);
    if (@phi_errors) {
        diag("Phi errors: " . join(", ", @phi_errors));
    }
    is scalar(@phi_errors), 0, 'Phi placement is valid';
};

subtest 'Loop phi constant folding' => sub {
    # Test that loop phis don't get constant folded
    my $graph = Chalk::IR::Graph->new();

    my $loop = Chalk::IR::Node->new(
        id => 1,
        op => 'Loop',
        inputs => [0],
        attributes => {},
    );
    $graph->add_node($loop);

    my $const_5 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 5 },
    );
    $graph->add_node($const_5);

    # Loop phi with two constant inputs - should NOT fold
    # because the loop value comes from a backedge
    my $phi = Chalk::IR::Node->new(
        id => 3,
        op => 'Phi',
        inputs => [$loop->id, $const_5->id, $const_5->id],
        attributes => {},
    );
    $graph->add_node($phi);

    my $result = $phi->peephole($graph);
    is $result->op, 'Phi', 'Loop phi does not constant fold';
};

subtest 'Nested scopes with loop' => sub {
    my $scope = Chalk::IR::Scope->new();

    # Outer scope
    my $const_0 = Chalk::IR::Node->new(
        id => 1,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $scope->define('x', $const_0);

    is $scope->lookup('x')->id, 1, 'Outer x defined';

    # Enter loop scope
    $scope->push_scope();

    my $phi_x = Chalk::IR::Node->new(
        id => 2,
        op => 'Phi',
        inputs => [0, $const_0->id],
        attributes => {},
    );
    $scope->define('x', $phi_x);

    is $scope->lookup('x')->id, 2, 'Loop x shadows outer x';

    # Exit loop scope
    $scope->pop_scope();

    is $scope->lookup('x')->id, 1, 'Outer x restored after loop';
};

subtest 'Loop with multiple phis' => sub {
    # while (i < 10 && j < 5) { i++; j++; }
    my $graph = Chalk::IR::Graph->new();
    my $scope = Chalk::IR::Scope->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    # Initialize i = 0, j = 0
    my $init_i = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($init_i);
    $scope->define('i', $init_i);

    my $init_j = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($init_j);
    $scope->define('j', $init_j);

    # Loop
    my $loop = Chalk::IR::Node->new(
        id => 4,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);
    $scope->push_scope();

    # Loop phis
    my $phi_i = Chalk::IR::Node->new(
        id => 5,
        op => 'Phi',
        inputs => [$loop->id, $init_i->id],
        attributes => {},
    );
    $graph->add_node($phi_i);
    $scope->define('i', $phi_i);

    my $phi_j = Chalk::IR::Node->new(
        id => 6,
        op => 'Phi',
        inputs => [$loop->id, $init_j->id],
        attributes => {},
    );
    $graph->add_node($phi_j);
    $scope->define('j', $phi_j);

    # Add backedge values
    my $const_1 = Chalk::IR::Node->new(
        id => 7,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $i_plus_1 = Chalk::IR::Node->new(
        id => 8,
        op => 'Add',
        inputs => [$phi_i->id, $const_1->id],
        attributes => {},
    );
    $graph->add_node($i_plus_1);

    my $j_plus_1 = Chalk::IR::Node->new(
        id => 9,
        op => 'Add',
        inputs => [$phi_j->id, $const_1->id],
        attributes => {},
    );
    $graph->add_node($j_plus_1);

    push $phi_i->inputs->@*, $i_plus_1->id;
    push $phi_j->inputs->@*, $j_plus_1->id;
    push $loop->inputs->@*, $loop->id;  # Simplified backedge

    is scalar($phi_i->inputs->@*), 3, 'Phi i has all inputs';
    is scalar($phi_j->inputs->@*), 3, 'Phi j has all inputs';

    # Note: Not validating CFG since this is just a structural test without Return
};

subtest 'Loop exit with final value' => sub {
    # i = 0; while (i < 3) { i++; } return i;
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $init = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($init);

    my $loop = Chalk::IR::Node->new(
        id => 3,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    my $phi = Chalk::IR::Node->new(
        id => 4,
        op => 'Phi',
        inputs => [$loop->id, $init->id],
        attributes => {},
    );
    $graph->add_node($phi);

    my $const_3 = Chalk::IR::Node->new(
        id => 5,
        op => 'Constant',
        inputs => [],
        attributes => { value => 3 },
    );
    $graph->add_node($const_3);

    my $cmp = Chalk::IR::Node->new(
        id => 6,
        op => 'LT',
        inputs => [$phi->id, $const_3->id],
        attributes => {},
    );
    $graph->add_node($cmp);

    my $if_node = Chalk::IR::Node->new(
        id => 7,
        op => 'If',
        inputs => [$loop->id, $cmp->id],
        attributes => {},
    );
    $graph->add_node($if_node);

    my $proj_true = Chalk::IR::Node->new(
        id => 8,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 0 },
    );
    $graph->add_node($proj_true);

    my $const_1 = Chalk::IR::Node->new(
        id => 9,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node->new(
        id => 10,
        op => 'Add',
        inputs => [$phi->id, $const_1->id],
        attributes => {},
    );
    $graph->add_node($add);

    push $phi->inputs->@*, $add->id;
    push $loop->inputs->@*, $proj_true->id;

    my $proj_false = Chalk::IR::Node->new(
        id => 11,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 1 },
    );
    $graph->add_node($proj_false);

    # Return final phi value
    my $return_node = Chalk::IR::Node->new(
        id => 12,
        op => 'Return',
        inputs => [$proj_false->id, $phi->id],
        attributes => {},
    );
    $graph->add_node($return_node);

    is $return_node->inputs->[1], $phi->id, 'Return uses loop phi value';

    my $json = $graph->to_json();
    my $has_return = scalar(grep { $_->{op} eq 'Return' } $json->{nodes}->@*);
    my $has_loop = scalar(grep { $_->{op} eq 'Loop' } $json->{nodes}->@*);
    ok $has_return, 'Return in JSON';
    ok $has_loop, 'Loop in JSON';
};

subtest 'Loop validator integration' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Valid loop structure with Return node
    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id],  # Entry (backedge added after phi)
        attributes => {},
    );
    $graph->add_node($loop);

    my $phi = Chalk::IR::Node->new(
        id => 3,
        op => 'Phi',
        inputs => [$loop->id, 0, 1],
        attributes => {},
    );
    $graph->add_node($phi);

    # Add backedge
    push $loop->inputs->@*, $phi->id;

    # Add Return to make CFG valid
    my $return_node = Chalk::IR::Node->new(
        id => 4,
        op => 'Return',
        inputs => [$loop->id, $phi->id],
        attributes => {},
    );
    $graph->add_node($return_node);

    my $validator = Chalk::IR::Validator->new();

    # Should validate without errors
    my @cfg_errors = $validator->validate_cfg($graph);
    if (@cfg_errors) {
        diag("CFG errors: " . join(", ", @cfg_errors));
    }
    is scalar(@cfg_errors), 0, 'Loop CFG validates';
    my @phi_errors = $validator->validate_phi_placement($graph);
    if (@phi_errors) {
        diag("Phi errors: " . join(", ", @phi_errors));
    }
    is scalar(@phi_errors), 0, 'Loop phi validates';
};

subtest 'Peephole does not optimize across loop boundaries' => sub {
    # Ensure peephole doesn't incorrectly optimize loop-carried dependencies
    my $graph = Chalk::IR::Graph->new();

    my $loop = Chalk::IR::Node->new(
        id => 1,
        op => 'Loop',
        inputs => [0],
        attributes => {},
    );
    $graph->add_node($loop);

    my $const_0 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $phi = Chalk::IR::Node->new(
        id => 3,
        op => 'Phi',
        inputs => [$loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi);

    # Add self-referencing backedge
    push $phi->inputs->@*, $phi->id;

    my $optimized = $phi->peephole($graph);

    # Should not simplify to constant even though init is constant
    isnt $optimized->op, 'Constant', 'Loop phi not constant folded';
    is $optimized->id, $phi->id, 'Loop phi preserved';
};
