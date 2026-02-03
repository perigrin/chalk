#!/usr/bin/env perl
# Test AST semiring API standardization for EvalContext support
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Scalar::Util qw(refaddr);
use Chalk::Semiring::AST;
use Chalk::EvalContext;

# Test 1: init_element_from_rule accepts optional $ctx parameter
{
    my $semiring = Chalk::Semiring::AST->new();

    # Without context - creates element without context (backward compatibility)
    my $mock_rule = MockRule->new(lhs => 'TestRule');
    my $elem1 = $semiring->init_element_from_rule($mock_rule, 0, 5, undef);
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

    my $elem2 = $semiring->init_element_from_rule($mock_rule, 10, 20, undef, $ctx);
    ok($elem2, "init_element_from_rule works with context");
    ok(defined($elem2->context), "Element with context has context");
    is($elem2->context->start_pos, 10, "Context has correct start_pos");
    is($elem2->context->end_pos, 20, "Context has correct end_pos");
}

# Test 2: Element class has context field
{
    my $elem = Chalk::Semiring::ASTElement->new(
        rule_name => 'TestRule',
        children  => [],
        start_pos => 5,
        end_pos   => 10,
        context   => undef
    );

    ok($elem, "Can create ASTElement with context parameter");
    ok(!defined($elem->context), "Context can be undef");
}

# Test 3: on_scan creates contexts for scanned terminals when element has context
{
    my $semiring = Chalk::Semiring::AST->new();

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

    my $elem = Chalk::Semiring::ASTElement->new(
        rule_name => 'TestRule',
        children  => [],
        start_pos => 0,
        end_pos   => 0,
        context   => $ctx
    );

    # Scan a terminal - in AST, this multiplies terminal into parent
    my $scanned = $semiring->on_scan(undef, $elem, 5, 'foo', undef);

    # AST multiply preserves parent context, scanned element should have parent's context
    ok(defined($scanned->context), "Scanned element has context");
    is($scanned->context->start_pos, 0, "Scanned context has parent's start position");
    is($scanned->context->end_pos, 0, "Scanned context has parent's end position");
    ok(!defined($scanned->context->focus), "Scanned context has parent's focus (undef)");

    # But the child (terminal) should have its own context
    is(scalar(@{$scanned->children}), 1, "Scanned element has one child (the terminal)");
    my $terminal = $scanned->children->[0];
    ok(defined($terminal->context), "Terminal child has context");
    is($terminal->context->focus, 'foo', "Terminal context has matched value as focus");
    is($terminal->context->start_pos, 5, "Terminal context has correct start position");
    is($terminal->context->end_pos, 8, "Terminal context has correct end position (5 + length('foo'))");
}

# Test 4: Identity elements share empty context singleton
{
    my $semiring = Chalk::Semiring::AST->new();

    my $mul_id = $semiring->mul_id;
    my $add_id = $semiring->add_id;

    ok(defined($mul_id->context), "mul_id has defined context");
    ok(defined($add_id->context), "add_id has defined context");

    # Both identity elements should share the same empty context singleton
    is(refaddr($mul_id->context), refaddr($add_id->context),
       "mul_id and add_id share the same empty context singleton");
    is(refaddr($mul_id->context), refaddr($semiring->empty_context),
       "mul_id context is the shared empty_context singleton");
}

# Mock rule class for testing
class MockRule {
    field $lhs :param :reader;
}

done_testing();
