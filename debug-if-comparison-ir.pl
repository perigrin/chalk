#!/usr/bin/env perl
# ABOUTME: Debug script to trace IR generation and execution for if-comparison
# ABOUTME: Tests 'my $x = 10; if ($x > 5) { return 1; } return 0;'

use 5.42.0;
use lib 'lib';
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::Semantic;
use Chalk::ParseForest;
use Chalk::IR::Node::Scope;
use Chalk::IR::Graph;
use Chalk::Interpreter::CEKDataflow;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;

# Load grammar from BNF
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

my %env = (
    patterns => {},
    grammar_name => 'Chalk'
);

# Initialize scope
$env{scope} = Chalk::IR::Node::Scope->new();

my %shared_context = (
    forest => Chalk::ParseForest->new()
);

my $semiring = Chalk::Semiring::Semantic->new(
    env => \%env,
    grammar => $grammar,
    shared_context => \%shared_context
);

my $parser = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $semiring
);

my $code = 'my $x = 10; if ($x > 5) { return 1; } return 0;';

say "=== Parsing: $code ===";
say "";

my $result = $parser->parse_string($code);

if ($result) {
    my $ctx = $result->context;
    my $focus = $ctx->focus;

    say "=== Parse Result ===";
    say "Result type: " . (ref($focus) || 'scalar');

    if (ref($focus) && $focus->can('id')) {
        say "Result ID: " . $focus->id;
        say "Result Op: " . ($focus->can('op') ? $focus->op : 'N/A');
    }

    # Try to get the graph from scope
    my $scope = $ctx->env->{scope};
    if ($scope && $scope->can('graph') && $scope->graph) {
        my $graph = $scope->graph;
        say "";
        say "=== IR Graph Nodes ===";
        my $nodes = $graph->nodes;
        for my $node_id (sort keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            say "Node: $node_id";
            say "  Op: " . $node->op;
            say "  Inputs: [" . join(", ", $node->inputs->@*) . "]";
            if ($node->can('to_hash')) {
                my $h = $node->to_hash;
                if ($h->{attributes}) {
                    say "  Attrs: " . Dumper($h->{attributes});
                }
            }
        }

        say "";
        say "=== Executing IR ===";
        my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
        $interp->initialize_stepping();

        my $step_count = 0;
        my $max_steps = 50;
        while ($step_count < $max_steps) {
            my $step_result = $interp->step();
            $step_count++;

            say "Step $step_count: " . ($step_result->{node_id} // 'NONE') .
                " (" . ($step_result->{node_op} // '?') . ") = " .
                (defined($step_result->{value}) ? $step_result->{value} : 'undef');

            if ($step_result->{done}) {
                say "";
                say "=== FINAL RESULT: " . (defined($step_result->{value}) ? $step_result->{value} : 'undef') . " ===";
                last;
            }
        }
    } else {
        # No graph, try building one
        say "";
        say "=== Building IR Graph ===";

        # Get all nodes from parse result
        my $graph = Chalk::IR::Graph->new();

        # Try to add nodes from focus
        if (ref($focus) && $focus->can('id')) {
            $graph->add_node($focus);
            say "Added node: " . $focus->id;
        }

        say "";
        say "=== IR Graph Nodes ===";
        my $nodes = $graph->nodes;
        for my $node_id (sort keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            say "Node: $node_id";
            say "  Op: " . $node->op;
            say "  Inputs: [" . join(", ", $node->inputs->@*) . "]";
        }
    }
} else {
    say "Parse failed!";
}
