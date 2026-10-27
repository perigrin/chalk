# ABOUTME: an array or hash reference passed to a :param field (declared Scalar)
# ABOUTME: reads back as that reference: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}


# A reference passed to a :param field with no default was refused: the
# field's declared repr is Scalar, and the guard took the ArrayRef/HashRef
# payload for a different reading (pvm 244). The cell's tag records the kind.
for my $c (
    [ q{use v5.42; use experimental "class"; class N { field $in :param; method first { return $in->[0] } method n { return scalar $in->@* } } my $o = N->new(in => [7, 8]); print $o->first, $o->n, "\n";} ],
    [ q{use v5.42; use experimental "class"; class N { field $h :param; method get ($k) { return $h->{$k} } } my $o = N->new(h => {a => 1, b => 2}); print $o->get("b"), $o->get("a"), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A field whose default is undef was refused: the default path stored it as
# a defined value, and Undef has no payload (pvm 244).
for my $src (
    q{use v5.42; use experimental "class"; class N { field $l :param = undef; method l { defined $l ? "d$l" : "u" } } print N->new->l, N->new(l => 4)->l, "\n";},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A field typed Int from its other constructor calls still refuses a reference:
# read back as Int, the pointer would print as a number.
{
    my $src = q{use v5.42; use experimental "class"; class N { field $v :param; method v { return $v } } my $o = N->new(v => 5); my $p = N->new(v => [1]); print $o->v, ref($p->v), "\n";};
    ok(!eval { through_llvm($src); 1 } && $@ =~ /GAP/, "an Int field given a reference is refused") or diag $@;
}

done_testing;
