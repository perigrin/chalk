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
my $bnf_file = 'grammar/perl.bnf';
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

    # Parse a simple expression
    my $result = $parser->parse_string('use 5.42.0; my $x = 42;');
    ok($result, 'ChalkIR semiring can parse simple code');

    # Check that IR was generated
    my $builder = $ir_semiring->builder;
    my $graph = $builder->graph;
    ok($graph, 'IR graph exists after parsing');
    isa_ok($graph, 'Chalk::IR::Graph', 'graph is an IR::Graph');
}

# Test 5: ChalkIR grammar accessor works
{
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    is($ir_semiring->grammar, $grammar, 'ChalkIR returns the same grammar object');
}

done_testing();
