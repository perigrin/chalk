#!/usr/bin/env perl
# Test SemanticValidation semiring API standardization for EvalContext support
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Scalar::Util qw(refaddr);
use Chalk::Semiring::SemanticValidation;
use Chalk::EvalContext;

# Test 1: init_element_from_rule accepts optional $ctx parameter
{
    my $semiring = Chalk::Semiring::SemanticValidation->new();

    # Without context - should return cached identity
    my $elem1 = $semiring->init_element_from_rule(undef, 0, 0, undef);
    ok($elem1, "init_element_from_rule works without context");
    ok(!defined($elem1->context), "Element without context has no context");

    # With same rule, should return same cached identity (reference equality)
    my $elem2 = $semiring->init_element_from_rule(undef, 0, 0, undef);
    is(refaddr($elem1), refaddr($elem2), "Same cached identity returned when no context");
}

# Test 2: init_element_from_rule creates new element with context when provided
{
    my $semiring = Chalk::Semiring::SemanticValidation->new();

    my $ctx = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 10,
        end_pos   => 20,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    my $elem = $semiring->init_element_from_rule(undef, 10, 20, undef, $ctx);
    ok($elem, "init_element_from_rule works with context");
    ok(defined($elem->context), "Element has context");
    is($elem->context->start_pos, 10, "Context has correct start_pos");
    is($elem->context->end_pos, 20, "Context has correct end_pos");
}

# Test 3: init_element_from_rule creates NEW elements when context provided
{
    my $semiring = Chalk::Semiring::SemanticValidation->new();

    my $ctx1 = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 10,
        end_pos   => 20,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    my $ctx2 = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 30,
        end_pos   => 40,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    my $elem1 = $semiring->init_element_from_rule(undef, 10, 20, undef, $ctx1);
    my $elem2 = $semiring->init_element_from_rule(undef, 30, 40, undef, $ctx2);

    ok(refaddr($elem1) != refaddr($elem2), "Different contexts create different elements");
    is($elem1->context->start_pos, 10, "First element has correct position");
    is($elem2->context->start_pos, 30, "Second element has correct position");
}

# Test 4: on_scan creates contexts for scanned terminals when element has context
{
    my $semiring = Chalk::Semiring::SemanticValidation->new();

    # Create element with context
    my $ctx = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 0,
        end_pos   => 0,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    my $elem = Chalk::Semiring::SemanticValidationElement->new(
        valid => 1,
        forest => undef,
        rules => undef,
        errors => [],
        start_pos => 0,
        end_pos => 0,
        context => $ctx
    );

    # Scan a terminal
    my $scanned = $semiring->on_scan(undef, $elem, 5, 'foo', undef);

    ok(defined($scanned->context), "Scanned element has context");
    is($scanned->context->start_pos, 5, "Scanned context has correct start position");
    is($scanned->context->end_pos, 8, "Scanned context has correct end position (5 + length('foo'))");
    is($scanned->context->focus, 'foo', "Scanned context has matched value as focus");
}

# Test 5: Identity elements have context => undef
{
    my $semiring = Chalk::Semiring::SemanticValidation->new();

    my $mul_id = $semiring->mul_id;
    my $add_id = $semiring->add_id;

    ok(!defined($mul_id->context), "mul_id has context => undef");
    ok(!defined($add_id->context), "add_id has context => undef");
}

done_testing();
