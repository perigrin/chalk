# ABOUTME: Scalar is a lowerable stamp -- it has a machine encoding (%Slot),
# ABOUTME: so the loader must carry it through rather than dropping it.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::IR::Serialize::JSON ();

# %LOWERABLE_STAMP answers ONE question: can the backend lower this stamp?
# It was written when Scalar had no machine encoding, so Scalar was excluded
# with the ref types. Scalar now encodes as %Slot, the uniform cell, and the exclusion outlived its reason -- a method returning an
# un-narrowed Scalar reached the backend with no representation at all and
# GAPped, the largest single group in the corpus gate.
#
# `Unknown` is a DIFFERENT case and must stay excluded: it is the absence of an
# answer, not an answer, and admitting it would let a node claim a machine
# encoding it does not have.

my $is_lowerable = \&Chalk::IR::Serialize::JSON::is_lowerable_stamp;

subtest 'Scalar is lowerable' => sub {
    ok($is_lowerable->('Scalar'), 'Scalar is admitted to the representation field');
};

subtest 'Unknown stays excluded' => sub {
    # The absence of an answer is not an answer. A node still holding Unknown at
    # machine-type selection must GAP, not claim an encoding.
    ok(!$is_lowerable->('Unknown'), 'Unknown is NOT admitted');
};

done_testing;
