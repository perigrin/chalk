# ABOUTME: a reference read as a string is KIND(0x...) or Class=KIND(0x...), one string per
# ABOUTME: referent: B::SoN -> chalk -> lli == perl (addresses compared only for equality).
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


# Coerce[HashRef->Str] had no arm: `"$node"` as a hash key was refused (pvm 225).
# The address differs from perl's, so each program prints what does not
# depend on it: the shape, and whether two strings are equal.
for my $src (
    q{my $h = {}; my $s = "$h"; print $s =~ /^HASH\(0x[0-9a-f]+\)$/ ? "ok" : "no:$s", "\n";},
    q{my $h = bless {}, "N"; my $s = "$h"; print $s =~ /^N=HASH\(0x[0-9a-f]+\)$/ ? "ok" : "no:$s", "\n";},
    q{my $h = {}; my $g = {}; my %m; $m{"$h"} = 1; $m{"$g"} = 2; $m{"$h"} = 3; print scalar(keys %m), $m{"$h"}, $m{"$g"}, "\n";},
    q{my $r = [1]; my $s = "$r"; print $s =~ /^ARRAY\(0x[0-9a-f]+\)$/ ? "ok" : "no:$s", "\n";},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
