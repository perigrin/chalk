# ABOUTME: An if arm in a loop body owns only the statements on its own control
# ABOUTME: chain -- not the next pass's, reached through a memory phi.
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
# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
# Under an alarm: the failure this guards against is a lowering that never
# ends.
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
    local $SIG{ALRM} = sub { die "lowering did not finish in 20s\n" };
    alarm 20;
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    alarm 0;
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# AN ARM'S BODY IS ITS CONTROL CHAIN. The walk that collects it follows data
# edges too; from a store in the arm, through the loop's memory phi, it
# reached the next pass's statements, and the If the arm belongs to counted
# as the arm's own -- process_control_node recursed until memory ran out
# (backlog 34066162).
for my $case (
    [ q{my @a = (1, 2); foreach my $x (1, 2) { $a[1] = $x; if ($x > 1) { $a[0] = 9 } print $a[0], $a[1] } print "\n";}, "1192\n", 'an element store, then a guarded store, in a foreach' ],
    [ q{sub ld { "l" . ($_[0] // "n") } for my $i (1 .. 3) { my $v; $v = $i if $i > 1; print ld($v) } print "\n";}, "lnl2l3\n", 'a my handed to a call, stored in an arm, in a loop' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
