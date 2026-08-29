# ABOUTME: A field store is coherent when the payload's written interpretation
# ABOUTME: matches the one the read applies -- not when the two reprs are equal.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::Target::LLVM::Context ();

# The i64 field payload carries ONE of two kinds of thing:
#
#   DIRECT  -- the value itself, sitting in the 64 bits (Int identity,
#              Boolean zext).
#   BOXED   -- a POINTER to something else, stored via ptrtoint (Str is a
#              StrPair*, ArrayRef/HashRef are i8*).
#
# _store_field_payload picks by the VALUE's repr; _lower_field_access_in_method
# reads by the FieldAccess NODE's repr. Those two must agree about which kind
# the bits are, or the read `inttoptr`s an integer (or loads a pointer as a
# number) and segfaults.
#
# `field_repr ne $repr` was a crude stand-in for that question. It is wrong in
# BOTH directions: it rejects Int-into-Scalar, which is coherent (the cell is
# already a %Slot and the payload is a plain i64 either way), and it would
# accept nothing across the direct/boxed line that equality happens to miss.

my $coherent = Chalk::Target::LLVM::Context->can('_field_store_is_coherent')
    or BAIL_OUT('_field_store_is_coherent not implemented');

subtest 'a refinement of the general cell is coherent' => sub {
    # THE REGRESSION THIS FIXES. The producer widened `:param` fields to
    # Scalar (9d23bda); T1 then correctly narrows the constructor argument to
    # Int. Int <: Scalar is a REFINEMENT, and the payload is a plain i64 under
    # both readings, so the store is coherent and 9 corpus `classes` cases were
    # being refused for no reason.
    ok($coherent->('Scalar', 'Int'),     'Int value into a Scalar field');
    ok($coherent->('Scalar', 'Boolean'), 'Boolean value into a Scalar field');
};

subtest 'identical interpretations stay coherent' => sub {
    ok($coherent->($_, $_), "$_ into a $_ field")
        for qw(Int Boolean Str ArrayRef HashRef);
};

subtest 'crossing the direct/boxed line is NOT coherent' => sub {
    # These are the pairs the guard exists for: the bits mean different things
    # on each side, so the read misinterprets them. An Int written directly and
    # read as Str is `inttoptr`d into a StrPair* -- the segfault the original
    # comment names.
    ok(!$coherent->('Str', 'Int'),      'Int value into a Str field: read would inttoptr it');
    ok(!$coherent->('Int', 'Str'),      'Str pointer into an Int field: read would use the address as a number');
    ok(!$coherent->('ArrayRef', 'Int'), 'Int into an ArrayRef field');
    ok(!$coherent->('Int', 'ArrayRef'), 'ArrayRef pointer into an Int field');
    ok(!$coherent->('Str', 'ArrayRef'), 'two DIFFERENT boxed kinds are still incoherent');
};

subtest 'a boxed value into the general cell is NOT silently allowed' => sub {
    # Scalar is refinable, but a Scalar-declared field READ still loads a bare
    # i64. Storing a StrPair* there and reading it as a number is exactly the
    # misinterpretation this guard is for -- being a supertype does not make it
    # coherent, which is why subtyping alone is the WRONG test.
    ok(!$coherent->('Scalar', 'Str'),
       'Str into a Scalar field: Str <: Scalar, yet the encodings disagree');
    ok(!$coherent->('Scalar', 'ArrayRef'), 'ArrayRef into a Scalar field');
};

subtest 'an undeclared field repr imposes no constraint' => sub {
    ok($coherent->(undef, 'Int'), 'no declared repr: nothing to disagree with');
    ok($coherent->(undef, 'Str'), 'no declared repr, boxed value');
};

done_testing;
