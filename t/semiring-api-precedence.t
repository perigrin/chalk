#!/usr/bin/env perl
# Test Precedence semiring API standardization for EvalContext support
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Chalk::Semiring::Precedence;
use Chalk::EvalContext;
use Chalk::Grammar;

# Test 1: init_element_from_rule accepts optional $ctx parameter
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
        { assoc => 'left', ops => ['*', '/'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Without context - should return cached identity with shared empty context
    my $elem1 = $semiring->init_element_from_rule(undef, 0, 0, undef);
    ok($elem1, "init_element_from_rule works without context");
    is($elem1->valid, 1, "Element without context is valid");
    ok(defined($elem1->context), "Element has shared empty context");
    is(scalar(@{$elem1->context->children}), 0, "Empty context has no children");

    # With same rule, should return same cached identity (reference equality)
    my $elem2 = $semiring->init_element_from_rule(undef, 0, 0, undef);
    ok($elem1 == $elem2, "Same cached identity returned when no context");
}

# Test 2: init_element_from_rule creates new element with context when provided
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

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
    is($elem->valid, 1, "Element with context is valid");
    ok(defined($elem->context), "Element has context");
    is($elem->context->start_pos, 10, "Context has correct start_pos");
    is($elem->context->end_pos, 20, "Context has correct end_pos");
}

# Test 3: init_element_from_rule creates NEW elements when context provided
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

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
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

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

    my $elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator_index => $semiring->lookup_operator('+') ? {} : {},
        context => $ctx
    );

    # Scan a non-operator terminal
    my $scanned = $semiring->on_scan(undef, $elem, 5, 'foo', 'IDENTIFIER');

    ok(defined($scanned->context), "Scanned element has context");
    is($scanned->context->start_pos, 5, "Scanned context has correct start position");
    is($scanned->context->end_pos, 8, "Scanned context has correct end position (5 + length('foo'))");
    is($scanned->context->focus, 'foo', "Scanned context has matched value as focus");
}

# Test 5: Identity elements have shared empty context
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    my $mul_id = $semiring->mul_id;
    my $add_id = $semiring->add_id;

    ok(defined($mul_id->context), "mul_id has defined context");
    ok(defined($add_id->context), "add_id has defined context");
    is(scalar(@{$mul_id->context->children}), 0, "mul_id context has empty children");
    is(scalar(@{$add_id->context->children}), 0, "add_id context has empty children");

    # Verify they share the same context instance
    use Scalar::Util qw(refaddr);
    is(refaddr($mul_id->context), refaddr($add_id->context), "Identity elements share same context instance");
}

done_testing();
