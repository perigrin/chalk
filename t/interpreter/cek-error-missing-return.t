#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter error handling for missing Return node
# ABOUTME: Tests that CEKDataflow dies when IR graph has no Return node
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 3;
use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;

# Tests use content-addressable IDs computed from node contents
# Object references are used for graph traversal

# Test: Empty graph should die
{
    my $graph = Chalk::IR::Graph->new();
    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);

    eval { $interp->execute(); };
    like($@, qr/No Return node found/, 'Dies on empty graph');
}

# Test: Graph with nodes but no Return node should die
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $const = Chalk::IR::Node::Constant->new(value => 42, type => 'int');

    $graph->add_node($start);
    $graph->add_node($const);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    eval { $interp->execute(); };
    like($@, qr/No Return node found/, 'Dies when no Return node exists');
}

# Test: Graph with Return node should succeed (not die)
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $const = Chalk::IR::Node::Constant->new(value => 42, type => 'int');
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $const,
    );

    $graph->add_node($start);
    $graph->add_node($const);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result;
    eval { $result = $interp->execute(); };
    is($@, '', 'Does not die when Return node exists');
}
