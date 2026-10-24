# ABOUTME: A merge whose arm is a call to a sub is a value merge when the producer says
# ABOUTME: so: `$p ? one() : 4` reads the call -- B::SoN -> chalk -> lli == perl.
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

# THE WIRE SAYS WHICH MERGE IS MEMORY. A call to a sub may store anything,
# so a phi with a direct call for an input was taken for a memory phi -- and
# when the call is an arm's VALUE (`my $v = $p ? one() : 4`) the value phi
# was never wired, and its read was refused as "Phi node encountered ...
# before its enclosing if/loop structure" (pvm chalk-found-gaps.md). B::SoN
# flags its memory phis `memory`; one it did not flag is a value.
for my $case (
    [ q{sub one { return 7 } sub pick { my ($p) = @_; my $v = defined $p ? one() : 0; return $v + 1 } print pick(1), " ", pick(undef), "\n";}, "8 1\n", 'in an inlined sub' ],
    [ q{sub one { print "one\n"; return 7 } my $p = $ENV{X} // 1; my $v = $p ? one() : 4; print "$v\n";}, "one\n7\n", 'a call that prints, taken' ],
    [ q{sub one { return 7 } my $p = $ENV{X} // 0; my $v = $p ? one() : 4; print "$v\n";}, "4\n", 'a scalar call in an arm' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
