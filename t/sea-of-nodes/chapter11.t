#!/usr/bin/env perl
# ABOUTME: Test Sea of Nodes Chapter 11 - Global Code Motion infrastructure
# ABOUTME: Validates CFG representation, basic blocks, and dominator tree

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'CFG: basic Start node as CFGNode' => sub {
    # Start is a CFGNode and starts a basic block
    my $start = Chalk::IR::Node::Start->new();

    ok $start->isa('Chalk::IR::Node::CFGNode'), 'Start is a CFGNode';
    ok $start->isCFG, 'Start isCFG returns true';
};

subtest 'CFG: Return node as CFGNode' => sub {
    # Return is a CFGNode and ends a basic block
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42)
    );
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $const);

    ok $ret->isa('Chalk::IR::Node::CFGNode'), 'Return is a CFGNode';
    ok $ret->isCFG, 'Return isCFG returns true';
};

subtest 'Dominator: Start dominates everything' => sub {
    # In any program, Start dominates all other nodes
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42)
    );
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $const);

    # Start dominates itself
    ok $start->dominates($start), 'Start dominates itself';

    # Start dominates Return
    ok $start->dominates($ret), 'Start dominates Return';
};

subtest 'Dominator: immediate dominator chain' => sub {
    # Test idom (immediate dominator) calculation
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42)
    );
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $const);

    # Return's immediate dominator should be Start
    my $ret_idom = $ret->idom;
    ok $ret_idom, 'Return has an immediate dominator';
    is $ret_idom, $start, 'Return idom is Start';

    # Start has no immediate dominator (it's the root)
    is $start->idom, undef, 'Start has no immediate dominator';
};

subtest 'Dominator: depth caching' => sub {
    # Test that dominator depth is cached correctly
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42)
    );
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $const);

    # Get dominator depths
    my $start_depth = $start->idepth;
    my $ret_depth = $ret->idepth;

    ok defined($start_depth), 'Start has dominator depth';
    ok defined($ret_depth), 'Return has dominator depth';
    ok $ret_depth > $start_depth, 'Return depth is greater than Start depth';
};

subtest 'Basic blocks: CFG traversal' => sub {
    # Test basic block identification through CFG traversal
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42)
    );
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $const);

    # Get basic blocks from graph
    my $graph = Chalk::IR::Graph->instance();
    my $blocks = $graph->basic_blocks();

    ok $blocks, 'Graph returns basic blocks';
    ok ref($blocks) eq 'ARRAY', 'Basic blocks is an array';
    ok scalar(@$blocks) > 0, 'At least one basic block exists';
};
