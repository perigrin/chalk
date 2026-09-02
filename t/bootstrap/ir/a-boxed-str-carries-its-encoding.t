# ABOUTME: Every boxed %Str writes its enc field; Chalk's default is utf8, not perl's.
# ABOUTME: An uninitialised field whose reader is coming is a heisenbug with a scheduled date.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Target::LLVM::Context;

# `%Str = { ptr, len, enc }`. The third field names WHICH CHARACTER SET the
# bytes are written in -- UTF-8, UTF-16, Shift-JIS, EUC-JP, the ISO-8859
# family, EBCDIC. perl's own Encode knows 124 of them.
#
# AN OPEN SET, NOT A FLAG (perigrin, 2026-09-02). An earlier version of this
# file called it a bytes-vs-characters distinction; that is a CONSEQUENCE of
# the encoding, not the question the field asks, and a two-way flag would have
# been the wrong shape to grow. So %_STR_ENC is a REGISTRY: names get numbers
# as the backend learns to handle them, and nothing caps how many there are.
#
# CHALK'S DEFAULT IS UTF-8, AND THAT IS A DELIBERATE BREAK WITH PERL, which has
# no single default -- a literal without `use utf8` is bytes-as-Latin-1, with
# it the source is decoded, so identical text means different things depending
# on a pragma. Measured on 5.42.0:
#
#     length("a\x{2014}b")            3    characters
#     length(encode('UTF-8', $same))  5    bytes
#
# THIS IS NOT SPECULATIVE. Chalk is itself non-ASCII -- 56 files under
# lib/Chalk carry non-ASCII bytes, 174 declare `use utf8`, and MOP.pm:81 has an
# em-dash INSIDE A `die` STRING. Self-hosting means compiling that source, so
# the field has a reader coming.

subtest 'the encoding registry is open, named, and refuses what it does not know' => sub {
    my $enc  = Chalk::Target::LLVM::Context->can('_str_enc');
    my $all  = Chalk::Target::LLVM::Context->can('_str_encodings');
    ok $enc && $all, 'there is an accessor for values and one for the registry'
        or return;

    is $enc->('utf8'), 0,
        'utf8 is ZERO, so a zeroed cell is the default rather than an '
      . 'unassigned encoding';

    my %reg = $all->();
    cmp_ok scalar(keys %reg), '>=', 3, 'the registry has entries';

    # Distinct numbers: two encodings sharing one value is a silent mis-read.
    my %seen;
    my @dupes = grep { $seen{ $reg{$_} }++ } sort keys %reg;
    is_deeply \@dupes, [], 'every registered encoding has a distinct number';

    # THE PROPERTY THAT MATTERS FOR AN OPEN SET. A name nobody has registered
    # must be an ERROR, never a silent 0 -- emitting the default for a string
    # whose encoding we did not recognise produces a module that RUNS AND IS
    # WRONG. UTF-16 is the example precisely because it is one we will want.
    ok !eval { $enc->('utf-16'); 1 },
        'an unregistered encoding dies rather than defaulting to utf8';
    like $@, qr/utf-16/, 'and the error names the encoding it refused';
};

# The layout must actually carry it. A vocabulary with nowhere to store its
# values would pass the subtest above and be useless.
subtest 'the %Str layout has an enc field to hold it' => sub {
    my @fields = Chalk::Target::LLVM::Context::_str_fields();
    my ($enc)  = grep { $_->{name} eq 'enc' } @fields;

    ok $enc, 'the layout declares an enc field' or return;
    is $enc->{llvm}, 'i32', 'it is an i32';

    my $idx = Chalk::Target::LLVM::Context::_str_idx('enc');
    is $idx, 2, 'and it is the third field, after ptr and len';
};

# THE POINT OF THE FILE. Every site that boxes a Str onto the heap must write
# all three fields. Skipping enc is invisible while nothing reads it and
# becomes a bug in the READER, far from the write that skipped it -- which is
# the worst version of this defect, not the mildest.
subtest 'every heap-boxing site writes enc, not just ptr and len' => sub {
    my $src = do {
        open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
        local $/; <$fh>;
    };

    # A boxing site is recognisable by storing the len field into a %Str it
    # just allocated. Count those, then count the enc stores.
    my @len_stores = ($src =~ /store i64 \$len_val, i64\* \$\w+_gep/g);
    my @enc_stores = ($src =~ /store i32 " \. _str_enc\('utf8'\) \. ", i32\* \$\w+_gep/g);

    cmp_ok scalar @len_stores, '>=', 2,
        'found the heap-boxing sites (they store a len)';
    is scalar @enc_stores, scalar @len_stores,
        'every one of them also stores an enc'
        or diag("  a boxing site that writes ptr+len and not enc leaves the\n"
              . "  third field as malloc garbage -- harmless only until the\n"
              . "  first reader lands");
};

# The method-return boxing lives in the other file and must not be forgotten:
# it is the site that was ADDED most recently, so it is the one most likely to
# have been written before this rule existed.
subtest 'the method-return boxing site writes enc too' => sub {
    my $src = do {
        open my $fh, '<', 'lib/Chalk/Target/LLVM.pm' or die $!;
        local $/; <$fh>;
    };

    like $src, qr/_str_enc.*utf8/,
        'LLVM.pm asks the vocabulary for its encoding value'
        or diag('  a literal `store i32 0` here would pass a byte-level check\n'
              . '  while saying nothing about which encoding it committed to');
    like $src, qr/%ret_g2 = getelementptr inbounds %Str/,
        'and it GEPs the third field to store it';
};

done_testing;
