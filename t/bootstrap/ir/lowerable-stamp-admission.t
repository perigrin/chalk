# ABOUTME: Pins which wire stamps may enter the shared representation field.
# ABOUTME: ArrayRef/HashRef are admitted; Unknown is poison and must stay out.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::Serialize::JSON;

# %LOWERABLE_STAMP filters the wire stamps that reach the representation field.
# Because `stamp` and `representation` are ONE FIELD under the transitional
# alias (Chalk::IR::Node), admitting a name here simultaneously claims it as a
# machine encoding -- so the list is a claim about lowerability, not about the
# lattice.
#
# Slice 3b (docs/plans/2026-08-24-loader-analysis-pipeline.md) added ArrayRef
# and HashRef. Both already had encodings in %_REPR_LLVM_TYPE (`i8*`, a boxed
# aggregate pointer), so dropping them was an omission rather than a decision.
#
# This file pins BOTH directions, because the interesting failure is not "did
# we add the two" -- it is "did someone widen this to everything". Measured
# over four aggregate programs, `Unknown` is 976 of ~1800 wire stamps; a naive
# widening floods the field with a value that dies at machine-type selection.

# The filter itself is a lexical, and it stays one -- exposing production state
# to make it assertable would be the tail wagging the dog. So drive it the way
# the loader does: hand it a wire node carrying a stamp and ask what reached the
# field. That also tests the thing that actually matters (what a load produces)
# rather than the shape of a hash.
sub loads_as ($stamp) {
    my $wire = {
        methods => {
            'main::probe' => {
                name  => 'main::probe',
                nodes => [
                    { id => 0, op => 'Start',    inputs => [] },
                    { id => 1, op => 'Constant', inputs => [],
                      const_type => 'int', value => 1, stamp => $stamp },
                    { id => 2, op => 'Return',   inputs => [0, 1] },
                ],
                start   => 0,
                returns => [2],
            },
        },
    };
    require JSON::PP;
    my ($graphs) = Chalk::IR::Serialize::JSON::from_json(
        JSON::PP->new->canonical->encode($wire));
    my ($const) = grep { $_->operation eq 'Constant' }
        $graphs->{'main::probe'}->nodes->@*;
    return $const->representation;
}

subtest 'the lowerable names reach the field' => sub {
    # Int/Num/Str/Boolean/Undef/Object were always admitted; ArrayRef/HashRef
    # are what slice 3b added.
    is loads_as($_), $_, "$_ is admitted"
        for qw(Int Num Str Boolean Undef Object ArrayRef HashRef);
};

subtest 'Unknown is excluded -- it is poison, not merely unlowerable' => sub {
    isnt loads_as('Unknown'), 'Unknown',
        'Unknown may not enter the representation field';

    # The reason, asserted rather than described: the backend refuses it.
    # If this ever stops dying, the exclusion's justification has changed and
    # this test should be revisited rather than deleted.
    require Chalk::Target::LLVM::Context;
    my $err = dies {
        Chalk::Target::LLVM::Context::_repr_to_llvm_type('Unknown')
    };
    like $err, qr/Unknown/,
        'a node still holding Unknown dies at machine-type selection';
};

subtest 'the never-emitted lattice names stay out' => sub {
    # These exist in the lattice but have no machine encoding. `Scalar` in
    # particular IS emitted by the producer (measured: 4 per program) and is
    # correctly dropped -- it needs a boxed value representation that does not
    # exist yet.
    isnt loads_as($_), $_, "$_ is not admitted"
        for qw(Scalar List Any Void Ref Regex CodeRef Array Hash Glob);
};

done_testing;
