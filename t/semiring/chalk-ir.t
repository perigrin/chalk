#!/usr/bin/env perl
# ABOUTME: Test Chalk::Semiring::ChalkIR - IR generation semiring wrapper
# ABOUTME: Verifies that ChalkIR properly encapsulates Composite(SPPF, Semantic) configuration
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use lib 'lib';
use Test::More;
use Chalk::Grammar;
use Chalk::Semiring::ChalkIR;

# Load Perl grammar from BNF
my $bnf_file = 'grammar/chalk.bnf';
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program');

# Test 1: ChalkIR can be instantiated with a grammar
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    ok($ir_semiring, 'ChalkIR semiring can be created');
    isa_ok($ir_semiring, 'Chalk::Semiring::ChalkIR', 'ChalkIR');
    # ChalkIR uses composition, not inheritance - it delegates to Composite
    ok($ir_semiring->composite, 'ChalkIR has a composite semiring');
    isa_ok($ir_semiring->composite, 'Chalk::Semiring::Composite', 'ChalkIR wraps a Composite');
}

# Test 2: ChalkIR has a builder accessor
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    my $builder = $ir_semiring->builder;
    ok($builder, 'ChalkIR has a builder');
    isa_ok($builder, 'Chalk::IR::Builder', 'Builder is an IR::Builder');
}

# Test 3: ChalkIR has mul_id and add_id (from Composite)
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    ok($ir_semiring->mul_id, 'ChalkIR has mul_id');
    ok($ir_semiring->add_id, 'ChalkIR has add_id');
    isa_ok($ir_semiring->mul_id, 'Chalk::Semiring::CompositeElement', 'mul_id is CompositeElement');
    isa_ok($ir_semiring->add_id, 'Chalk::Semiring::CompositeElement', 'add_id is CompositeElement');
}

# Test 4: ChalkIR can be used with Parser
{
    use Chalk::Parser;

    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $ir_semiring
    );

    ok($parser, 'Parser can be created with ChalkIR semiring');

    # Parsing tests with Perl grammar skipped - Perl grammar doesn't have semantic actions
    # ChalkIR requires semantic evaluation, which is only available in grammars with custom Rule classes
    # See tests 6-12 below for actual parsing tests using the Chalk grammar
}

# Test 5: ChalkIR grammar accessor works
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    is($ir_semiring->grammar, $grammar, 'ChalkIR returns the same grammar object');
}

# ==============================================================================
# NEW TESTS: Comprehensive parsing tests using Chalk grammar
# These tests verify that ChalkIR actually generates IR for Chalk code
# ==============================================================================

# Load Chalk grammar
my $chalk_bnf_file = 'grammar/chalk.bnf';
open my $chalk_fh, '<:utf8', $chalk_bnf_file or die "Cannot open $chalk_bnf_file: $!";
my $chalk_content = do { local $/; <$chalk_fh> };
close $chalk_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($chalk_content, 'Program', 'Chalk');

# Helper: Parse Chalk code with ChalkIR and return graph
sub parse_chalk_with_ir {
    my ($code) = @_;

    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $chalk_grammar);
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => $ir_semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $parse_result = $parser->parse_string($code);
    return (undef, undef, undef) unless $parse_result;

    my $builder = $ir_semiring->builder;
    my $graph = $builder->graph;

    # Prune to winning parse if possible
    if ($parse_result->can('context')) {
        my $ctx = $parse_result->context;
        if ($ctx && $ctx->can('focus')) {
            my $focus = $ctx->focus;
            if ($focus && $focus->can('id')) {
                eval { $graph->prune_to_reachable($focus->id) };
                return (undef, undef, undef) if $@;
            }
        }
    }

    return ($parse_result, $graph, $builder);
}

# Helper: Count nodes of specific types in graph
sub count_node_types {
    my ($graph, @types) = @_;

    my $nodes = $graph->nodes;
    my %counts;

    for my $type (@types) {
        my $count = grep {
            my $hash = $_->to_hash;
            $hash->{op} eq $type
        } values %$nodes;
        $counts{$type} = $count;
    }

    return \%counts;
}

# Test 6: Parse simple constant return and verify IR
{
    my $code = 'return 42;';
    my ($result, $graph, $builder) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: simple constant return parses');
    ok($graph, 'ChalkIR: graph exists after parsing constant');

    if ($graph) {
        my $nodes = $graph->nodes;
        my $node_count = scalar(keys %$nodes);
        ok($node_count > 0, "ChalkIR: graph has nodes (found $node_count)");

        my $counts = count_node_types($graph, 'Constant', 'Return', 'Start');
        ok($counts->{Constant} > 0, "ChalkIR: graph contains Constant node");
        ok($counts->{Start} > 0, "ChalkIR: graph contains Start node");
    }
}

# Test 7: Parse variable declaration and verify IR
{
    my $code = 'my $x = 5; return $x;';
    my ($result, $graph, $builder) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: variable declaration parses');
    ok($graph, 'ChalkIR: graph exists after parsing variable');

    if ($graph) {
        my $nodes = $graph->nodes;
        my $node_count = scalar(keys %$nodes);
        ok($node_count > 0, "ChalkIR: graph has nodes for variable (found $node_count)");

        my $counts = count_node_types($graph, 'Constant', 'Return');
        ok($counts->{Constant} > 0, "ChalkIR: graph contains Constant node for value");
        # Store/Load nodes no longer used - we use closure-based context now
    }
}

# Test 8: Parse arithmetic and verify IR
{
    my $code = 'return 3 + 5;';
    my ($result, $graph, $builder) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: arithmetic expression parses');
    ok($graph, 'ChalkIR: graph exists after parsing arithmetic');

    if ($graph) {
        my $nodes = $graph->nodes;
        my $node_count = scalar(keys %$nodes);
        ok($node_count > 0, "ChalkIR: graph has nodes for arithmetic (found $node_count)");

        my $counts = count_node_types($graph, 'Constant', 'Add', 'Return');
        ok($counts->{Constant} >= 2, "ChalkIR: graph contains Constant nodes for operands");
        ok($counts->{Add} > 0, "ChalkIR: graph contains Add node");
    }
}

# Test 9: Parse comparison and verify IR
{
    my $code = 'return 10 > 5;';
    my ($result, $graph, $builder) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: comparison expression parses');
    ok($graph, 'ChalkIR: graph exists after parsing comparison');

    if ($graph) {
        my $nodes = $graph->nodes;
        my $node_count = scalar(keys %$nodes);
        ok($node_count > 0, "ChalkIR: graph has nodes for comparison (found $node_count)");

        my $counts = count_node_types($graph, 'Constant', 'GT', 'Return');
        ok($counts->{Constant} >= 2, "ChalkIR: graph contains Constant nodes for comparison operands");
        ok($counts->{GT} > 0, "ChalkIR: graph contains GT (greater than) node");
    }
}

# Test 10: Parse simple if statement and verify control flow IR
# This is the critical test - it should verify that ChalkIR generates If/Proj/Region nodes
{
    my $code = q{
my $x = 5;
my $result = 0;
if ($x > 0) {
    $result = 10;
}
return $result;
};

    my ($result, $graph, $builder) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: simple if statement parses');
    ok($graph, 'ChalkIR: graph exists after parsing if statement');

    if ($graph) {
        my $nodes = $graph->nodes;
        my $node_count = scalar(keys %$nodes);
        ok($node_count > 0, "ChalkIR: graph has nodes for if statement (found $node_count)");

        # CRITICAL TEST: Check for control flow nodes
        my $counts = count_node_types($graph, 'If', 'Proj', 'Region', 'GT', 'Constant', 'Store');

        # Control flow tests - should now pass after polymorphism fix
        ok($counts->{If} > 0, "ChalkIR: graph contains If node for conditional");
        ok($counts->{Proj} >= 2, "ChalkIR: graph contains Proj nodes for true/false branches");
        ok($counts->{Region} > 0, "ChalkIR: graph contains Region node for merge point");
        ok($counts->{Constant} > 0, "ChalkIR: graph contains Constant nodes");
        ok($counts->{GT} > 0, "ChalkIR: graph contains GT node for condition");
    }
}

# Test 11: Parse if-else statement and verify control flow IR
{
    my $code = q{
my $x = 5;
my $result = 0;
if ($x > 0) {
    $result = 10;
} else {
    $result = 20;
}
return $result;
};

    my ($result, $graph, $builder) = parse_chalk_with_ir($code);

    ok($result, 'ChalkIR: if-else statement parses');
    ok($graph, 'ChalkIR: graph exists after parsing if-else');

    if ($graph) {
        my $nodes = $graph->nodes;
        my $node_count = scalar(keys %$nodes);
        ok($node_count > 0, "ChalkIR: graph has nodes for if-else (found $node_count)");

        my $counts = count_node_types($graph, 'If', 'Proj', 'Region', 'Phi');

        # Control flow tests - should now pass after polymorphism fix
        ok($counts->{If} > 0, "ChalkIR: if-else contains If node");
        ok($counts->{Proj} >= 2, "ChalkIR: if-else contains Proj nodes");
        ok($counts->{Region} > 0, "ChalkIR: if-else contains Region node");
        ok($counts->{Phi} > 0, "ChalkIR: if-else contains Phi node for value merge");
    }
}

# Test 12: Verify parse result has proper structure
{
    my $code = 'return 42;';
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $chalk_grammar);
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => $ir_semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $parse_result = $parser->parse_string($code);
    ok($parse_result, 'ChalkIR: parse returns result');

    if ($parse_result) {
        isa_ok($parse_result, 'Chalk::Semiring::CompositeElement', 'ChalkIR: parse result is CompositeElement');

        ok($parse_result->can('context'), 'ChalkIR: parse result has context method');

        if ($parse_result->can('context')) {
            my $ctx = $parse_result->context;
            ok(defined($ctx), 'ChalkIR: context is defined');

            if ($ctx && $ctx->can('focus')) {
                my $focus = $ctx->focus;
                # Focus tests - should now pass after polymorphism fix
                ok(defined($focus), 'ChalkIR: focus is defined');
                ok($focus && $focus->can('id'), 'ChalkIR: focus has id method') if defined($focus);
            }
        }
    }
}

done_testing();
