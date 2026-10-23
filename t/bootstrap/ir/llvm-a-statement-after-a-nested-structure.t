# ABOUTME: A statement after a nested if or loop, inside a loop body or an if arm, runs:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or is refused by name.
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

# THE ARM WALK STOPPED AT EVERY MERGE. A statement after a nested if or loop
# has the nested structure's Region as its control_in, and the walk that
# collects a loop body or an if arm refused to look past a Region: the
# statement was neither in the arm nor on the outer chain, and vanished
# (backlog c7113f1e: `print "|"` after an inner foreach printed abab for
# perl's ab|ab|).
for my $case (
    [ q{foreach my $x (1, 2) { if ($x > 1) { print "a" } print "|" } print "\n";}, "|a|\n", 'after an if, in a loop body' ],
    [ q{foreach my $x (1, 2) { foreach my $y ("a", "b") { print $y } print "|" } print "\n";}, "ab|ab|\n", 'after a loop, in a loop body' ],
    [ q{my $c = 1; if ($c) { foreach my $y ("a", "b") { print $y } print "|" } print "\n";}, "ab|\n", 'after a loop, in an if arm' ],
    [ q{my $c = 1; if ($c) { if ($c > 0) { print "a" } print "|" } print "\n";}, "a|\n", 'after an if, in an if arm' ],
    [ q{my $i = 0; while ($i < 2) { foreach my $y ("a", "b") { print $y } print "|"; $i++ } print "\n";}, "ab|ab|\n", 'after a loop, in a while body' ],
    [ q{foreach my $x (1, 2) { foreach my $y ("a", "b") { print $y } print "|"; foreach my $z (1) { print $z } print "." } print "\n";}, "ab|1.ab|1.\n", 'after each of two loops' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "$name: perl's answer") }
    else { like($@, qr/^(?:load|lower): .*(?:GAP|LLVM backend:)/, "$name: refused, naming why") or diag $@ }
}

done_testing;
