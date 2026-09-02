# ABOUTME: T2 may be a partial functor, but every unmapped type must say why.
# ABOUTME: A type with neither a machine type nor a named refusal is a silent gap.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Target::LLVM::Context;

# T2 IS A FUNCTOR INTO A CATEGORY THAT NEED NOT BE TOTAL OVER THE SOURCE. We
# map the arrows we can map, so a Chalk type with no machine type is a
# legitimate outcome -- an LValueRef aliases a RANGE and a pointer cannot
# express it; a GlobRef points at a symbol table this lowering does not have.
#
# WHAT IS NOT LEGITIMATE IS SILENCE. `_repr_to_llvm_type` already draws the
# line in its own failure message -- "add it to %_REPR_LLVM_TYPE with its
# machine type, or to %_REPR_NO_MACHINE_TYPE with the reason it has none" --
# so a type reaching it with neither gets "this is not a known
# representation", which is true and says nothing about whether the absence
# was decided. Seven types were in that state; this pins that none is again.
#
# EPHEMERAL TYPES ARE EXCLUDED and are a different case entirely. An ephemeral
# value exists during evaluation with no storage and no address, so it cannot
# have a single-value layout by construction: `List` is arity-polymorphic,
# `Void` is arity 0, `Unknown` is the absence of an answer. Their refusals are
# about the LATTICE, not about this target, and they would be refused by any
# T2 (perigrin's framing: T2 cannot be total over the lattice, but it should
# be total over the non-ephemeral types).

my $MAP = Chalk::Target::LLVM::Context::_repr_llvm_type_map();

# A NAMED refusal dies with its own reason; an unnamed one dies with the
# generic "not a known representation". That difference IS the property under
# test, so it is read from the message rather than from a second table.
sub classification ($type) {
    return 'mapped' if exists $MAP->{$type};
    my $err = '';
    eval { Chalk::Target::LLVM::Context::_repr_to_llvm_type($type); 1 } or $err = $@;
    return 'silent' if !$err || $err =~ /not a\s+known representation/s;
    return 'named';
}

# Every lattice type that denotes a single value with storage. Listed rather
# than derived, so adding a type to the lattice without deciding its T2 fate
# fails here rather than passing unnoticed.
my @NON_EPHEMERAL = qw(
    Scalar Undef Str Num Int Boolean VString DualVar
    Ref Object Regex ScalarRef LValueRef ArrayRef HashRef CodeRef GlobRef
    Array Hash
);

subtest 'no non-ephemeral type is silently unmapped' => sub {
    my @silent = grep { classification($_) eq 'silent' } @NON_EPHEMERAL;
    is_deeply(\@silent, [],
        'every non-ephemeral type is either mapped or refused BY NAME')
        or diag("  silent: @silent\n"
              . "  => add a machine type, or a %_REPR_NO_MACHINE_TYPE entry\n"
              . "     saying why it has none. Silence blames the type layer\n"
              . "     for a target's limit.");
};

# The partition itself, asserted so a change of mind is visible. These are not
# arbitrary: each refusal names a structural reason the value has no
# single-scalar layout in THIS target.
subtest 'the partition is deliberate on both sides' => sub {
    my %expect = (
        # Mapped: a layout exists and is committed to.
        Scalar => 'mapped', Undef => 'mapped', Str  => 'mapped',
        Num    => 'mapped', Int   => 'mapped', Boolean => 'mapped',
        Object => 'mapped', Array => 'mapped', Hash => 'mapped',
        # Every reference kind that has inhabitants is a pointer.
        ScalarRef => 'mapped', ArrayRef => 'mapped',
        HashRef   => 'mapped', CodeRef  => 'mapped',
        # Ref too: perl reports a ref-to-ref as REF, so it is inhabited.
        Ref       => 'mapped',

        # Refused, each for its own structural reason:
        LValueRef => 'named',  # aliases a RANGE: needs base+offset+len
        GlobRef   => 'named',  # points at a symbol table we do not have
        DualVar   => 'named',  # two independent values in one cell
        VString   => 'named',  # Str plus V magic %Str cannot carry
        Regex     => 'named',  # resolved statically, never reaches runtime
    );

    for my $t (sort keys %expect) {
        is(classification($t), $expect{$t},
            "$t is " . ($expect{$t} eq 'mapped' ? 'mapped' : 'refused by name'));
    }
};

# `Ref` IS INHABITED, and an earlier version of this file asserted the
# opposite. perl reports `\\$y` -- a reference to a reference -- as `REF`
# from both ref() and reftype(), a kind distinct from SCALAR. So there IS a
# value whose own type is Ref, and calling it an abstract classifier was a
# claim about capitalisation ("nothing has ref() eq 'Ref'") rather than about
# inhabitants.
#
# Its layout needs no separate thought: a ref-to-ref is a pointer like every
# other reference, so T2 maps it to the same i8*. TWO CHALK TYPES SHARING ONE
# LLVM TYPE IS ORDINARY and not a smell -- Boolean and Undef already share
# i1. The functor is not required to be injective; T1 keeps the two types
# distinct and does not need to care that T2's images coincide.
subtest 'Ref is inhabited, and shares its target type with ScalarRef' => sub {
    my $y  = 5;
    my $r  = \$y;
    my $rr = \$r;

    is(ref($r),  'SCALAR', 'a reference to a scalar is SCALAR');
    is(ref($rr), 'REF',    'a reference to a REFERENCE is REF -- a distinct kind');
    isnt(ref($rr), ref($r),
        'perl names them differently, so Ref is not merely ScalarRef');

    is(classification('Ref'), 'mapped', 'so Ref has a machine type');
    is($MAP->{Ref}, $MAP->{ScalarRef},
        'and it is the SAME one as ScalarRef -- both are pointers');

    # The functor may collapse distinct types onto one target type. Asserted
    # against a pair that has always done so, to show this is the rule rather
    # than an exception made for Ref.
    is($MAP->{Boolean}, $MAP->{Undef},
        'Boolean and Undef likewise share i1 -- T2 need not be injective');
};

done_testing;
