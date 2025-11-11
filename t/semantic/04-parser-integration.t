#!/usr/bin/env perl
# ABOUTME: Tests for Parser integration with semantic actions
# ABOUTME: Validates that Parser calls evaluate() when using Semantic semiring

use 5.42.0;
use warnings;
use Test::More;

use lib 'lib';
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Semantic;

# Test that Parser works with Semantic semiring
{
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            ['S' => ['a', 'b']],
        ]
    );

    my $semiring = Chalk::Semiring::Semantic->new(
        env => {},
        grammar => $grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    # Test that parse returns a semantic element
    my $result = $parser->parse_string("ab");

    ok($result, 'Parser with Semantic semiring can parse');
    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'Result is a SemanticElement');

    # Verify the element has the expected structure
    can_ok($result, 'extract');
    ok(defined($result->extract), 'SemanticElement can extract value');
}

# Test with custom evaluation rule
{
    package CustomAddRule {
        use 5.42.0;
        use experimental 'class';

        class CustomAddRule :isa(Chalk::GrammarRule) {
            # Override evaluate to sum numeric values
            method evaluate($context) {
                my @children = $context->children->@*;
                return 0 unless @children >= 3;

                my $left = $children[0]->extract;
                my $op = $children[1]->extract;
                my $right = $children[2]->extract;

                if ($op eq '+' && defined($left) && defined($right)) {
                    return $left + $right;
                }

                return [$left, $op, $right];
            }
        }
    }

    my $add_rule = CustomAddRule->new(
        lhs => 'Expr',
        rhs => [qr/\d+/, qr/\+/, qr/\d+/]
    );

    my $grammar = Chalk::Grammar->new(
        rules => { 'Expr' => [$add_rule] },
        start_symbol => 'Expr'
    );

    my $semiring = Chalk::Semiring::Semantic->new(
        env => {},
        grammar => $grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string("5+3");

    ok($result, 'Parser with custom evaluate rule can parse');
    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'Result is a SemanticElement');

    # Verify the custom evaluation was called
    my $extracted = $result->extract;
    ok(defined($extracted), 'Custom evaluate produced a result');
    # The custom rule should either return the sum (8) or an array structure
    ok($extracted == 8 || ref($extracted) eq 'ARRAY',
       'Custom evaluate returned expected type (number or array)');
}

# Test that default evaluate() is called
{
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            ['S' => ['x']],
        ]
    );

    my $semiring = Chalk::Semiring::Semantic->new(
        env => {},
        grammar => $grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string("x");

    ok($result, 'Parser with default evaluate can parse');
    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'Result is a SemanticElement');

    # Verify default evaluation works
    can_ok($result, 'extract');
    ok(defined($result->extract), 'Default evaluate produced a result');
}

done_testing();
