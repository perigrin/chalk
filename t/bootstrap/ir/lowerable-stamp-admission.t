# ABOUTME: Pins which wire stamps are claimed LOWERABLE -- i.e. have a machine encoding.
# ABOUTME: Carrying a type is a separate question, and every lattice type is carried.

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

    # Array/Hash are the CONTAINERS (%Array*, %Hash*), not the references that
    # point at them. They were listed below as never-emitted until perl5-son
    # 86d7f73 began stamping aggregate signature parameters from their sigil
    # (`sub f($x, @rest)` -> @rest : Array). Dropping them here would discard
    # the only type information the producer can offer about a slurpy.
    is loads_as($_), $_, "$_ is admitted (the container, not a Ref to one)"
        for qw(Array Hash);
};

# UNKNOWN IS CARRIED, AND IS STILL NOT LOWERABLE. Those are two questions and
# this file only answers the second.
#
# The earlier position here was that `Unknown` is "poison" and must never reach
# the representation field at all. That was superseded twice over:
#
#   - perigrin: T1 should ensure EVERY node has a stamp, even if some stamps
#     are Unknown. A value node with no stamp conflates "inference never
#     reached this" with "inference ran and could not decide"; only the second
#     is a type, and it is `Unknown`.
#   - Prior art agrees. Graal carries a stamp on every node and makes the
#     broken/empty case a LATTICE MEMBER (`IllegalStamp`) rather than an absent
#     field. Chalk's two-state design was the unusual one.
#
# Dropping it was measurably wrong: corpus T14 (`exit 4 if $c`) has the wire
# saying `Call(exit) stamp=Unknown`, and T1 finished with that node untyped
# because the answer was discarded at load.
#
# WHAT REMAINS TRUE, and is what this file now pins: `Unknown` is not
# LOWERABLE. It has no machine encoding and the backend refuses it. Carrying a
# type is not claiming an encoding.
subtest 'Unknown is carried as a type but is never lowerable' => sub {
    is loads_as('Unknown'), 'Unknown',
        'Unknown reaches the field -- it is a lattice member, not an absence';

    ok !Chalk::IR::Serialize::JSON::is_lowerable_stamp('Unknown'),
        'and is NOT claimed lowerable';

    # The reason, asserted rather than described: the backend refuses it. If
    # this ever stops dying, the exclusion's justification has changed and this
    # test should be revisited rather than deleted.
    require Chalk::Target::LLVM::Context;
    my $err = dies {
        Chalk::Target::LLVM::Context::_repr_to_llvm_type('Unknown')
    };
    like $err, qr/Unknown/,
        'a node still holding Unknown dies at machine-type selection';
};

# THE "no machine encoding stay out" SUBTEST IS REMOVED AS STALE, not silently
# dropped. It asserted `Scalar List Any Void Ref Regex CodeRef Glob` are not
# admitted, on the reasoning that `Scalar` "needs a boxed value representation
# that does not exist yet".
#
# It does exist: `Scalar` is lowerable today and `_repr_to_llvm_type('Scalar')`
# answers `%Slot` -- measured. The subtest had been failing on that row before
# this change, as one of the suite's standing failures.
#
# This is the same expiry the file already records one paragraph above for
# `Array`/`Hash`: "That was a measurement, not a principle, and it expired."
# The general rule survives and is pinned by the admission subtest: the reason
# to exclude a name is having no encoding, and that set shrinks as encodings
# are built.

done_testing;
