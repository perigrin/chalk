# ABOUTME: Every %Slot field access goes through _slot_idx, never a literal index.
# ABOUTME: A literal index is how adding a field becomes a silent miscompile.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Target::LLVM::Context;
my $C = 'Chalk::Target::LLVM::Context';

# WHY THIS TEST EXISTS. A previous attempt added a `tag` field to %Slot at
# index 1, which shifted `payload` from 1 to 2. Every production read and write
# still used literal indices, so:
#   - insertvalue %Slot ..., i64 X, 1   became an i64-into-i8 TYPE ERROR
#   - getelementptr ... i32 1           silently addressed the TAG BYTE
# 16 tests failed and the change was reverted. `_slot_idx` existed to prevent
# exactly this and had ZERO production callers; its test asserted only that the
# function WORKS, never that anything CALLS it -- AC-green over an untested
# path. This test asserts the calling.

sub _production_code {
    my @src;
    for my $f (qw(lib/Chalk/Target/LLVM/Context.pm lib/Chalk/Target/LLVM.pm)) {
        open my $fh, '<', $f or die "$f: $!";
        while (my $l = <$fh>) {
            next if $l =~ /^\s*#/;          # comments describe, they do not emit
            push @src, "$f:$.: $l";
        }
    }
    return @src;
}

subtest '_slot_idx exists and is total over the declared fields' => sub {
    ok $C->can('_slot_idx'), '_slot_idx exists';
    my %seen;
    for my $f ($C->_slot_fields) {
        my $i = $C->_slot_idx($f->{name});
        ok defined $i,        "$f->{name} has an index";
        ok !$seen{$i}++,      "index $i is unique";
    }
    ok !eval { $C->_slot_idx('nope'); 1 }, 'an unknown name dies';
};

subtest 'no emitted %Slot access uses a literal field index' => sub {
    my @bad;
    for my $line (_production_code()) {
        # insertvalue/extractvalue on a %Slot with a trailing literal index
        push @bad, $line
            if $line =~ /(?:insert|extract)value \%Slot [^;]*,\s*\d+\s*(?:;|")/;
        # getelementptr into a %Slot* with a literal FIELD index. A GEP
        # through a pointer takes TWO indices and the first is the pointer
        # deref -- a literal 0 there is correct and not a field reference.
        # Only the LAST index selects a field, so anchor on end-of-args.
        push @bad, $line
            if $line =~ /getelementptr[^;"]*\%Slot[^;"]*i32 \d+\s*(?:"|;|\\n)/;
    }
    is scalar(@bad), 0, 'every %Slot field access is named'
        or diag join '', map { "  $_" } @bad;
};

subtest 'the field list is the single source of the layout' => sub {
    my $decl = $C->_slot_type_decl;
    like $decl, qr/^%Slot\s*=\s*type/, 'declaration is rendered';
    for my $f ($C->_slot_fields) {
        like $decl, qr/\Q$f->{llvm}\E/, "declares $f->{name}";
    }
};

done_testing;
