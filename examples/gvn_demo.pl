#!/usr/bin/env perl
# ABOUTME: Demonstration of Global Value Numbering optimization
# ABOUTME: Shows GVN eliminating redundant computations that peephole optimization misses

use v5.42;
use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Graph;
use Chalk::IR::Optimizer;

say "=== Global Value Numbering (GVN) Demo ===\n";

# Build example IR: return (a+b) + (a+b)
# This computes a+b twice unnecessarily
my $graph = Chalk::IR::Graph->new();

say "Building IR for: (a+b) + (a+b) where a=5, b=10\n";

# Start node
my $start = Chalk::IR::Node->new(
    id => 'node_0',
    op => 'Start',
    inputs => [],
    attributes => { function => 'main' }
);
$graph->add_node($start);

# Constants
my $const_a = Chalk::IR::Node->new(
    id => 'node_1',
    op => 'Constant',
    inputs => [],
    attributes => { value => 5, type => 'Int' }
);
$graph->add_node($const_a);

my $const_b = Chalk::IR::Node->new(
    id => 'node_2',
    op => 'Constant',
    inputs => [],
    attributes => { value => 10, type => 'Int' }
);
$graph->add_node($const_b);

# First a+b
my $add1 = Chalk::IR::Node->new(
    id => 'node_3',
    op => 'Add',
    inputs => ['node_1', 'node_2'],
    attributes => {
        left => { op => 'NodeRef', node_id => 'node_1' },
        right => { op => 'NodeRef', node_id => 'node_2' }
    }
);
$graph->add_node($add1);

# Second a+b (duplicate!)
my $add2 = Chalk::IR::Node->new(
    id => 'node_4',
    op => 'Add',
    inputs => ['node_1', 'node_2'],
    attributes => {
        left => { op => 'NodeRef', node_id => 'node_1' },
        right => { op => 'NodeRef', node_id => 'node_2' }
    }
);
$graph->add_node($add2);

# (a+b) + (a+b)
my $add3 = Chalk::IR::Node->new(
    id => 'node_5',
    op => 'Add',
    inputs => ['node_3', 'node_4'],
    attributes => {
        left => { op => 'NodeRef', node_id => 'node_3' },
        right => { op => 'NodeRef', node_id => 'node_4' }
    }
);
$graph->add_node($add3);

# Return
my $return = Chalk::IR::Node->new(
    id => 'node_6',
    op => 'Return',
    inputs => ['node_0', 'node_5'],
    attributes => {}
);
$graph->add_node($return);

say "Before optimization:";
say "  Nodes: " . $graph->node_count;
say "  Operations: 3 Add nodes (node_3, node_4, node_5)";
say "  Note: node_3 and node_4 compute the same value (a+b)\n";

# Run GVN optimization
my $result = Chalk::IR::Optimizer->run_gvn($graph);
my $optimized_graph = $result->{graph};
my $metrics = $result->{metrics};

say "After GVN optimization:";
say "  Nodes: " . $optimized_graph->node_count;
say "  Eliminated: " . $metrics->{nodes_eliminated} . " duplicate node(s)";

if (%{$metrics->{redirections}}) {
    say "  Redirections:";
    for my $dup (sort keys %{$metrics->{redirections}}) {
        my $canon = $metrics->{redirections}{$dup};
        say "    $dup -> $canon (duplicate eliminated)";
    }
}

say "\n=== Commutativity Demo ===\n";

# Build example: a+b and b+a (should be recognized as same)
my $graph2 = Chalk::IR::Graph->new();

say "Building IR for: (a+b) vs (b+a) where a=3, b=7\n";

my $start2 = Chalk::IR::Node->new(
    id => 'node_0',
    op => 'Start',
    inputs => [],
    attributes => { function => 'main' }
);
$graph2->add_node($start2);

my $const_a2 = Chalk::IR::Node->new(
    id => 'node_1',
    op => 'Constant',
    inputs => [],
    attributes => { value => 3, type => 'Int' }
);
$graph2->add_node($const_a2);

my $const_b2 = Chalk::IR::Node->new(
    id => 'node_2',
    op => 'Constant',
    inputs => [],
    attributes => { value => 7, type => 'Int' }
);
$graph2->add_node($const_b2);

# a + b
my $add_ab = Chalk::IR::Node->new(
    id => 'node_3',
    op => 'Add',
    inputs => ['node_1', 'node_2'],
    attributes => {
        left => { op => 'NodeRef', node_id => 'node_1' },
        right => { op => 'NodeRef', node_id => 'node_2' }
    }
);
$graph2->add_node($add_ab);

# b + a (commuted - should be recognized as same!)
my $add_ba = Chalk::IR::Node->new(
    id => 'node_4',
    op => 'Add',
    inputs => ['node_2', 'node_1'],  # Reversed!
    attributes => {
        left => { op => 'NodeRef', node_id => 'node_2' },
        right => { op => 'NodeRef', node_id => 'node_1' }
    }
);
$graph2->add_node($add_ba);

my $return2 = Chalk::IR::Node->new(
    id => 'node_5',
    op => 'Return',
    inputs => ['node_0', 'node_4'],
    attributes => {}
);
$graph2->add_node($return2);

say "Before optimization:";
say "  Nodes: " . $graph2->node_count;
say "  node_3: a + b";
say "  node_4: b + a (commuted, but mathematically equivalent)\n";

my $result2 = Chalk::IR::Optimizer->run_gvn($graph2);
my $optimized_graph2 = $result2->{graph};
my $metrics2 = $result2->{metrics};

say "After GVN optimization:";
say "  Nodes: " . $optimized_graph2->node_count;
say "  Eliminated: " . $metrics2->{nodes_eliminated} . " duplicate node(s)";
say "  GVN recognized that a+b and b+a are equivalent!\n";

if (%{$metrics2->{redirections}}) {
    say "  Redirections:";
    for my $dup (sort keys %{$metrics2->{redirections}}) {
        my $canon = $metrics2->{redirections}{$dup};
        say "    $dup -> $canon";
    }
}

say "\n=== Complex Expression Demo ===\n";

# Build: (a*b) + (a*b) where both multiplies are redundant
my $graph3 = Chalk::IR::Graph->new();

say "Building IR for: (a*b) + (a*b) where a=4, b=6\n";

my $start3 = Chalk::IR::Node->new(
    id => 'node_0',
    op => 'Start',
    inputs => [],
    attributes => { function => 'main' }
);
$graph3->add_node($start3);

my $const_a3 = Chalk::IR::Node->new(
    id => 'node_1',
    op => 'Constant',
    inputs => [],
    attributes => { value => 4, type => 'Int' }
);
$graph3->add_node($const_a3);

my $const_b3 = Chalk::IR::Node->new(
    id => 'node_2',
    op => 'Constant',
    inputs => [],
    attributes => { value => 6, type => 'Int' }
);
$graph3->add_node($const_b3);

# First a*b
my $mul1 = Chalk::IR::Node->new(
    id => 'node_3',
    op => 'Multiply',
    inputs => ['node_1', 'node_2'],
    attributes => {
        left => { op => 'NodeRef', node_id => 'node_1' },
        right => { op => 'NodeRef', node_id => 'node_2' }
    }
);
$graph3->add_node($mul1);

# Second a*b (duplicate!)
my $mul2 = Chalk::IR::Node->new(
    id => 'node_4',
    op => 'Multiply',
    inputs => ['node_1', 'node_2'],
    attributes => {
        left => { op => 'NodeRef', node_id => 'node_1' },
        right => { op => 'NodeRef', node_id => 'node_2' }
    }
);
$graph3->add_node($mul2);

# (a*b) + (a*b)
my $add_final = Chalk::IR::Node->new(
    id => 'node_5',
    op => 'Add',
    inputs => ['node_3', 'node_4'],
    attributes => {
        left => { op => 'NodeRef', node_id => 'node_3' },
        right => { op => 'NodeRef', node_id => 'node_4' }
    }
);
$graph3->add_node($add_final);

my $return3 = Chalk::IR::Node->new(
    id => 'node_6',
    op => 'Return',
    inputs => ['node_0', 'node_5'],
    attributes => {}
);
$graph3->add_node($return3);

say "Before optimization:";
say "  Nodes: " . $graph3->node_count;
say "  Common subexpression: a*b computed twice\n";

my $result3 = Chalk::IR::Optimizer->run_gvn($graph3);
my $optimized_graph3 = $result3->{graph};
my $metrics3 = $result3->{metrics};

say "After GVN optimization:";
say "  Nodes: " . $optimized_graph3->node_count;
say "  Eliminated: " . $metrics3->{nodes_eliminated} . " duplicate node(s)";
say "  Result: Single computation of a*b reused!\n";

say "=== Summary ===\n";
say "GVN optimization provides:";
say "  * Elimination of redundant arithmetic operations";
say "  * Common subexpression elimination";
say "  * Recognition of commutative equivalence (a+b === b+a)";
say "  * Works across the entire function (global scope)";
say "  * Idempotent (running twice has no additional effect)";
say "";
say "This goes beyond peephole optimization, which only looks at";
say "individual nodes in isolation. GVN considers the entire graph";
say "structure to find equivalent computations.";
