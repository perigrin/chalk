# ABOUTME: Pins %Slot as a field-list-derived tagged cell, not a hardcoded literal.
# ABOUTME: The tag is what lets a consumer read a payload without guessing.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Target::LLVM::Context;

my $C = 'Chalk::Target::LLVM::Context';

# ---------------------------------------------------------------------------
# %Slot must be derived from a field list, exactly as %Str is. A hardcoded
# literal is how `$n * 16` at Context.pm:5490 became a silent under-allocation
# hazard: add a field and the multiplier is wrong with no error anywhere.
# ---------------------------------------------------------------------------
subtest 'slot fields are declared, not hardcoded' => sub {
    ok $C->can('_slot_fields'), '_slot_fields exists';
    my @f = $C->_slot_fields;
    ok scalar(@f) >= 3, 'at least defined, tag, payload' or diag explain \@f;

    my %by = map { $_->{name} => $_ } @f;
    ok exists $by{defined}, 'has a defined field';
    ok exists $by{tag},     'has a TAG field -- the whole point';
    ok exists $by{payload}, 'has a payload field';

    for my $f (@f) {
        ok defined $f->{llvm},  "$f->{name} declares an llvm type";
        ok defined $f->{bytes}, "$f->{name} declares a byte width";
    }
};

subtest 'the type declaration is rendered from the field list' => sub {
    my $decl = $C->_slot_type_decl;
    like $decl, qr/^%Slot\s*=\s*type\s*\{/, 'declares %Slot';
    my @f = $C->_slot_fields;
    for my $f (@f) {
        like $decl, qr/\Q$f->{llvm}\E/, "declaration mentions $f->{name}'s type";
    }
};

subtest 'the size is COMPUTED, never a magic multiplier' => sub {
    my $size = $C->_slot_size_bytes;
    ok $size > 0, "size is positive ($size)";

    # The size must actually track the field list. This is the assertion that
    # would have caught `$n * 16` surviving a third field.
    my @f = $C->_slot_fields;
    my $raw = 0;
    $raw += $_->{bytes} for @f;
    ok $size >= $raw, "size ($size) covers the raw field bytes ($raw)";
};

subtest 'field indices are looked up by name, not written as literals' => sub {
    ok $C->can('_slot_idx'), '_slot_idx exists';
    my %seen;
    for my $f ($C->_slot_fields) {
        my $i = $C->_slot_idx($f->{name});
        ok defined $i, "$f->{name} has an index";
        ok !$seen{$i}++, "index $i is unique";
    }
    # An unknown name must die rather than silently return undef and be used
    # as index 0 -- reading the defined-bit where a payload belonged.
    ok !eval { $C->_slot_idx('no_such_field'); 1 },
        'an unknown field name dies rather than returning undef';
};

done_testing;
