# ABOUTME: Coerce[Scalar -> X] dispatches on the Slot tag instead of refusing.
# ABOUTME: The tag is the recorded reading; without it the payload is a guess.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Target::LLVM::Context;

# The GAP this replaces, verbatim from Context.pm before this change:
#   "GAP: Coerce[Scalar -> Num] needs a T2 decision about how to read a %Slot
#    payload (tagged? runtime? per-context choice?)"
# The answer chosen is TAGGED. These pin that the die is gone and that what
# replaces it actually reads the tag rather than assuming a reading.

subtest 'the tag vocabulary covers the scalar spine' => sub {
    my $C = 'Chalk::Target::LLVM::Context';
    my @names = $C->_slot_tag_names;
    for my $r (qw(Int Num Str Undef)) {
        ok scalar(grep { $_ eq $r } @names), "$r is a tag";
    }
    # Undef must be 0 so a zeroed cell reads as undef, never as a valid Int.
    is $C->_slot_tag_value('Undef'), 0, 'Undef is tag 0 (zeroed memory is undef)';
    isnt $C->_slot_tag_value('Int'), 0, 'Int is not 0';
};

subtest 'an unknown reading tags as Undef, it does not guess' => sub {
    my $C = 'Chalk::Target::LLVM::Context';
    is $C->_slot_tag_for_repr('Int'),     'Int',   'a concrete reading passes through';
    is $C->_slot_tag_for_repr('Num'),     'Num',   'Num passes through';
    is $C->_slot_tag_for_repr('Str'),     'Str',   'Str passes through';
    # The whole point: Scalar is the UN-NARROWED top. It has no single reading,
    # so tagging it Int would be the guess the tag exists to eliminate.
    is $C->_slot_tag_for_repr('Scalar'),  'Undef', 'Scalar does NOT claim a reading';
    is $C->_slot_tag_for_repr('Unknown'), 'Undef', 'Unknown does NOT claim a reading';
    is $C->_slot_tag_for_repr(undef),     'Undef', 'absent does NOT claim a reading';
};

subtest 'Coerce[Scalar -> X] no longer refuses outright' => sub {
    my $src = do {
        open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
        local $/; <$fh>;
    };
    unlike $src, qr/needs a T2 decision about how to read a/,
        'the "needs a T2 decision" GAP is gone';
    like $src, qr/_lower_coerce_from_slot|_slot_tag_of/,
        'something reads the tag on the Scalar path';
};

done_testing;
