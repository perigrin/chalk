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
