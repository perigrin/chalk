#!/usr/bin/env perl
# ABOUTME: Tests for Chalk::Semiring::Semantic and SemanticElement
# ABOUTME: Validates semantic evaluation during parsing with contexts

use 5.42.0;
use warnings;
use Test::More;
use Scalar::Util qw(refaddr);

use lib 'lib';
use Chalk::Semiring::Semantic;
use Chalk::EvalContext;
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;

# Test basic element construction
{
    my $ctx = Chalk::EvalContext->new(
        focus => "test_value",
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $elem = Chalk::Semiring::SemanticElement->new(
        value => "foo",
        context => $ctx
    );

    isa_ok($elem, 'Chalk::Semiring::SemanticElement', 'constructor creates SemanticElement');
    is($elem->value, "foo", 'value accessor works');
    isa_ok($elem->context, 'Chalk::EvalContext', 'context accessor works');
}

# Test semiring construction
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

    isa_ok($semiring, 'Chalk::Semiring::Semantic', 'constructor creates Semantic semiring');
    isa_ok($semiring->mul_id, 'Chalk::Semiring::SemanticElement', 'mul_id is a SemanticElement');
    isa_ok($semiring->add_id, 'Chalk::Semiring::SemanticElement', 'add_id is a SemanticElement');
}

# Test init_element_from_rule
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

    my $rule = $grammar->rules->{'S'}->[0];
    my $elem = $semiring->init_element_from_rule($rule, 0, 5);

    isa_ok($elem, 'Chalk::Semiring::SemanticElement', 'init_element_from_rule returns SemanticElement');
    isa_ok($elem->context, 'Chalk::EvalContext', 'element has context');
    is($elem->context->start_pos, 0, 'context has correct start_pos');
    is($elem->context->end_pos, 5, 'context has correct end_pos');
    ok(refaddr($elem->context->rule) == refaddr($rule), 'context has correct rule reference');
}

# Test add operation (choice - prefer first alternative)
{
    my $ctx1 = Chalk::EvalContext->new(
        focus => "value1",
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $ctx2 = Chalk::EvalContext->new(
        focus => "value2",
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $elem1 = Chalk::Semiring::SemanticElement->new(
        value => "first",
        context => $ctx1
    );

    my $elem2 = Chalk::Semiring::SemanticElement->new(
        value => "second",
        context => $ctx2
    );

    my $result = $elem1->add($elem2);

    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'add returns SemanticElement');
    is($result->value, "first", 'add prefers first alternative');
}

# Test multiply operation (sequence)
{
    my $ctx1 = Chalk::EvalContext->new(
        focus => "left",
        children => [],
        start_pos => 0,
        end_pos => 3,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $ctx2 = Chalk::EvalContext->new(
        focus => "right",
        children => [],
        start_pos => 3,
        end_pos => 8,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $elem1 = Chalk::Semiring::SemanticElement->new(
        value => "a",
        context => $ctx1
    );

    my $elem2 = Chalk::Semiring::SemanticElement->new(
        value => "b",
        context => $ctx2
    );

    my $result = $elem1->multiply($elem2);

    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'multiply returns SemanticElement');
    isa_ok($result->context, 'Chalk::EvalContext', 'multiply combines contexts');

    # The multiply operation appends other's context to self's children
    # Since elem1 has 0 children, result should have 1 child (ctx2)
    is(scalar(@{$result->context->children}), 1, 'combined context has other context as child');
}

# Test identity elements
{
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            ['S' => ['a']],
        ]
    );

    my $semiring = Chalk::Semiring::Semantic->new(
        env => {},
        grammar => $grammar
    );

    my $mul_id = $semiring->mul_id;
    my $add_id = $semiring->add_id;

    # mul_id should be identity for multiplication
    my $ctx = Chalk::EvalContext->new(
        focus => "test",
        children => [],
        start_pos => 0,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $elem = Chalk::Semiring::SemanticElement->new(
        value => "test",
        context => $ctx
    );

    # elem * mul_id should behave properly
    my $result = $elem->multiply($mul_id);
    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'multiply with mul_id works');

    # elem + add_id should behave properly
    $result = $elem->add($add_id);
    isa_ok($result, 'Chalk::Semiring::SemanticElement', 'add with add_id works');
}

# Test with environment
{
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            ['S' => ['a']],
        ]
    );

    my %env = (foo => 'bar', baz => 42);

    my $semiring = Chalk::Semiring::Semantic->new(
        env => \%env,
        grammar => $grammar
    );

    my $rule = $grammar->rules->{'S'}->[0];
    my $elem = $semiring->init_element_from_rule($rule, 0, 5);

    is($elem->context->env, \%env, 'context has access to environment');
}

done_testing();
