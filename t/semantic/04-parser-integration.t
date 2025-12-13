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

# Define a test rule class with pass-through behavior for testing
package TestPassThroughRule {
    use 5.42.0;
    use experimental 'class';

    class TestPassThroughRule :isa(Chalk::GrammarRule) {
        method evaluate($context) {
            # Return array of child values for testing
            return [ map { $_->extract } $context->children->@* ];
        }
    }
}

# Test that Parser works with Semantic semiring using custom rule
{
    my $rule = TestPassThroughRule->new(
        lhs => 'S',
        rhs => ['a', 'b']
    );

    my $grammar = Chalk::Grammar->new(
        rules => { 'S' => [$rule] },
        start_symbol => 'S'
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
    my $extracted = $result->extract;
    ok(defined($extracted), 'SemanticElement can extract value');
}

# Test with custom evaluation rule (concatenation instead of arithmetic)
{
    package CustomConcatRule {
        use 5.42.0;
        use experimental 'class';

        class CustomConcatRule :isa(Chalk::GrammarRule) {
            # Override evaluate to concatenate child values
            method evaluate($context) {
                my @children = $context->children->@*;
                my @values = map { $_->extract // '' } @children;
                return join('', @values);
            }
        }
    }

    my $concat_rule = CustomConcatRule->new(
        lhs => 'S',
        rhs => ['x', 'y', 'z']
    );

    my $grammar = Chalk::Grammar->new(
        rules => { 'S' => [$concat_rule] },
        start_symbol => 'S'
    );

    my $semiring = Chalk::Semiring::Semantic->new(
        env => {},
        grammar => $grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string("xyz");

    ok($result, 'Parser with custom evaluate rule can parse');
    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'Result is a SemanticElement');

    # Verify the custom evaluation was called
    my $extracted = $result->extract;
    ok(defined($extracted), 'Custom evaluate produced a result');
    is($extracted, 'xyz', 'Custom evaluate concatenated child values');
}

# Test that rules without explicit evaluate return undef focus
# (evaluation only happens when complete() is called with lazy semantic evaluation)
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

    ok($result, 'Parser can parse with rules using base GrammarRule');
    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'Result is a SemanticElement');

    # For rules without explicit evaluate, the focus remains undef
    # (semantic evaluation is lazy - only triggered when needed)
    my $extracted = $result->extract;
    ok(!defined($extracted), 'Extract returns undef for unevaluated rules');
}

done_testing();
