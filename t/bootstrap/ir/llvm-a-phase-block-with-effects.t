# ABOUTME: A BEGIN or END block with effects of its own is refused, not dropped; a
# ABOUTME: `use` -- only a require and an import -- leaves the program as it was.
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

# THE LOADER READ ONLY `methods`, so B::SoN's `phase_blocks` were dropped: a
# program with `BEGIN { print }` and `END { print }` printed only its main
# line (pvm corpus compile-phase.md). Until BEGIN and END run in their places,
# such a program is refused.
{
    my $got = eval { through_llvm(q{END { print "end\n" } BEGIN { print "begin\n" } print "main\n";}) };
    ok(!defined $got, 'a BEGIN and an END that print are not lowered') or diag "got: $got";
    like($@, qr/^load: .*BEGIN or END block/, 'refused, naming the phase block');
}

# A `use` IS A BEGIN BLOCK TOO, of a require and an import, and the program
# around it still lowers.
is(eval { through_llvm(q{use strict; use List::Util qw(sum); print "ok\n";}) } // "died: $@",
    "ok\n", 'a program with use statements still lowers');

done_testing;
