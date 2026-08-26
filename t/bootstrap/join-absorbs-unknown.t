# ABOUTME: `Unknown` is the pessimistic top and ABSORBS: a join with an Unknown
# ABOUTME: arm is Unknown, because inference cannot manufacture what it missed.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::IR::Analysis;
use Chalk::Grammar::Perl::TypeLibrary;
require Chalk::IR::Serialize::JSON;

# `Unknown` is the SOUND TOP: everything is a subtype of it, so it wins every
# least-upper-bound. That is the ANSWER, not a malfunction. A merge of an
# inferred arm with an arm inference could not type is not "the inferred type" --
# the value flowing out of the merge may be either arm, and one of them is not
# known to be an Int. Typing the merge from the known arm alone is a GUESS about
# the other arm, and the backend would unbox on it.
#
#     join(Int, Int)     = Int
#     join(Int, Unknown) = Unknown      <- correct: one arm is not known
#
# An Unknown result leaves the node untyped, the backend GAPs loudly, and the
# gap names a real hole in inference. That is the outcome T1 wants: the fix for
# an Unknown arm is to INFER it, not to discard it.
#
# CONTRAST with the `Undef` drop, still live in Analysis.pm's join-rule handler
# (`_seed_and_propagate_reprs`, the `grep { $_ ne 'Undef' }` above the
# `_join_repr` call). That one is SEMANTIC -- `$a // $b` never yields undef when
# $a is defined -- where absorb is EPISTEMIC. Do not read one as precedent for
# the other.

subtest 'the lattice fact that motivates absorb' => sub {
    is Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Unknown'), 1,
        'Int <: Unknown -- Unknown is top';
    ok !Chalk::Grammar::Perl::TypeLibrary::is_subtype('Unknown', 'Int'),
        'Unknown is NOT a subtype of Int';
};

subtest 'a join with an Unknown arm is Unknown' => sub {
    my $j = Chalk::IR::Analysis::_join_repr('Int', 'Unknown');
    is $j, 'Unknown', 'Int joined with Unknown absorbs to Unknown';

    is Chalk::IR::Analysis::_join_repr('Unknown', 'Int'), 'Unknown',
        'and the same regardless of arm order';

    is Chalk::IR::Analysis::_join_repr('Int', 'Str'), 'Str',
        'a join of two KNOWN types is unaffected';
};

# Absorption must not depend on there being a known arm to absorb.
subtest 'an all-Unknown join stays undetermined' => sub {
    is Chalk::IR::Analysis::_join_repr('Unknown', 'Unknown'), 'Unknown',
        'nothing known -> still Unknown, not a guessed type';
};

done_testing;
