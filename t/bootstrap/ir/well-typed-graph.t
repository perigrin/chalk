# ABOUTME: Tests for the well-typed-graph invariant checker (Phase 3a H2).
# ABOUTME: Verifies that malformed graphs (unbridged repr mismatch) fail loudly.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph::TypedInvariant;

# H2-1: A well-formed graph with matching representations passes.
# Add(Int, Int) -> Int: all operands match Add's required Int representation.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs = $f->make('Constant', value => '1', const_type => 'integer');
    $lhs->set_representation('Int');
    my $rhs = $f->make('Constant', value => '2', const_type => 'integer');
    $rhs->set_representation('Int');
    my $add = $f->make('Add', inputs => [$lhs, $rhs]);
    $add->set_representation('Int');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$lhs, $rhs, $add]);
    ok($result->{ok}, 'well-formed Add(Int,Int)->Int passes the invariant');
    is(scalar @{ $result->{violations} }, 0,
        'no violations in well-formed graph');
}

# H2-2: A malformed graph with unbridged repr mismatch FAILS the invariant.
# Add requires Int operands; a Scalar-representation operand with no Coerce
# interposed is a well-typedness violation.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs = $f->make('Constant', value => '1', const_type => 'integer');
    $lhs->set_representation('Int');
    my $bad_rhs = $f->make('Constant', value => '2', const_type => 'integer');
    $bad_rhs->set_representation('Scalar');  # wrong: Add needs Int
    my $add = $f->make('Add', inputs => [$lhs, $bad_rhs]);
    $add->set_representation('Int');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$lhs, $bad_rhs, $add]);
    ok(!$result->{ok}, 'malformed Add(Int,Scalar) without Coerce FAILS the invariant');
    ok(scalar @{ $result->{violations} } > 0,
        'at least one violation reported for unbridged mismatch');
}

# H2-3: A graph bridged by a Coerce node passes.
# Coerce[Scalar->Int](bad_rhs) bridges the gap — the Add sees Int on both operands.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs = $f->make('Constant', value => '1', const_type => 'integer');
    $lhs->set_representation('Int');
    my $scalar_val = $f->make('Constant', value => '2', const_type => 'integer');
    $scalar_val->set_representation('Scalar');
    my $coerce = $f->make('Coerce',
        from_repr => 'Scalar',
        to_repr   => 'Int',
        inputs    => [$scalar_val],
    );
    $coerce->set_representation('Int');
    my $add = $f->make('Add', inputs => [$lhs, $coerce]);
    $add->set_representation('Int');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$lhs, $scalar_val, $coerce, $add]);
    ok($result->{ok}, 'Coerce-bridged graph passes the invariant');
    is(scalar @{ $result->{violations} }, 0,
        'no violations when Coerce bridges the representation gap');
}

# H2-4: violation includes the offending node's id in the report.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs = $f->make('Constant', value => '1', const_type => 'integer');
    $lhs->set_representation('Int');
    my $bad_rhs = $f->make('Constant', value => '99', const_type => 'integer');
    $bad_rhs->set_representation('Num');  # wrong: Add needs Int
    my $add = $f->make('Add', inputs => [$lhs, $bad_rhs]);
    $add->set_representation('Int');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$lhs, $bad_rhs, $add]);
    ok(!$result->{ok}, 'Add(Int,Num) without Coerce fails');
    my $v = $result->{violations}[0];
    ok(defined $v, 'violation record is defined');
    ok(defined $v->{node_id}, 'violation has node_id');
    ok(defined $v->{message}, 'violation has message');
}

# H2-5: A node with undef representation on an operation is NOT a violation
# (undef means "not yet assigned"; the invariant only fires on nodes that
# have a representation that mismatches, NOT on unassigned nodes).
{
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs = $f->make('Constant', value => '1', const_type => 'integer');
    # No set_representation called — representation remains undef
    my $rhs = $f->make('Constant', value => '2', const_type => 'integer');
    my $add = $f->make('Add', inputs => [$lhs, $rhs]);

    my $result = Chalk::IR::Graph::TypedInvariant->check([$lhs, $rhs, $add]);
    ok($result->{ok}, 'undef representation on operands is not a violation (not yet assigned)');
}

# H2-6: Divide requires Num inputs (Perl `/` is always float division).
# A Coerce(Int->Num) bridging each operand satisfies the invariant.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs_i = $f->make('Constant', value => '3', const_type => 'integer');
    $lhs_i->set_representation('Int');
    my $rhs_i = $f->make('Constant', value => '4', const_type => 'integer');
    $rhs_i->set_representation('Int');
    my $coe_lhs = $f->make('Coerce', from_repr => 'Int', to_repr => 'Num',
        inputs => [$lhs_i]);
    $coe_lhs->set_representation('Num');
    my $coe_rhs = $f->make('Coerce', from_repr => 'Int', to_repr => 'Num',
        inputs => [$rhs_i]);
    $coe_rhs->set_representation('Num');
    my $div = $f->make('Divide', inputs => [$coe_lhs, $coe_rhs]);
    $div->set_representation('Num');

    my $result = Chalk::IR::Graph::TypedInvariant->check(
        [$lhs_i, $rhs_i, $coe_lhs, $coe_rhs, $div]);
    ok($result->{ok}, 'Divide(Coerce(Int->Num), Coerce(Int->Num)) passes the invariant');
    is(scalar @{ $result->{violations} }, 0,
        'no violations for well-typed float division graph');
}

# H2-7: Divide with bare Int inputs (no Coerce) fails the invariant.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs = $f->make('Constant', value => '3', const_type => 'integer');
    $lhs->set_representation('Int');
    my $rhs = $f->make('Constant', value => '4', const_type => 'integer');
    $rhs->set_representation('Int');
    my $div = $f->make('Divide', inputs => [$lhs, $rhs]);
    $div->set_representation('Num');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$lhs, $rhs, $div]);
    ok(!$result->{ok}, 'Divide(Int, Int) without Coerce fails the invariant');
    ok(scalar @{ $result->{violations} } > 0, 'violations reported for bare-Int Divide');
}


# H2-8 (Phase 0, bilateral): Length with Array operand passes the invariant.
# Length(Array) is the canonical array-count op; Array is a valid operand repr.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $arr = $f->make('ArrayLiteral', inputs => [$c1]);
    $arr->set_representation('Array');
    my $len = $f->make('Length', inputs => [$arr]);
    $len->set_representation('Int');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$c1, $arr, $len]);
    ok($result->{ok}, 'H2-8 bilateral: Length(Array)->Int passes the invariant');
    is(scalar @{ $result->{violations} }, 0, 'H2-8: no violations for well-typed Length');
}

# H2-9 (Phase 0, bilateral): Length with Int operand FAILS the invariant.
# Length requires Array or Str; an Int operand is a type error.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $wrong = $f->make('Constant', value => '42', const_type => 'integer');
    $wrong->set_representation('Int');
    my $len = $f->make('Length', inputs => [$wrong]);
    $len->set_representation('Int');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$wrong, $len]);
    ok(!$result->{ok}, 'H2-9 bilateral: Length(Int) FAILS the invariant (Int is not Array or Str)');
    ok(scalar @{ $result->{violations} } > 0, 'H2-9: violations reported for ill-typed Length');
}


# H2-10 (Phase 1.1, bilateral): Subscript(Array, Int) passes the invariant.
# Subscript container must be Array or Hash; index must be Int (array) or Str (hash).
{
    my $f = Chalk::IR::NodeFactory->new;

    my $arr = $f->make('ArrayLiteral', inputs => []);
    $arr->set_representation('Array');
    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_representation('Int');
    my $sub = $f->make('Subscript', inputs => [$arr, $idx]);
    $sub->set_representation('Int');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$arr, $idx, $sub]);
    ok($result->{ok}, 'H2-10 bilateral: Subscript(Array, Int) passes the invariant');
    is(scalar @{ $result->{violations} }, 0, 'H2-10: no violations for Subscript(Array,Int)');
}

# H2-11 (Phase 1.1, bilateral): Subscript(Int, Int) FAILS — container must be Array or Hash.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $not_ctr = $f->make('Constant', value => '5', const_type => 'integer');
    $not_ctr->set_representation('Int');
    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_representation('Int');
    my $sub = $f->make('Subscript', inputs => [$not_ctr, $idx]);
    $sub->set_representation('Int');

    my $result = Chalk::IR::Graph::TypedInvariant->check([$not_ctr, $idx, $sub]);
    ok(!$result->{ok}, 'H2-11 bilateral: Subscript(Int, Int) FAILS (Int is not Array or Hash)');
    ok(scalar @{ $result->{violations} } > 0, 'H2-11: violations reported for Subscript with Int container');
}

done_testing;
