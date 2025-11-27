#!/usr/bin/env perl
# ABOUTME: Debug script for issue #195 test 51 failure
# ABOUTME: Minimal reproduction of "Region node: no active input path" error
use 5.42.0;
use experimental qw(class);
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use Data::Dumper;
use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::IR::Builder;
use Chalk::IR::Node::Scope;
use Chalk::Semiring::Semantic;

# Test code from failing test 51
my $code = 'my $x = 5; if ($x > 0) { return 42; } return -42;';

print "Parsing: $code\n\n";

# Load Chalk grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf( $bnf_content, 'Program', 'Chalk' );

# Create parser with IR builder
my $builder = Chalk::IR::Builder->new();
my $scope = Chalk::IR::Node::Scope->new();
my $semiring = Chalk::Semiring::Semantic->new(
    grammar => $grammar,
    env => { ir_builder => $builder, scope => $scope }
);

my $parser = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $semiring
);

# Parse the code
my $result = $parser->parse_string( $code );

if (!$result) {
    die "Parse failed\n";
}

print "Parse successful!\n";

# Get the IR graph from the builder
my $graph = $builder->graph;

if (!$graph) {
    die "No IR graph returned\n";
}

print "IR graph obtained\n";

# Prune to winning parse
if ( $result->can('context') ) {
    my $ctx = $result->context;
    if ( $ctx->can('focus') ) {
        my $winning_node = $ctx->focus;
        if ( $winning_node && $winning_node->can('id') ) {
            eval { $graph->prune_to_reachable( $winning_node->id ) };
            if ($@) {
                die "Prune error: $@\n";
            }
        }
    }
}

# Dump the graph structure
print "\n=== IR Graph Structure ===\n";
print "Graph type: ", ref($graph), "\n";

# Get all nodes
my @all_nodes = $graph->get_all_nodes();
print "\nTotal nodes: ", scalar(@all_nodes), "\n\n";

# Count node types
my %node_types;
for my $node (@all_nodes) {
    my $type = ref($node);
    $type =~ s/^Chalk::IR::Node:://;
    $node_types{$type}++;
}

print "Node type counts:\n";
for my $type (sort keys %node_types) {
    print "  $type: $node_types{$type}\n";
}

# Look for statements in Program node
print "\n=== Program Statements ===\n";
if ($graph->can('statements')) {
    my @stmts = @{$graph->statements // []};
    print "Number of statements: ", scalar(@stmts), "\n";
    for my $i (0 .. $#stmts) {
        my $stmt = $stmts[$i];
        print "  Statement $i: ", $stmt->id, " (", ref($stmt), ")\n";
    }
} else {
    print "Graph doesn't have statements method\n";
}

print "\n=== Attempting CEK Execution ===\n";
use Chalk::Interpreter::CEKDataflow;

my $cek_result = eval {
    my $cek_interp = Chalk::Interpreter::CEKDataflow->new( graph => $graph );
    $cek_interp->execute();
};

if ($@) {
    print "CEK execution FAILED:\n$@\n";
} else {
    print "CEK execution succeeded: $cek_result\n";
}

# Compare to Perl execution
my $perl_result = eval $code;
print "\nPerl execution result: $perl_result\n";
