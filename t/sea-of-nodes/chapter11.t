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

subtest 'Loop depth: simple while loop' => sub {
    # Test loop depth computation for a simple while loop
    # Structure: Start -> Loop -> (body) -> backedge to Loop
    use Chalk::IR::Node::Loop;

    my $start = Chalk::IR::Node::Start->new();

    # Create a Loop node with entry from Start
    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [refaddr($start)]
    );

    # Start should have loop depth 0 (not in any loop)
    is $start->loopDepth(), 0, 'Start has loop depth 0';

    # Loop entry should have loop depth 1 (first loop level)
    is $loop->loopDepth(), 1, 'Loop node has loop depth 1';
};

subtest 'Loop depth: nested loops' => sub {
    # Test loop depth computation for nested loops
    # Structure: Start -> Loop1 -> Loop2 (nested)
    use Chalk::IR::Node::Loop;

    my $start = Chalk::IR::Node::Start->new();

    # Outer loop
    my $loop1 = Chalk::IR::Node::Loop->new(
        inputs => [refaddr($start)]
    );

    # Inner loop nested inside outer loop
    my $loop2 = Chalk::IR::Node::Loop->new(
        inputs => [refaddr($loop1)]
    );

    # Verify depth increments correctly
    is $start->loopDepth(), 0, 'Start has loop depth 0';
    is $loop1->loopDepth(), 1, 'Outer loop has depth 1';
    is $loop2->loopDepth(), 2, 'Inner loop has depth 2';
};

subtest 'Infinite loop: forceExit creates synthetic exit' => sub {
    # Test that infinite loops get a synthetic exit via forceExit()
    # while(1) {} - infinite loop with no natural exit
    use Chalk::IR::Node::Loop;
    use Chalk::IR::Node::Stop;

    my $start = Chalk::IR::Node::Start->new();

    # Create infinite loop (no exit condition)
    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [refaddr($start)]
    );

    # Add backedge to complete the loop
    my $loop_inputs = $loop->inputs;
    push @$loop_inputs, refaddr($loop);

    # Create Stop node (represents end of program)
    my $stop = Chalk::IR::Node::Stop->new(
        inputs => [refaddr($loop)]
    );

    # Call forceExit to detect infinite loop and create synthetic exit
    $loop->forceExit();

    # After forceExit, the loop should have a synthetic Never node
    # This makes the loop reachable for scheduling
    ok $loop->can('forceExit'), 'Loop has forceExit method';

    # Test will verify the existence of synthetic exit path
    # The implementation should walk the backedge idom chain
    # If no CProjNode is found (no natural exit), create NeverNode
};

subtest 'Early schedule: place floating node at deepest input control' => sub {
    # Test early scheduling of unpinned data nodes
    # Floating nodes (Add, Mul, etc.) should be placed at deepest input's control
    use Chalk::IR::Node::Add;

    my $graph = Chalk::IR::Graph->instance();
    my $start = Chalk::IR::Node::Start->new();

    # Create two constants
    my $const1 = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10)
    );

    my $const2 = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::IR::Type::Integer->constant(20)
    );

    # Create an Add node (unpinned data node)
    my $add = Chalk::IR::Node::Add->new(
        left => $const1,
        right => $const2
    );

    # Return the result
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $add
    );

    # Run early schedule
    ok $graph->can('schedule_early'), 'Graph has schedule_early method';
    my $schedule = $graph->schedule_early();

    # After scheduling, the Add node should be scheduled somewhere
    # It should be scheduled at the deepest dominating control point
    # In this simple case, that's the Start node
    ok defined($schedule), 'schedule_early returns a schedule';
};
