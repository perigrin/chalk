#!/usr/bin/env perl
# ABOUTME: Test IR generation for string concatenation operator (.) - Issue #110
# ABOUTME: Verifies semantic action creates StrConcat nodes when parsing string concatenation
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use lib 'lib';
use lib 'tools';
use Test::More;

# Test that IR Builder generates StrConcat nodes for string concatenation
{
    use Chalk::Parser;
    use Chalk::Grammar;
    use Chalk::IR::Builder;
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

    # Test basic string concatenation: "foo" . "bar"
    my $program = q{
        use 5.42.0;
        my $greeting = "Hello" . " " . "World";
    };

    # Parse the program
    my $result = $parser->parse_string($program);
    ok($result, 'String concatenation program parses successfully');

    # Get the IR graph
    my $graph = $builder->graph;
    ok($graph, 'Builder has a graph');

    # Check for StrConcat nodes
    my $nodes = $graph->nodes;
    my @str_concat_nodes = grep { $_->op eq 'StrConcat' } values %$nodes;

    ok(scalar(@str_concat_nodes) > 0, 'Graph contains at least one StrConcat node');
    cmp_ok(scalar(@str_concat_nodes), '>=', 2, 'Graph contains at least 2 StrConcat nodes for chained concatenation');

    # Verify a StrConcat node has correct structure
    my $concat_node = $str_concat_nodes[0];
    ok($concat_node->inputs, 'StrConcat node has inputs');
    is(scalar(@{$concat_node->inputs}), 3, 'StrConcat node has 3 inputs (control, left, right)');

    # Verify attributes structure
    ok($concat_node->attributes, 'StrConcat node has attributes');
    ok($concat_node->attributes->{left}, 'StrConcat has left attribute');
    ok($concat_node->attributes->{right}, 'StrConcat has right attribute');
    is($concat_node->attributes->{left}{op}, 'NodeRef', 'Left attribute is a NodeRef');
    is($concat_node->attributes->{right}{op}, 'NodeRef', 'Right attribute is a NodeRef');
}

# Test chained concatenation
{
    use Chalk::Parser;
    use Chalk::Grammar;
    use Chalk::IR::Builder;
    use Chalk::Semiring::Semantic;

    # Load Chalk grammar
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    # Create IR Builder
    my $builder = Chalk::IR::Builder->new();

    # Create Semantic semiring
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

    # Test chained concatenation
    my $program = q{
        use 5.42.0;
        my $a = "foo";
        my $b = "bar";
        my $c = "baz";
        my $result = $a . $b . $c;
    };

    # Parse the program
    my $result = $parser->parse_string($program);
    ok($result, 'Chained concatenation program parses successfully');

    # Get the IR graph
    my $graph = $builder->graph;

    # Check for StrConcat nodes
    my $nodes = $graph->nodes;
    my @str_concat_nodes = grep { $_->op eq 'StrConcat' } values %$nodes;

    cmp_ok(scalar(@str_concat_nodes), '>=', 2, 'Chained concatenation creates at least 2 StrConcat nodes');
}

done_testing();
