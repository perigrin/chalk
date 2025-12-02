#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter execution with loop iteration
# ABOUTME: Tests Loop iteration, Phi value selection, and backedge traversal

use 5.42.0;
use utf8;
use lib 'lib';
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Phi;
use Chalk::Interpreter::CEKDataflow;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Return;

subtest 'Loop node tracks active_input_index' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    # Create a Loop with entry control from Start
    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    # Initial active_input_index should be 0 (not yet executed)
    is($loop->active_input_index, 0, 'Loop active_input_index defaults to 0');
};

subtest 'Loop.execute() sets active_input_index based on active path' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id, 'backedge_placeholder'],
    );
    $graph->add_node($loop);

    # Mock context where entry control (index 0) is active
    my %node_values = (
        $start->id => 1,  # Entry path active
        'backedge_placeholder' => 0,  # Backedge not active
    );
    my $context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };

    my $result = $loop->execute($context);

    is($result, 0, 'Loop returns 0 for entry path');
    is($loop->active_input_index, 0, 'active_input_index set to 0 for entry');
};

subtest 'Loop.execute() returns 1 when backedge is active' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id, 'backedge_ctrl'],
    );
    $graph->add_node($loop);

    # Mock context where backedge (index 1) is active
    my %node_values = (
        $start->id => 0,  # Entry path not active
        'backedge_ctrl' => 1,  # Backedge active (continue iterating)
    );
    my $context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };

    my $result = $loop->execute($context);

    is($result, 1, 'Loop returns 1 for backedge path');
    is($loop->active_input_index, 1, 'active_input_index set to 1 for backedge');
};

subtest 'Phi selects entry value (index 0) on first iteration' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id, 'backedge_ctrl'],
    );
    $graph->add_node($loop);

    my $init_val = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_val);

    my $loop_val = Chalk::IR::Node::Constant->new(value => 42, type => 'int');
    $graph->add_node($loop_val);

    # Phi with Loop region: inputs = [region_id, entry_value, backedge_value]
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_val->id, $loop_val->id],
    );
    $graph->add_node($phi);

    # Simulate entry path active (index 0)
    my %node_values = (
        $start->id => 1,
        'backedge_ctrl' => 0,
        $init_val->id => 0,
        $loop_val->id => 42,
    );

    # First execute Loop to set active_input_index
    my $loop_context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };
    $loop->execute($loop_context);

    # Now execute Phi - should select entry value
    my $phi_context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };
    my $result = $phi->execute($phi_context);

    is($result, 0, 'Phi selects entry value (0) when Loop active_input_index is 0');
};

subtest 'Phi selects backedge value (index 1) on subsequent iterations' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id, 'backedge_ctrl'],
    );
    $graph->add_node($loop);

    my $init_val = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_val);

    my $loop_val = Chalk::IR::Node::Constant->new(value => 42, type => 'int');
    $graph->add_node($loop_val);

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_val->id, $loop_val->id],
    );
    $graph->add_node($phi);

    # Simulate backedge path active (index 1)
    my %node_values = (
        $start->id => 0,
        'backedge_ctrl' => 1,
        $init_val->id => 0,
        $loop_val->id => 42,
    );

    # First execute Loop to set active_input_index = 1
    my $loop_context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };
    $loop->execute($loop_context);

    # Now execute Phi - should select backedge value
    my $phi_context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };
    my $result = $phi->execute($phi_context);

    is($result, 42, 'Phi selects backedge value (42) when Loop active_input_index is 1');
};

subtest 'CEKDataflow.find_loop_body_nodes identifies loop-dependent nodes' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: while (i < 10) { i = i + 1; } return i;
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $init_i = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_i);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    my $phi_i = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_i->id],
    );
    $graph->add_node($phi_i);

    my $const_10 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    $graph->add_node($const_10);

    my $lt = Chalk::IR::Node::LT->new(
        left => $phi_i,
        right => $const_10,
    );
    $graph->add_node($lt);

    my $const_1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node::Add->new(
        left => $phi_i,
        right => $const_1,
    );
    $graph->add_node($add);

    # Complete phi backedge
    push $phi_i->inputs->@*, $add->id;
    # Add backedge to loop (simplified - would normally be from Proj)
    push $loop->inputs->@*, $loop->id;

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my @body_nodes = $interp->find_loop_body_nodes($loop->id);

    # Should find: phi_i, lt, add (nodes that depend on Loop or its Phis)
    ok(scalar(@body_nodes) >= 1, 'Found at least the Phi node in loop body');
    ok((grep { $_ eq $phi_i->id } @body_nodes), 'Phi node is in loop body');
};

subtest 'Execute simple counter loop: while (i < 3) { i++ } return i' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build IR for: i = 0; while (i < 3) { i = i + 1; } return i;
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $init_i = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_i);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    my $phi_i = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_i->id],
    );
    $graph->add_node($phi_i);

    my $const_3 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');
    $graph->add_node($const_3);

    my $lt = Chalk::IR::Node::LT->new(
        left => $phi_i,
        right => $const_3,
    );
    $graph->add_node($lt);

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$loop->id, $lt->id],
        condition_id => $lt->id,
        condition => $lt,
    );
    $graph->add_node($if_node);

    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    $graph->add_node($proj_true);

    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    $graph->add_node($proj_false);

    my $const_1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node::Add->new(
        left => $phi_i,
        right => $const_1,
    );
    $graph->add_node($add);

    # Complete phi backedge with the incremented value
    push $phi_i->inputs->@*, $add->id;
    # Add backedge to loop from true projection
    push $loop->inputs->@*, $proj_true->id;

    # Return on false path
    my $return_node = Chalk::IR::Node::Return->new(
        control => $proj_false,
        value => $phi_i,
    );
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();

    is($result, 3, 'Counter loop executes: while (i < 3) returns 3');
};

subtest 'Execute accumulator loop: sum = 0; i = 0; while (i < 5) { sum += i; i++; } return sum' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build IR for: sum = 0; i = 0; while (i < 5) { sum = sum + i; i = i + 1; } return sum;
    # Expected: 0+1+2+3+4 = 10
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $init_sum = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_sum);

    my $init_i = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_i);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    # Two Phi nodes: one for sum, one for i
    my $phi_sum = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_sum->id],
    );
    $graph->add_node($phi_sum);

    my $phi_i = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_i->id],
    );
    $graph->add_node($phi_i);

    my $const_5 = Chalk::IR::Node::Constant->new(value => 5, type => 'int');
    $graph->add_node($const_5);

    my $lt = Chalk::IR::Node::LT->new(
        left => $phi_i,
        right => $const_5,
    );
    $graph->add_node($lt);

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$loop->id, $lt->id],
        condition_id => $lt->id,
        condition => $lt,
    );
    $graph->add_node($if_node);

    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    $graph->add_node($proj_true);

    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    $graph->add_node($proj_false);

    my $const_1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_1);

    # sum = sum + i
    my $add_sum = Chalk::IR::Node::Add->new(
        left => $phi_sum,
        right => $phi_i,
    );
    $graph->add_node($add_sum);

    # i = i + 1
    my $add_i = Chalk::IR::Node::Add->new(
        left => $phi_i,
        right => $const_1,
    );
    $graph->add_node($add_i);

    # Complete phi backedges
    push $phi_sum->inputs->@*, $add_sum->id;
    push $phi_i->inputs->@*, $add_i->id;

    # Add backedge to loop from true projection
    push $loop->inputs->@*, $proj_true->id;

    # Return sum on false path
    my $return_node = Chalk::IR::Node::Return->new(
        control => $proj_false,
        value => $phi_sum,
    );
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();

    is($result, 10, 'Accumulator loop: sum of 0..4 = 10');
};

subtest 'Iteration limit prevents infinite loops' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build an infinite loop (backedge always active)
    # This should trigger the iteration limit
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $init_i = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_i);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    my $phi_i = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_i->id],
    );
    $graph->add_node($phi_i);

    my $const_1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_1);

    # Always true condition
    my $const_true = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_true);

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$loop->id, $const_true->id],
        condition_id => $const_true->id,
        condition => $const_true,
    );
    $graph->add_node($if_node);

    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    $graph->add_node($proj_true);

    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    $graph->add_node($proj_false);

    my $add = Chalk::IR::Node::Add->new(
        left => $phi_i,
        right => $const_1,
    );
    $graph->add_node($add);

    # Complete phi backedge
    push $phi_i->inputs->@*, $add->id;
    push $loop->inputs->@*, $proj_true->id;

    my $return_node = Chalk::IR::Node::Return->new(
        control => $proj_false,
        value => $phi_i,
    );
    $graph->add_node($return_node);

    # Create interpreter with a low iteration limit for faster testing
    my $interp = Chalk::Interpreter::CEKDataflow->new(
        graph => $graph,
        max_iterations => 100,  # Low limit for test speed
    );

    my $error;
    eval {
        $interp->execute();
    };
    $error = $@;

    like($error, qr/Loop exceeded iteration limit/, 'Infinite loop triggers iteration limit');
};
