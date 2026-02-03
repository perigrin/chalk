#!/usr/bin/env perl
# Test Semantic semiring API standardization for EvalContext support
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Scalar::Util qw(refaddr);
use Chalk::Semiring::Semantic;
use Chalk::EvalContext;
use Chalk::Grammar;

# Note: Semantic semiring already had partial context support
# This test verifies the standardized API (5th parameter $ctx)

# Test 1: init_element_from_rule accepts optional $ctx parameter (5th param)
{
    # Create minimal mock grammar object
    my $grammar = bless({ _start_symbol => 'Test' }, 'MockGrammar');
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

    # Without context - creates context internally (existing behavior)
    my $elem1 = $semiring->init_element_from_rule(undef, 0, 0, undef);
    ok($elem1, "init_element_from_rule works without context");
    ok(defined($elem1->context), "Element always has context (created internally)");

    # With explicit context - uses provided context
    my $ctx = Chalk::EvalContext->new(
        focus     => 'test_focus',
        children  => [],
        start_pos => 10,
        end_pos   => 20,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    my $elem2 = $semiring->init_element_from_rule(undef, 10, 20, undef, $ctx);
    ok($elem2, "init_element_from_rule works with explicit context");
    ok(defined($elem2->context), "Element has context");
    is($elem2->context->focus, 'test_focus', "Uses provided context (not internally created)");
    is($elem2->context->start_pos, 10, "Context has correct start_pos");
    is($elem2->context->end_pos, 20, "Context has correct end_pos");
}

# Test 2: Different contexts create different elements
{
    # Create minimal mock grammar object
    my $grammar = bless({ _start_symbol => 'Test' }, 'MockGrammar');
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

    my $ctx1 = Chalk::EvalContext->new(
        focus     => 'focus1',
        children  => [],
        start_pos => 10,
        end_pos   => 20,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    my $ctx2 = Chalk::EvalContext->new(
        focus     => 'focus2',
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
    is($elem1->context->focus, 'focus1', "First element has correct focus");
    is($elem2->context->focus, 'focus2', "Second element has correct focus");
}

# Test 3: on_scan already creates contexts (existing behavior)
{
    # Create minimal mock grammar object
    my $grammar = bless({ _start_symbol => 'Test' }, 'MockGrammar');
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

    # Create element with context (Semantic always has context)
    my $elem = $semiring->init_element_from_rule(undef, 0, 0, undef);

    # Mock item for on_scan
    my $mock_item = bless { rule => sub { undef } }, 'MockItem';

    # Scan a terminal - on_scan multiplies the terminal into the element
    my $scanned = $semiring->on_scan($mock_item, $elem, 5, 'foo', undef);

    ok(defined($scanned->context), "Scanned element has context");
    # Semantic's on_scan multiplies the scanned terminal, combining contexts
    # The result spans from original start to new end
    is($scanned->context->start_pos, 0, "Scanned context starts from original position");
    is($scanned->context->end_pos, 8, "Scanned context ends at terminal end (5 + length('foo'))");
    # Context has one child (the scanned terminal)
    is(scalar(@{$scanned->context->children}), 1, "Context has one child (scanned terminal)");
    is($scanned->context->children->[0]->focus, 'foo', "Child context has matched value");
}

# Test 4: Identity elements have contexts (Semantic always has contexts)
{
    # Create minimal mock grammar object
    my $grammar = bless({ _start_symbol => 'Test' }, 'MockGrammar');
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

    my $mul_id = $semiring->mul_id;
    my $add_id = $semiring->add_id;

    # Semantic identity elements DO have contexts (unlike other semirings)
    # This is existing behavior - they always have contexts
    ok(defined($mul_id->context), "mul_id has context (Semantic always has contexts)");
    ok(defined($add_id->context), "add_id has context (Semantic always has contexts)");

    # NEW: Verify identity elements share empty_context singleton
    is(refaddr($mul_id->context), refaddr($add_id->context),
       "Identity elements share empty_context singleton");
}

done_testing();

# Mock packages for test
package MockGrammar {
    # Minimal mock - Semantic only needs grammar to exist
}

package MockItem {
    sub rule { undef }
}
