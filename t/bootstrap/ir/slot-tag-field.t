# ABOUTME: The %Slot tag field exists, is required at construction, and is written everywhere.
# ABOUTME: Pins the named-index discipline that a previous literal-index attempt broke.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;
use Chalk::Target::LLVM::Context;

my $C = 'Chalk::Target::LLVM::Context';

# ---------------------------------------------------------------------------
# The field exists, and every index is asked for BY NAME.
#
# A previous attempt added this field and left production reading literal
# indices, which turned `payload` from 1 into 2 while every site still said 1:
# insertvalue became an i64-into-i8 type error and getelementptr silently
# addressed the tag byte. Nothing below hardcodes an index.
# ---------------------------------------------------------------------------
subtest 'the tag is a declared field between defined and payload' => sub {
    my @names = map { $_->{name} } $C->_slot_fields;
    is_deeply \@names, [qw(defined tag payload)],
        'the field order is defined, tag, payload';

    my ($tag) = grep { $_->{name} eq 'tag' } $C->_slot_fields;
    is $tag->{llvm}, 'i8', 'the tag is an i8';

    is $C->_slot_type_decl, '%Slot = type { i1, i8, i64 }',
        'the emitted type declaration carries it';
};

# ---------------------------------------------------------------------------
# The tag is REQUIRED. A default would be a guess wearing the syntax of a
# fact, and the whole point of the field is to stop consumers guessing.
# ---------------------------------------------------------------------------
subtest 'a Slot cannot be built without saying what the payload means' => sub {
    my $ctx = $C->new;
    ok !eval { $ctx->_build_slot('i1 true', '%p', undef, 'probe'); 1 },
        'omitting the tag dies rather than defaulting';
    ok !eval { $ctx->_build_slot('i1 true', '%p', '', 'probe'); 1 },
        'an empty tag dies too';

    # The escape hatch is EXPLICIT, not a default: a caller that does not know
    # the reading must say so.
    ok eval { $C->new->_build_slot('i1 true', '%p', 'Opaque', 'probe'); 1 },
        "'Opaque' is how a caller says the reading is not established";
};

# ---------------------------------------------------------------------------
# Construction writes EVERY field. A field with no write is poison at runtime
# -- not a type error lli would catch, but a wrong value.
# ---------------------------------------------------------------------------
subtest 'construction writes every declared field, at its named index' => sub {
    my $ctx = $C->new;
    $ctx->_build_slot('i1 true', '%p', 'Int', 'probe');
    my $ir = join "\n", $ctx->render_blocks(1);

    my @inserts = $ir =~ /insertvalue/g;
    is scalar(@inserts), scalar($C->_slot_fields),
        'one insertvalue per declared field';

    my $i_def = $C->_slot_idx('defined');
    my $i_tag = $C->_slot_idx('tag');
    my $i_pay = $C->_slot_idx('payload');
    like $ir, qr/insertvalue %Slot undef, i1 true, $i_def\b/, 'defined inserted';
    like $ir, qr/insertvalue %Slot \S+, i8 \d+, $i_tag\b/,    'tag inserted';
    like $ir, qr/insertvalue %Slot \S+, i64 %p, $i_pay\b/,    'payload inserted';
};

subtest 'the tag is readable back off the aggregate' => sub {
    my $ctx = $C->new;
    $ctx->_slot_tag_of('%s');
    my $i = $C->_slot_idx('tag');
    like join("\n", $ctx->render_blocks(1)),
        qr/extractvalue %Slot %s, $i\b/,
        '_slot_tag_of extracts at the named tag index';
};

# ---------------------------------------------------------------------------
# End-to-end through the real backend: a stored element records the reading
# its own repr establishes, and the module still executes.
# ---------------------------------------------------------------------------
subtest 'the backend stamps a stored element with its own reading' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my @c;
    for my $v (1, 2, 3) {
        my $n = $f->make('Constant', value => "$v", const_type => 'integer');
        $n->set_representation('Int');
        push @c, $n;
    }
    my $arr = $f->make('ArrayLiteral', inputs => \@c);
    $arr->set_representation('ArrayRef');
    my $len = $f->make('Length', inputs => [$arr]);
    $len->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$len]);

    my $ll = Chalk::Target::LLVM->lower($ret);

    like $ll, qr/^%Slot = type \{ i1, i8, i64 \}$/m,
        'the emitted module declares the three-field cell';

    # The elements are Int, so the tag must be Int's value -- NOT Undef (which
    # would claim the cell is empty) and NOT Opaque (the reading IS known here).
    my $int_tag = $C->_slot_tag_value('Int');
    like $ll, qr/store i8 $int_tag, i8\* \S+  ; ArrayRef: slot\[0\] tag=Int/,
        'an Int element is stamped Int';

    isnt $int_tag, $C->_slot_tag_value('Undef'),
        'a known reading is distinguishable from an undef cell';

    # Every slot GEP addresses a NAMED index.
    my $i_tag = $C->_slot_idx('tag');
    my $i_pay = $C->_slot_idx('payload');
    like $ll, qr/getelementptr inbounds %Slot, %Slot\* \S+, i64 0, i32 $i_tag  ; ArrayRef: slot\[0\] tag ptr/,
        'the tag GEP uses the named index';
    like $ll, qr/getelementptr inbounds %Slot, %Slot\* \S+, i64 0, i32 $i_pay  ; ArrayRef: slot\[0\] payload ptr/,
        'the payload GEP uses the named index';
};

# ---------------------------------------------------------------------------
# No literal index survives in production. This is the check that would have
# caught the reverted attempt.
# ---------------------------------------------------------------------------
subtest 'no production site addresses a Slot subfield by a literal' => sub {
    my @bad;
    for my $file ('lib/Chalk/Target/LLVM/Context.pm', 'lib/Chalk/Target/LLVM.pm') {
        open my $fh, '<', $file or die "$file: $!";
        while (my $line = <$fh>) {
            next if $line =~ /^\s*#/;
            # A %Slot GEP whose trailing subfield index is a bare number.
            push @bad, "$file:$.: $line"
                if $line =~ /getelementptr inbounds %Slot, %Slot\*[^;]*, i32 \d+\s*(?:;|")/;
            # An object-field GEP whose Slot subfield index is a bare number.
            push @bad, "$file:$.: $line"
                if $line =~ /\.obj\*[^;]*, i32 \$slot_idx, i32 \d+/;
        }
        close $fh;
    }
    is scalar(@bad), 0, 'every Slot subfield index comes from _slot_idx'
        or diag join '', @bad;
};

done_testing;
