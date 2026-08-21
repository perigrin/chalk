# ABOUTME: `Unknown` contributes no constraint to a join and must be dropped,
# ABOUTME: so a merge with one inferred arm and one Unknown arm types from the known arm.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::Grammar::Perl::TypeLibrary;
require Chalk::IR::Serialize::JSON;

# `Unknown` is the SOUND TOP: everything is a subtype of it, so it wins every
# least-upper-bound and DISCARDS the known arm. Measured before this fix:
#
#     join(Int, Int)     = Int
#     join(Int, Unknown) = Unknown      <- the known type is thrown away
#
# The join is not malfunctioning -- LUB is the right operation for merging two
# KNOWN types and the wrong one for "one arm is known, the other has not been
# inferred yet". `Unknown` is not a claim about the value at all; it is an
# admission that inference has not finished, so it must not constrain the result.
#
# PRECEDENT in this same file: `Undef` is already dropped before joining for
# the `//` case (Serialize/JSON.pm:1548). The justifications differ and both
# are worth keeping straight -- `Undef` is dropped for a SEMANTIC reason ($a//$b
# never yields undef when $a is defined), `Unknown` for an EPISTEMIC one.

subtest 'the lattice fact that motivates the drop' => sub {
    is Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Unknown'), 1,
        'Int <: Unknown -- Unknown is top';
    ok !Chalk::Grammar::Perl::TypeLibrary::is_subtype('Unknown', 'Int'),
        'Unknown is NOT a subtype of Int';
};

subtest 'a join with an Unknown arm types from the known arm' => sub {
    my $j = Chalk::IR::Serialize::JSON::_join_repr('Int', 'Unknown');
    is $j, 'Int', 'Int joined with Unknown is Int, not Unknown';

    is Chalk::IR::Serialize::JSON::_join_repr('Unknown', 'Int'), 'Int',
        'and the same regardless of arm order';

    is Chalk::IR::Serialize::JSON::_join_repr('Int', 'Str'), 'Str',
        'a join of two KNOWN types is unaffected';
};

# Dropping every arm must NOT make the join succeed vacuously. An all-Unknown
# merge is still undetermined, and _join_repr's contract is to return undef so
# the caller leaves the node untyped and the backend GAPs loudly.
subtest 'an all-Unknown join stays undetermined' => sub {
    is Chalk::IR::Serialize::JSON::_join_repr('Unknown', 'Unknown'), 'Unknown',
        'nothing known -> still Unknown, not a guessed type';
};

done_testing;
