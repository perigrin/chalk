# ABOUTME: time() is the clock's seconds, an Int: B::SoN -> chalk -> lli == perl (on what a
# ABOUTME: program can compare -- the value itself differs run to run).
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

# time was not lowered, and its untyped result made all it touched TOP
# (pvm 331, where it defeats folding: `1 + time() * 0`).
for my $c (
    [ q{my $t = time(); print $t > 1000000000 ? "y\n" : "n\n";} ],
    [ q{my $p = 1 + time() * 0; print "$p\n";} ],
    [ q{my $p = 1 + time() * 0; my $q = 2 + time() * 0; my $o = ""; for my $v ($p, $q) { $o .= "[$v]" } print join(",", map { "[$_]" } $p, $q), " ", join(",", grep { $_ > 1 } $p, $q), " $o\n";} ],
    [ q{my $a = time; my $b = time; print $b - $a < 5 ? "ok\n" : "slow\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
