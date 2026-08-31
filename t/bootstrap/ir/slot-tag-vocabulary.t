# ABOUTME: The %Slot tag vocabulary covers every representation _box_payload boxes, each distinctly.
# ABOUTME: A boxable repr with no tag of its own would be read back as the wrong kind of value.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::Target::LLVM::Context;

# ---------------------------------------------------------------------------
# The tag names how a %Slot payload should be READ. The payload is 8 raw bytes
# whose interpretation is recorded nowhere else, so a consumer that has to
# stringify or numify one has to guess -- and today the backend refuses instead.
#
# The vocabulary is only useful if it is TOTAL over what _box_payload actually
# boxes. A boxable repr missing from the table used to fall back to 'Undef',
# which makes a live heap pointer indistinguishable from an undefined cell:
# not a type error LLVM would catch, but a wrong value read at runtime.
#
# This file pins the vocabulary only. The tag FIELD does not exist yet, so
# nothing here touches emitted IR.
# ---------------------------------------------------------------------------

# The boxable set, derived from _box_payload's own source rather than copied.
# Copying it is how the two drift: a repr added to the boxer would leave this
# test green while the new payload read back as undef.
my $src = do {
    open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
    local $/; <$fh>;
};
my ($body) = $src =~ /^sub _box_payload \{(.*?)^\}/ms;
ok(defined $body, '_box_payload found in Context.pm');

my %boxable;
$boxable{$_} = 1 for $body =~ /\$repr eq '(\w+)'/g;

is_deeply(
    [sort keys %boxable],
    [qw(ArrayRef Boolean CodeRef HashRef Int Num Object Str)],
    '_box_payload boxes the eight expected representations'
);

# --- Undef is 0 -------------------------------------------------------------
#
# A zeroed or memset cell must read as undef, never as a valid value of some
# other type. This is the one tag value whose NUMBER is load-bearing.
is(Chalk::Target::LLVM::Context::_slot_tag_value('Undef'), 0, 'Undef tag is 0');

# --- every boxable repr has a tag, and they are all distinct ----------------
my %seen;
for my $repr (sort keys %boxable) {
    my $v = eval { Chalk::Target::LLVM::Context::_slot_tag_value($repr) };
    ok(defined $v, "boxable repr '$repr' has a tag value") or next;
    ok(!exists $seen{$v}, "tag $v for '$repr' is not already used by '" . ($seen{$v} // '') . "'");
    $seen{$v} = $repr;
}

# --- and none of them collides with Undef ----------------------------------
#
# The specific conflation this file exists to prevent: a boxed pointer whose
# tag reads 0 is indistinguishable from a cell that is genuinely undef.
for my $repr (sort keys %boxable) {
    isnt(Chalk::Target::LLVM::Context::_slot_tag_value($repr), 0,
        "boxable repr '$repr' does not share Undef's tag");
}

# --- _slot_tag_for_repr never silently maps a boxable repr to Undef --------
for my $repr (sort keys %boxable) {
    is(Chalk::Target::LLVM::Context::_slot_tag_for_repr($repr), $repr,
        "_slot_tag_for_repr('$repr') maps to itself, not Undef");
}

# --- "not established" is a DIFFERENT fact from "is undef" -----------------
#
# A Scalar whose narrowing failed is not a value that IS undef: the first says
# the reading was never determined, the second asserts a reading. One tag value
# cannot carry both -- collapsing them is what would make a T2 consumer treat an
# un-narrowed cell as a known-undef one and skip the coercion it still needs.
is(Chalk::Target::LLVM::Context::_slot_tag_for_repr('Scalar'), 'Opaque',
    'un-narrowed Scalar tags as Opaque, not Undef');
is(Chalk::Target::LLVM::Context::_slot_tag_for_repr('Unknown'), 'Opaque',
    'Unknown tags as Opaque, not Undef');
is(Chalk::Target::LLVM::Context::_slot_tag_for_repr(undef), 'Opaque',
    'a missing repr tags as Opaque, not Undef');
isnt(Chalk::Target::LLVM::Context::_slot_tag_value('Opaque'), 0,
    'Opaque is distinct from Undef');

# Undef itself still round-trips: it IS a representation in the lattice.
is(Chalk::Target::LLVM::Context::_slot_tag_for_repr('Undef'), 'Undef',
    "an actual Undef repr still tags as Undef");

done_testing;
