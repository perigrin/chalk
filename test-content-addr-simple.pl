#!/usr/bin/env perl
# ABOUTME: Simple direct test of content-addressable node IDs
# ABOUTME: Tests that identical nodes get the same ID and automatically deduplicate

use 5.42.0;
use experimental 'class';
use lib 'lib';

use Chalk::IR::Builder;
use Chalk::IR::Graph;

# Create builder (graph is created internally)
my $builder = Chalk::IR::Builder->new();
my $graph = $builder->graph;

print "Testing content-addressable node IDs...\n\n";

# Create same constant multiple times (simulating multiple Earley completions)
print "Creating const_Int_42 three times:\n";
my $const1 = $builder->build_constant_node(42, 'Int');
my $const2 = $builder->build_constant_node(42, 'Int');
my $const3 = $builder->build_constant_node(42, 'Int');

print "  First:  ID = " . $const1->id . "\n";
print "  Second: ID = " . $const2->id . "\n";
print "  Third:  ID = " . $const3->id . "\n";

# Add all three to pending
$graph->add_node($const1);
$graph->add_node($const2);
$graph->add_node($const3);

# Materialize
$graph->materialize_pending_nodes();

# Check how many nodes are in the graph
my $pending = $graph->get_pending_all();
my $pending_count = scalar(keys %$pending);
my $graph_count = $graph->node_count();

print "\nAfter materialization:\n";
print "  Pending nodes: $pending_count\n";
print "  Graph nodes: $graph_count\n";

# Create returns from the same constant
print "\nCreating return_const_Int_42 three times:\n";
my $ret1 = $builder->build_return_node($const1);
my $ret2 = $builder->build_return_node($const2);
my $ret3 = $builder->build_return_node($const3);

print "  First:  ID = " . $ret1->id . "\n";
print "  Second: ID = " . $ret2->id . "\n";
print "  Third:  ID = " . $ret3->id . "\n";

# Add returns to pending
$graph->clear_pending();
$graph->add_node($ret1);
$graph->add_node($ret2);
$graph->add_node($ret3);

# Materialize again
$graph->materialize_pending_nodes();

$pending = $graph->get_pending_all();
$pending_count = scalar(keys %$pending);
$graph_count = $graph->node_count();

print "\nAfter second materialization:\n";
print "  Pending nodes: $pending_count\n";
print "  Total graph nodes: $graph_count\n";

# Count Return nodes
my @returns = grep { $_->can('op') && $_->op eq 'Return' } values %{$graph->nodes};
print "  Return nodes: " . scalar(@returns) . "\n";

# Test result
if ($const1->id eq $const2->id && $const2->id eq $const3->id) {
    print "\nSUCCESS: Identical constants got same ID!\n";
} else {
    print "\nFAIL: Identical constants got different IDs\n";
    exit 1;
}

if ($ret1->id eq $ret2->id && $ret2->id eq $ret3->id) {
    print "SUCCESS: Identical returns got same ID!\n";
} else {
    print "FAIL: Identical returns got different IDs\n";
    exit 1;
}

if ($graph_count == 2) {  # 1 constant + 1 return
    print "SUCCESS: Graph has exactly 2 nodes (1 constant + 1 return) - duplicates eliminated!\n";
    exit 0;
} else {
    print "FAIL: Expected 2 nodes in graph, got $graph_count\n";
    exit 1;
}
