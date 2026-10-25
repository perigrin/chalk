# ABOUTME: An if over a sub parameter nothing typed tests the value the call passed, by
# ABOUTME: that value's own truthiness: B::SoN -> chalk -> lli == perl.
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

# `my ($want) = @_; if ($want)`: the parameter is Unknown -- nothing in
# the sub types it -- but inlined at a call it IS the caller's value, and
# the condition is that value's truth. Refused as If.cond[Unknown->Boolean]
# (pvm 079 and seven more).
for my $case (
    [ q{sub load { "loaded " . ($_[0] // "nothing") } sub find { my ($want) = @_; my $found; if ($want) { $found = "it"; } return load($found) } print find(1), "; ", find(0), "\n";}, "loaded it; loaded nothing\n", 'an Int argument (pvm 079)' ],
    [ q{sub f { my ($s) = @_; if ($s) { return "t" } return "f" } print f("0"), f(""), f("0.0"), f("a"), "\n";}, "fftt\n", 'a Str argument' ],
    [ q{sub f { my ($x) = @_; if ($x) { return "t" } return "f" } my $u; print f($u), f(2.5), "\n";}, "ft\n", 'undef and a Num' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
