# ABOUTME: a list assignment into scalars from a list that flattens (a call, an
# ABOUTME: array) takes element by element: B::SoN -> chalk -> lli == perl.
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


# `($s, $m) = f()` into scalars not kept in memory was refused: the value
# flattens, so each target takes its element at run time, undef past the end.
for my $src (
    q{sub f { (1, 2) } my ($s, $m); ($s, $m) = f(); print "$s $m\n";},
    q{sub f { (7) } my ($a, $b); ($a, $b) = f(); print $a, defined $b ? "d" : "u", "\n";},
    q{my @l = (4, 5, 6); my ($p, $q); ($p, $q) = @l; print $p + $q, "\n";},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A target's reads were stamped Unknown, so every consumer -- an
# interpolation, a comparison, a merge -- refused them (pvm 168, 169, 214).
# Its cell holds a Scalar, which is what it is read as.
for my $src (
    q{sub g { (5, 2) } sub f { my $lo = 0; if ($_[0]) { ($lo) = g(); } "$lo" } print f(1), f(0), "\n";},
    q{sub p { ("p$_[0]", length $_[0]) } my ($ap, $al) = p("xy"); print "$ap ", $al + 1, ($al > 1 ? " long" : " short"), "\n";},
    q{sub q2 { (3, "a") } my ($n, $s) = q2(); my @r = ($s) x $n; print "@r\n";},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
