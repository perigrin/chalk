#!/usr/bin/env perl
# ABOUTME: Test IR generation pipeline with GVN optimization for simple Chalk programs
# ABOUTME: Verifies semantic actions build IR during parsing and GVN deduplicates intermediate nodes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use lib 'lib';
use lib 'tools';
use Test::More;

# Test that IR Builder can be used during parsing
{
    use Chalk::Parser;
    use Chalk::Grammar;
    use Chalk::IR::Builder;
    use Chalk::IR::Validator;
    use Chalk::IR::Optimizer::GVN;
    use Chalk::Semiring::Semantic;

    # Load Chalk grammar with semantic actions
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    # Create IR Builder
    my $builder = Chalk::IR::Builder->new();

    # Create Semantic semiring with Builder in environment
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => $grammar,
        env => { ir_builder => $builder }
    );

    # Create parser
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Simple program: just a variable assignment
    my $program = q{
        use 5.42.0;
        my $x = 42;
    };

    # Parse the program
    my $result = $parser->parse_string($program);
    ok($result, 'Simple program parses successfully');

    # Get the IR graph (nodes created during parsing)
    my $graph = $builder->graph;
    ok($graph, 'Builder has a graph');

    # Debug: Check nodes before optimization
    my $nodes_before = $graph->nodes;
    diag("Before GVN: " . scalar(keys %$nodes_before) . " total nodes");

    # Run GVN to deduplicate nodes from intermediate parse completions
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};
    my $metrics = $gvn_result->{metrics};

    # Debug: Check after GVN
    my $nodes_after = $graph->nodes;
    diag("After GVN: " . scalar(keys %$nodes_after) . " nodes (eliminated " . $metrics->{nodes_eliminated} . ")");
    diag("Node types after GVN:");
    for my $node (values %$nodes_after) {
        diag("  " . $node->op . " (node " . $node->id . ")");
    }

    # Verify graph has some nodes (should have Start, Store for assignment, etc.)
    my $node_count = $graph->node_count;
    ok($node_count > 0, "Graph has nodes (got $node_count)");

    # Verify graph has Start node
    my $entry = $graph->entry;
    ok($entry, 'Graph has entry node');

    my $start_node = $graph->get_node($entry);
    ok($start_node, 'Can retrieve start node');
    is($start_node->op, 'Start', 'Entry node is a Start node');

    # Verify graph uses SSA-style variables (no Store nodes for local variables)
    # Variables should be direct data flow edges, not memory operations
    my $nodes = $graph->nodes;
    my @store_nodes = grep { $_->op eq 'Store' } values %$nodes;
    is(scalar(@store_nodes), 0, 'Graph uses SSA-style variables (no Store nodes for locals)');

    # Validate the IR (should pass after GVN deduplication)
    use Chalk::IR::Validator;
    my $validator = Chalk::IR::Validator->new();
    my ($valid, $errors) = $validator->validate_all($graph);

    if (!$valid) {
        diag("Validation errors:");
        for my $error (@$errors) {
            diag("  $error");
        }
    }

    ok($valid, 'Generated IR passes validation after GVN');
}

done_testing();
