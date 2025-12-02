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
