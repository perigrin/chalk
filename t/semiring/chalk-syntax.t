#!/usr/bin/env perl
# ABOUTME: Test ChalkSyntax semiring for syntax and precedence validation
# ABOUTME: Verifies SPPF+Precedence composition without IR generation
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use experimental qw(defer);
defer { done_testing() }

use Chalk::Base;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Grammar;
use Chalk::Parser;

subtest 'ChalkSyntax semiring creation' => sub {
    # Load grammar
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);

    ok $semiring, 'ChalkSyntax semiring created';
    ok $semiring->composite, 'Has composite semiring';
    ok $semiring->grammar, 'Has grammar reference';

    # Check that composite has both SPPF and Precedence semirings
    my $semirings = $semiring->composite->semirings;
    is scalar(@$semirings), 2, 'Composite has two semirings';

    isa_ok $semirings->[0], ['Chalk::Semiring::SPPF'], 'First semiring is SPPF';
    isa_ok $semirings->[1], ['Chalk::Semiring::Precedence'], 'Second semiring is Precedence';
};

subtest 'ChalkSyntax identity elements' => sub {
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);

    ok $semiring->mul_id, 'Has multiplicative identity';
    ok $semiring->add_id, 'Has additive identity';

    isa_ok $semiring->mul_id, ['Chalk::Semiring::CompositeElement'], 'mul_id is CompositeElement';
    isa_ok $semiring->add_id, ['Chalk::Semiring::CompositeElement'], 'add_id is CompositeElement';
};

subtest 'ChalkSyntax accepts valid Chalk syntax' => sub {
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Test valid syntax
    my @valid_tests = (
        'my $x = 42;',
        'my $result = 3 + 5 * 2;',
        'if ($x > 10) { say "big"; }',
        'my $sum = 1 + 2 + 3;',
    );

    for my $input (@valid_tests) {
        my $result = $parser->parse_string($input);
        ok $result, "ChalkSyntax accepts valid syntax: $input";
    }
};

subtest 'ChalkSyntax validates precedence' => sub {
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Test that operator precedence is validated
    # These should all parse successfully because ChalkSyntax validates precedence
    # Note: Only testing operators supported by the Chalk grammar
    my @precedence_tests = (
        '3 + 5 * 2;',      # Multiplication before addition
        '1 + 2 + 3;',      # Left-associative addition
        '10 / 2 - 1;',     # Division before subtraction
        '$x && $y || $z;', # Logical operators
    );

    for my $input (@precedence_tests) {
        my $result = $parser->parse_string($input);
        ok $result, "ChalkSyntax validates precedence for: $input";
    }
};

subtest 'ChalkSyntax delegates to composite' => sub {
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);

    # Check that semiring methods delegate properly
    ok $semiring->can('multiply'), 'Has multiply method';
    ok $semiring->can('plus'), 'Has plus method';
    ok $semiring->can('init_element_from_rule'), 'Has init_element_from_rule method';
    ok $semiring->can('on_complete'), 'Has on_complete method';
    ok $semiring->can('on_scan'), 'Has on_scan method';
};

subtest 'ChalkSyntax without Semantic semiring' => sub {
    # Verify that ChalkSyntax does NOT include Semantic semiring
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);

    my $semirings = $semiring->composite->semirings;
    is scalar(@$semirings), 2, 'ChalkSyntax has exactly 2 semirings (not 3)';

    # Check that neither semiring is Semantic
    for my $sr (@$semirings) {
        my $class = ref($sr);
        isnt $class, 'Chalk::Semiring::Semantic', "ChalkSyntax does not include Semantic ($class)";
    }
};

subtest 'ChalkSyntax syntax check mode usage' => sub {
    # Verify that ChalkSyntax works for syntax-only checking (like perl -c)
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parse a simple program
    my $result = $parser->parse_string('my $x = 1 + 2;');
    ok $result, 'ChalkSyntax successfully validates syntax';

    # Verify result is a CompositeElement with SPPF + Precedence
    isa_ok $result, ['Chalk::Semiring::CompositeElement'], 'Result is CompositeElement';

    # Get the elements
    my $elements = $result->elements;
    is scalar(@$elements), 2, 'Result has 2 elements (SPPF + Precedence)';

    isa_ok $elements->[0], ['Chalk::Semiring::SPPFElement'], 'First element is SPPFElement';
    isa_ok $elements->[1], ['Chalk::Semiring::PrecedenceElement'], 'Second element is PrecedenceElement';

    # Check that precedence is valid
    ok $elements->[1]->valid, 'Precedence validation succeeded';
};
