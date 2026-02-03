#!/usr/bin/env perl
# Test Boolean semiring API standardization for EvalContext support
use 5.42.0;
use experimental qw(class builtin);
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More;
use Chalk::Semiring::Boolean;
use Chalk::EvalContext;
use Chalk::Grammar;

# Test 1: init_element_from_rule accepts optional $ctx parameter
{
    my $semiring = Chalk::Semiring::Boolean->new();

    # Without context - should return cached identity with empty context
    my $elem1 = $semiring->init_element_from_rule(undef, 0, 0, undef);
    ok($elem1, "init_element_from_rule works without context");
    is($elem1->value, 1, "Element without context has value 1 (true)");
    ok(defined($elem1->context), "Element has defined empty context");
    is(scalar(@{$elem1->context->children}), 0, "Element context is empty");

    # With same rule, should return same cached identity (reference equality)
    my $elem2 = $semiring->init_element_from_rule(undef, 0, 0, undef);
    ok($elem1 == $elem2, "Same cached identity returned when no context");
}

# Test 2: init_element_from_rule creates new element with context when provided
{
    my $semiring = Chalk::Semiring::Boolean->new();

    # Create a minimal context (grammar can be undef for this test)
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
    is($elem->value, 1, "Element with context has value 1 (true)");
    ok(defined($elem->context), "Element has context");
    is($elem->context->start_pos, 10, "Context has correct start_pos");
    is($elem->context->end_pos, 20, "Context has correct end_pos");
}

# Test 3: init_element_from_rule creates NEW elements when context provided
{
    my $semiring = Chalk::Semiring::Boolean->new();

    # Don't need full Grammar object - just use undef
    my $grammar = undef;

    my $ctx1 = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 10,
        end_pos   => 20,
        env       => {},
        grammar   => $grammar,
        rule      => undef,
    );

    my $ctx2 = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 30,
        end_pos   => 40,
        env       => {},
        grammar   => $grammar,
        rule      => undef,
    );

    my $elem1 = $semiring->init_element_from_rule(undef, 10, 20, undef, $ctx1);
    my $elem2 = $semiring->init_element_from_rule(undef, 30, 40, undef, $ctx2);

    # Use refaddr for reference comparison
    use Scalar::Util qw(refaddr);
    ok(refaddr($elem1) != refaddr($elem2), "Different contexts create different elements");
    is($elem1->context->start_pos, 10, "First element has correct position");
    is($elem2->context->start_pos, 30, "Second element has correct position");
}

# Test 4: on_scan creates contexts for scanned terminals when element has context
{
    my $semiring = Chalk::Semiring::Boolean->new();

    # Don't need full Grammar object - just use undef
    my $grammar = undef;

    # Create element with context
    my $ctx = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 0,
        end_pos   => 0,
        env       => {},
        grammar   => $grammar,
        rule      => undef,
    );

    my $elem = Chalk::Semiring::BooleanElement->new(
        value => 1,
        context => $ctx
    );

    # Scan a non-keyword identifier
    my $scanned = $semiring->on_scan(undef, $elem, 5, 'foo', 'IDENTIFIER');

    ok(defined($scanned->context), "Scanned element has context");
    is($scanned->context->start_pos, 5, "Scanned context has correct start position");
    is($scanned->context->end_pos, 8, "Scanned context has correct end position (5 + length('foo'))");
    is($scanned->context->focus, 'foo', "Scanned context has matched value as focus");
}

# Test 5: on_scan without context returns element unchanged
{
    my $semiring = Chalk::Semiring::Boolean->new();

    # Create element without context
    my $elem = Chalk::Semiring::BooleanElement->new(value => 1);

    # Scan should return element unchanged
    my $scanned = $semiring->on_scan(undef, $elem, 5, 'foo', 'IDENTIFIER');

    ok(!defined($scanned->context), "Scanned element without context still has no context");
    is($scanned->value, 1, "Element value unchanged");

    # Should return same element reference
    use Scalar::Util qw(refaddr);
    is(refaddr($scanned), refaddr($elem), "Returns same element reference when no context");
}

# Test 6: Identity elements have defined empty context singleton
{
    my $semiring = Chalk::Semiring::Boolean->new();

    my $mul_id = $semiring->mul_id;
    my $add_id = $semiring->add_id;

    ok(defined($mul_id->context), "mul_id has defined context");
    ok(defined($add_id->context), "add_id has defined context");

    # Verify contexts are empty
    is(scalar(@{$mul_id->context->children}), 0, "mul_id context has no children");
    is(scalar(@{$add_id->context->children}), 0, "add_id context has no children");
    ok(!defined($mul_id->context->focus), "mul_id context has no focus");
    ok(!defined($add_id->context->focus), "add_id context has no focus");

    # Verify they share the same context singleton
    use Scalar::Util qw(refaddr);
    is(refaddr($mul_id->context), refaddr($add_id->context), "mul_id and add_id share same empty context singleton");
}

# Test 7: Keyword rejection still works with context
{
    my $semiring = Chalk::Semiring::Boolean->new();

    my $ctx = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 0,
        end_pos   => 0,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    my $elem = Chalk::Semiring::BooleanElement->new(
        value => 1,
        context => $ctx
    );

    # Try to scan a keyword as an identifier - should be rejected
    my $rejected = $semiring->on_scan(undef, $elem, 0, 'class', 'IDENTIFIER');

    # Should return add_id (false)
    is($rejected->value, 0, "Keyword rejected returns value 0 (false)");
}

done_testing();
