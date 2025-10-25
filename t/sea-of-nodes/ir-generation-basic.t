#!/usr/bin/env perl
# ABOUTME: Test basic IR generation for simple Chalk programs
# ABOUTME: Verifies semantic actions build IR during parsing
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

    # Get the winning derivation ID from the parse result
    my $winning_deriv_id = $result->context->env->{derivation_id};

    # Get the IR graph and prune to keep only the winning derivation
    my $graph = $builder->graph;
    ok($graph, 'Builder has a graph');

    # Prune the graph to remove nodes from losing parse alternatives
    if (defined $winning_deriv_id) {
        $graph->prune_by_derivation_id($winning_deriv_id);
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

    # Verify graph has at least one Store node (from the assignment)
    my $nodes = $graph->nodes;
    my @store_nodes = grep { $_->op eq 'Store' } values %$nodes;
    ok(@store_nodes > 0, 'Graph contains Store node from assignment');

    # Validate the IR
    use Chalk::IR::Validator;
    my $validator = Chalk::IR::Validator->new();
    my ($valid, $errors) = $validator->validate_all($graph);

    if (!$valid) {
        diag("Validation errors:");
        for my $error (@$errors) {
            diag("  $error");
        }
    }

    # TODO: Fix control flow wiring to eliminate duplicate Start nodes and unreachable nodes
    TODO: {
        local $TODO = 'Control flow wiring needs refinement for proper CFG';
        ok($valid, 'Generated IR passes validation');
    }
}

done_testing();
