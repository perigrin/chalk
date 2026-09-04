# ABOUTME: An Undef arm is a lattice element, not an absence -- it enters the
# ABOUTME: join like every other arm, and Undef joined with Int is Scalar.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::IR::Analysis;
require Chalk::IR::NodeFactory;
require Chalk::IR::Graph;

# The propagation pass used to strip every `Undef` arm out of a merge's input
# reprs before joining, on the argument that "Undef contributes no value to
# widen". That argument is about RUNTIME VALUES, and the join is about TYPES: a
# `//` whose left arm may be undef yields Undef on one path and Int on the
# other, so the merge's static type is the join of both -- Scalar, the least
# upper bound of two siblings. Dropping the Undef arm reports Int for a value
# that is provably not always an Int.
#
# The drop existed because the old partial `_join_repr` could not rank Undef at
# all and returned undef for the pair, which read downstream as "inference
# failed". The join is total now (join-is-the-lattice-join.t), so the drop is
# the only thing left that lies.
#
# Scalar has no machine encoding until T2 exists, so the three corpus cases
# that merge Undef with a defined arm (L3b, L3c, L3d in logical.md) are
# DECLARED GAPs while this stands. See spec 9.5.

sub dor_repr ( $left_repr, $right_repr ) {
    my $f = Chalk::IR::NodeFactory->new;

    # DISTINCT values so the two Constants cannot hash-cons into one node --
    # a collapsed input list would make this test pass for the wrong reason.
    my $i  = 0;
    my @in = map {
        my $n = $f->make( 'Constant', const_type => 'integer', value => ++$i );
        $n->set_stamp($_);
        $n;
    } ( $left_repr, $right_repr );

    my $d = $f->make( 'DefinedOr', inputs => \@in );

    my $g = Chalk::IR::Graph->new;
    $g->merge($_) for $d, @in;
    Chalk::IR::Analysis::_propagate_computed_reprs( { g => $g } );
    return $d->stamp;
}

subtest 'an Undef arm widens the merge to Scalar' => sub {
    is dor_repr( 'Undef', 'Int' ), 'Scalar',
        'DefinedOr(Undef, Int) is Scalar -- the join of two siblings, not Int';
};

# BILATERAL. Without this, the subtest above passes against a join that answers
# Scalar for everything -- which is exactly what deleting too much would do.
subtest 'a merge with no Undef arm is unaffected' => sub {
    is dor_repr( 'Int', 'Int' ), 'Int',
        'DefinedOr(Int, Int) is still Int';

    is dor_repr( 'Int', 'Str' ), 'Str',
        'and Int|Str still widens along the chain to Str';
};

done_testing;
