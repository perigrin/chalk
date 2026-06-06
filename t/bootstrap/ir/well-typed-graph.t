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

done_testing;
