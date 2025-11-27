#!/usr/bin/env perl
# ABOUTME: Test content-addressable node IDs fix duplicate IR nodes
# ABOUTME: Simple test to verify content-addressable IDs work correctly

use 5.42.0;
use experimental 'class';
use lib 'lib';

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Semantic;

# Build grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Can't open grammar: $!";
my $bnf = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');

# Create parser with Semantic semiring (builds IR)
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);
my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);

# Simple test: two return statements
my $code = <<'END_CODE';
if (1) { return 42; }
return 99;
END_CODE

print "Parsing code:\n$code\n";

my $result = $parser->parse_string($code);

if (!$result) {
    print "FAIL: Parse failed\n";
    exit 1;
}

# Get IR builder and graph
my $builder = $semiring->env->{ir_builder};
if (!$builder) {
    print "FAIL: No IR builder in environment\n";
    exit 1;
}

my $graph = $builder->graph;
if (!$graph) {
    print "FAIL: No graph in builder\n";
    exit 1;
}

# Count Return nodes
my @returns = grep { $_->can('op') && $_->op eq 'Return' } values %{$graph->nodes};

print "\nResults:\n";
print "  Total nodes: " . $graph->node_count() . "\n";
print "  Return nodes: " . scalar(@returns) . "\n";

# Show all node IDs
print "\nAll node IDs:\n";
for my $id (sort keys %{$graph->nodes}) {
    my $node = $graph->nodes->{$id};
    my $op = $node->can('op') ? $node->op : 'Unknown';
    print "  $id ($op)\n";
}

# Expected: 2 Return nodes (one per return statement)
my $expected = 2;
my $actual = scalar(@returns);

if ($actual == $expected) {
    print "\nSUCCESS: Got exactly $expected Return nodes (no duplicates!)\n";
    exit 0;
} else {
    print "\nFAIL: Expected $expected Return nodes, got $actual\n";
    exit 1;
}
