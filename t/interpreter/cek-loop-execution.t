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
