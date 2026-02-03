#!/usr/bin/env perl
# Test Composite semiring API standardization and context propagation
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Scalar::Util qw(refaddr);
use Chalk::Semiring::Composite;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::TypeInference;
use Chalk::Semiring::SemanticValidation;
use Chalk::EvalContext;

# Test 1: Composite accepts and propagates context to all wrapped semirings
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    my $typeinf_sr = Chalk::Semiring::TypeInference->new();

    my $semval_sr = Chalk::Semiring::SemanticValidation->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$precedence_sr, $typeinf_sr, $semval_sr]
    );

    # Create context
    my $ctx = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 10,
        end_pos   => 20,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    # Call init_element_from_rule with context
    my $elem = $composite->init_element_from_rule(undef, 10, 20, undef, $ctx);

    ok($elem, "Composite init_element_from_rule works with context");
    isa_ok($elem, 'Chalk::Semiring::CompositeElement', "Returns CompositeElement");

    # Verify all wrapped elements have contexts
    my @elements = $elem->elements->@*;
    is(scalar(@elements), 3, "CompositeElement has 3 wrapped elements");

    # Check Precedence element (index 0)
    my $prec_elem = $elements[0];
    ok(defined($prec_elem->context), "Precedence element has context");
    is($prec_elem->context->start_pos, 10, "Precedence context has correct start_pos");
    is($prec_elem->context->end_pos, 20, "Precedence context has correct end_pos");

    # Check TypeInference element (index 1)
    my $type_elem = $elements[1];
    ok(defined($type_elem->context), "TypeInference element has context");
    is($type_elem->context->start_pos, 10, "TypeInference context has correct start_pos");
    is($type_elem->context->end_pos, 20, "TypeInference context has correct end_pos");

    # Check SemanticValidation element (index 2)
    my $semval_elem = $elements[2];
    ok(defined($semval_elem->context), "SemanticValidation element has context");
    is($semval_elem->context->start_pos, 10, "SemanticValidation context has correct start_pos");
    is($semval_elem->context->end_pos, 20, "SemanticValidation context has correct end_pos");
}

# Test 2: Composite without context returns cached identity
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    my $typeinf_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$precedence_sr, $typeinf_sr]
    );

    # Without context - wrapped semirings return cached identities
    my $elem1 = $composite->init_element_from_rule(undef, 0, 0, undef);
    my $elem2 = $composite->init_element_from_rule(undef, 0, 0, undef);

    ok($elem1, "Composite works without context");
    ok($elem2, "Composite works without context (second call)");

    # Wrapped elements should be cached identities (same reference)
    my @elems1 = $elem1->elements->@*;
    my @elems2 = $elem2->elements->@*;

    # Precedence should return same cached identity
    is(refaddr($elems1[0]), refaddr($elems2[0]),
       "Precedence returns same cached identity");

    # TypeInference should return same cached identity
    is(refaddr($elems1[1]), refaddr($elems2[1]),
       "TypeInference returns same cached identity");
}

# Test 3: Composite on_scan propagates to all wrapped semirings
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    my $typeinf_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$precedence_sr, $typeinf_sr]
    );

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

    my $elem = $composite->init_element_from_rule(undef, 0, 0, undef, $ctx);

    # Call on_scan
    my $scanned = $composite->on_scan(undef, $elem, 5, 'foo', 'IDENTIFIER');

    ok($scanned, "Composite on_scan works");

    # Check wrapped elements have contexts from on_scan
    my @scanned_elements = $scanned->elements->@*;

    # Precedence element should have context
    ok(defined($scanned_elements[0]->context), "Precedence scanned element has context");
    is($scanned_elements[0]->context->start_pos, 5, "Precedence scanned context at correct position");

    # TypeInference element should have context
    ok(defined($scanned_elements[1]->context), "TypeInference scanned element has context");
    is($scanned_elements[1]->context->start_pos, 5, "TypeInference scanned context at correct position");
}

# Test 4: CompositeElement context delegation
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    my $typeinf_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$precedence_sr, $typeinf_sr]
    );

    my $ctx = Chalk::EvalContext->new(
        focus     => 'test_value',
        children  => [],
        start_pos => 10,
        end_pos   => 20,
        env       => { test => 1 },
        grammar   => undef,
        rule      => undef,
    );

    my $elem = $composite->init_element_from_rule(undef, 10, 20, undef, $ctx);

    # CompositeElement should delegate context() calls
    # Note: Only works if one of the wrapped elements has context method
    # In this case, TypeInference elements have context
    my $delegated_ctx = $elem->context();
    ok(defined($delegated_ctx), "CompositeElement delegates context() call");

    # Should delegate to first element with context method
    if (defined($delegated_ctx)) {
        is($delegated_ctx->start_pos, 10, "Delegated context has correct start_pos");
        is($delegated_ctx->end_pos, 20, "Delegated context has correct end_pos");
    }
}

# Test 5: Identity elements from Composite
{
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    my $typeinf_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$precedence_sr, $typeinf_sr]
    );

    my $mul_id = $composite->mul_id;
    my $add_id = $composite->add_id;

    ok($mul_id, "Composite has mul_id");
    ok($add_id, "Composite has add_id");

    isa_ok($mul_id, 'Chalk::Semiring::CompositeElement', "mul_id is CompositeElement");
    isa_ok($add_id, 'Chalk::Semiring::CompositeElement', "add_id is CompositeElement");

    # Verify wrapped identities
    my @mul_elems = $mul_id->elements->@*;
    my @add_elems = $add_id->elements->@*;

    is(scalar(@mul_elems), 2, "mul_id has 2 wrapped identities");
    is(scalar(@add_elems), 2, "add_id has 2 wrapped identities");

    # Wrapped identities should have defined contexts (shared empty context pattern)
    ok(defined($mul_elems[0]->context), "Wrapped Precedence mul_id has defined context");
    ok(defined($mul_elems[1]->context), "Wrapped TypeInference mul_id has defined context");
    ok(defined($add_elems[0]->context), "Wrapped Precedence add_id has defined context");
    ok(defined($add_elems[1]->context), "Wrapped TypeInference add_id has defined context");
}

done_testing();
