#!/usr/bin/env perl
# Test LongestMatch semiring API standardization for EvalContext support
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Scalar::Util qw(refaddr);
use Chalk::Semiring::LongestMatch;
use Chalk::EvalContext;

# Test 1: init_element_from_rule accepts optional $ctx parameter
{
    my $semiring = Chalk::Semiring::LongestMatch->new();

    # Without context - creates element without context (backward compatibility)
    my $elem1 = $semiring->init_element_from_rule(undef, 0, 5, undef);
    ok($elem1, "init_element_from_rule works without context");
    ok(!defined($elem1->context), "Element without context has no context");

    # With context - creates element with context
    my $ctx = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 10,
        end_pos   => 20,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    my $elem2 = $semiring->init_element_from_rule(undef, 10, 20, undef, $ctx);
    ok($elem2, "init_element_from_rule works with context");
    ok(defined($elem2->context), "Element with context has context");
    is($elem2->context->start_pos, 10, "Context has correct start_pos");
    is($elem2->context->end_pos, 20, "Context has correct end_pos");
}

# Test 2: Element class has context field
{
    my $elem = Chalk::Semiring::LongestMatchElement->new(
        valid     => 1,
        start_pos => 5,
        end_pos   => 10,
        context   => undef
    );

    ok($elem, "Can create LongestMatchElement with context parameter");
    ok(!defined($elem->context), "Context can be undef");
}

# Test 3: on_scan creates contexts for scanned terminals when element has context
{
    my $semiring = Chalk::Semiring::LongestMatch->new();

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

    my $elem = Chalk::Semiring::LongestMatchElement->new(
        valid     => 1,
        start_pos => 0,
        end_pos   => 0,
        context   => $ctx
    );

    # Scan a terminal
    my $scanned = $semiring->on_scan(undef, $elem, 5, 'foo', undef);

    ok(defined($scanned->context), "Scanned element has context");
    is($scanned->context->start_pos, 5, "Scanned context has correct start position");
    is($scanned->context->end_pos, 8, "Scanned context has correct end position (5 + length('foo'))");
    is($scanned->context->focus, 'foo', "Scanned context has matched value as focus");
}

# Test 4: Identity elements have context => undef
{
    my $semiring = Chalk::Semiring::LongestMatch->new();

    my $mul_id = $semiring->mul_id;
    my $add_id = $semiring->add_id;

    ok(!defined($mul_id->context), "mul_id has context => undef");
    ok(!defined($add_id->context), "add_id has context => undef");
}

done_testing();
