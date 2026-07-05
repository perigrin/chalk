# ABOUTME: Guards the static out-of-bounds / missing-key Subscript repr inference (019f2e25).
# ABOUTME: An OOB array read / absent hash key loads as :Slot (yields undef), not :Int (yields 0).

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON qw(from_json);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

# Produce the B::SoN JSON for a snippet, load it, and return the repr of the
# (single) Subscript node in main::corpus_case.
sub subscript_repr ($body) {
    my $src = "package main;\nsub corpus_case { $body }\n";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;
    my ($graphs, $mop) = from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return undef;
    my ($sub) = grep { $_->operation eq 'Subscript' } $g->nodes->@*;
    return $sub ? ($sub->representation // '<undef>') : '<no Subscript>';
}

subtest 'an out-of-bounds array read loads as :Slot (R9)' => sub {
    # $a[9] on a 3-element array is statically OOB -> perl undef. The Subscript
    # must load as Slot (the tagged {defined=false} path), not Int (which the
    # backend prints as 0 -- a silent miscompile).
    is(subscript_repr('my @a = (1, 2, 3); $a[9]'), 'Slot',
        'OOB index 9 over a 3-element literal array -> Slot');
};

subtest 'a missing-key hash lookup loads as :Slot (R10)' => sub {
    is(subscript_repr('my %h = (a => 1, b => 2); $h{z}'), 'Slot',
        'absent key "z" over {a,b} -> Slot');
};

subtest 'an in-bounds array read stays :Int (teeth)' => sub {
    # The static-miss rule must NOT fire on a valid access: $a[1] is in bounds,
    # so it keeps the element repr. Bilateral coverage: a wrong static-miss
    # check that stamped everything Slot would break every valid read.
    is(subscript_repr('my @a = (1, 2, 3); $a[1]'), 'Int',
        'in-bounds index 1 keeps the element repr Int');
};

subtest 'a present-key hash lookup stays :Int (teeth)' => sub {
    is(subscript_repr('my %h = (a => 1, b => 2); $h{a}'), 'Int',
        'present key "a" keeps the element repr Int');
};

subtest 'a negative in-range index is a HIT, stays :Int (teeth)' => sub {
    # $a[-1] on a 3-element array is perl's last element (a HIT), NOT a miss.
    # The static-miss rule must only fire for idx < -len, so a negative in-range
    # index keeps the element repr -- else a valid from-the-end read would
    # wrongly load as Slot (undef). NOTE: the negative-index VALUE lowering
    # (from-the-end adjustment) is a separate backend gap (filed) -- this asserts
    # only the repr DECISION, which is correctly Int (a HIT, not a miss).
    is(subscript_repr('my @a = (1, 2, 3); $a[-1]'), 'Int',
        'negative in-range index -1 keeps the element repr Int (a HIT)');
};

subtest 'a negative out-of-range index is a MISS, loads :Slot (teeth)' => sub {
    # $a[-5] on a 3-element array is past the start -> perl undef.
    is(subscript_repr('my @a = (1, 2, 3); $a[-5]'), 'Slot',
        'negative out-of-range index -5 -> Slot');
};

subtest 'a flattened array container is NOT statically decided a MISS (teeth)' => sub {
    # (@x, 99) is list-flattening: B::SoN represents @x as a nested ArrayRef in
    # ONE input slot, so a static length over the outer inputs is WRONG. $a[3]
    # here is a HIT (99), not a miss. The static-miss rule must NOT stamp Slot,
    # or a valid read miscompiles to undef. (The container's element repr is not
    # inferable through the flattening either, so it stays untyped -- an honest
    # GAP, exactly as before the R9/R10 change; the point is it is NOT Slot.)
    isnt(subscript_repr('my @x = (10,20,30); my @a = (@x, 99); $a[3]'), 'Slot',
        'flattened (@x, 99)[3] is a HIT, NOT statically a miss -> not Slot');
};

subtest 'a flattened hash container is NOT statically decided a MISS (teeth)' => sub {
    # (%base, b => 2) flattens %base into one input slot, corrupting the
    # even/odd key parity -- a static key scan would falsely miss present keys.
    isnt(subscript_repr('my %base = (a => 1); my %h = (%base, b => 2); $h{a}'), 'Slot',
        'flattened (%base, b=>2){a} is a HIT, NOT statically a miss -> not Slot');
};

done_testing();
