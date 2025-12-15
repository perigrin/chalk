#!/usr/bin/env perl
# ABOUTME: Tests for GrammarRule evaluate() method for semantic actions
# ABOUTME: Validates that rules require explicit evaluate() implementation

use 5.42.0;
use warnings;
use Test::More;

use lib 'lib';
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::EvalContext;

# Define a test rule class with default pass-through behavior
package TestPassThroughRule {
    use 5.42.0;
    use experimental 'class';

    class TestPassThroughRule :isa(Chalk::GrammarRule) {
        # Default pass-through: return array of child values
        method evaluate($context) {
            return [ map { $_->extract } $context->children->@* ];
        }
    }
}

# Test that GrammarRule has evaluate method
{
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            ['S' => ['a', 'b']],
        ]
    );

    my $rule = $grammar->rules->{'S'}->[0];
    ok($rule->can('evaluate'), 'GrammarRule has evaluate method');
}

# Test that base GrammarRule dies without explicit evaluate
{
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            ['S' => []],  # Empty production
        ]
    );

    my $rule = $grammar->rules->{'S'}->[0];

    my $ctx = Chalk::EvalContext->new(
        focus => undef,
        children => [],
        start_pos => 0,
        end_pos => 0,
        env => {},
        grammar => $grammar,
        rule => $rule
    );

    eval { $rule->evaluate($ctx) };
    like($@, qr/has no evaluate\(\) method/, 'base GrammarRule dies with helpful message');
}

# Test pass-through evaluate implementation with no children
{
    my $rule = TestPassThroughRule->new(
        lhs => 'S',
        rhs => []
    );

    my $ctx = Chalk::EvalContext->new(
        focus => undef,
        children => [],
        start_pos => 0,
        end_pos => 0,
        env => {},
        grammar => undef,
        rule => $rule
    );

    my $result = $rule->evaluate($ctx);

    is_deeply($result, [], 'evaluate returns empty array for no children');
}

# Test pass-through evaluate implementation with children
{
    my $rule = TestPassThroughRule->new(
        lhs => 'S',
        rhs => ['a', 'b', 'c']
    );

    # Create child contexts with values
    my $child1 = Chalk::EvalContext->new(
        focus => "first",
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $child2 = Chalk::EvalContext->new(
        focus => "second",
        children => [],
        start_pos => 5,
        end_pos => 11,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $child3 = Chalk::EvalContext->new(
        focus => "third",
        children => [],
        start_pos => 11,
        end_pos => 16,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $ctx = Chalk::EvalContext->new(
        focus => undef,
        children => [$child1, $child2, $child3],
        start_pos => 0,
        end_pos => 16,
        env => {},
        grammar => undef,
        rule => $rule
    );

    my $result = $rule->evaluate($ctx);

    is_deeply($result, ["first", "second", "third"],
              'evaluate returns array of child values');
}

# Test evaluate can access rule information
{
    my $rule = TestPassThroughRule->new(
        lhs => 'Expression',
        rhs => ['Number', '+', 'Number']
    );

    my $child1 = Chalk::EvalContext->new(
        focus => 5,
        children => [],
        start_pos => 0,
        end_pos => 1,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $child2 = Chalk::EvalContext->new(
        focus => "+",
        children => [],
        start_pos => 1,
        end_pos => 2,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $child3 = Chalk::EvalContext->new(
        focus => 3,
        children => [],
        start_pos => 2,
        end_pos => 3,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $ctx = Chalk::EvalContext->new(
        focus => undef,
        children => [$child1, $child2, $child3],
        start_pos => 0,
        end_pos => 3,
        env => {},
        grammar => undef,
        rule => $rule
    );

    my $result = $rule->evaluate($ctx);

    is_deeply($result, [5, "+", 3], 'evaluate extracts all child values');
}

# Test that evaluate can be subclassed
{
    package TestRule {
        use 5.42.0;
        use experimental 'class';

        class TestRule :isa(Chalk::GrammarRule) {
            # Override evaluate to sum numeric children
            method evaluate($context) {
                my $sum = 0;
                for my $child ($context->children->@*) {
                    my $val = $child->extract;
                    $sum += $val if defined($val) && $val =~ /^\d+$/;
                }
                return $sum;
            }
        }
    }

    my $rule = TestRule->new(
        lhs => 'Sum',
        rhs => ['a', 'b', 'c']
    );

    my $child1 = Chalk::EvalContext->new(
        focus => 10,
        children => [],
        start_pos => 0,
        end_pos => 2,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $child2 = Chalk::EvalContext->new(
        focus => 20,
        children => [],
        start_pos => 2,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $child3 = Chalk::EvalContext->new(
        focus => 30,
        children => [],
        start_pos => 4,
        end_pos => 6,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $ctx = Chalk::EvalContext->new(
        focus => undef,
        children => [$child1, $child2, $child3],
        start_pos => 0,
        end_pos => 6,
        env => {},
        grammar => undef,
        rule => $rule
    );

    my $result = $rule->evaluate($ctx);

    is($result, 60, 'subclassed evaluate can override default behavior');
}

done_testing();
