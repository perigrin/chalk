# ABOUTME: ListAppend is map/grep's loop-carried accumulator; it must lower and count correctly.
# ABOUTME: Arity does NOT identify shape -- grep's third input is a gate, map's is a contribution.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `map` and `grep` with a block lower to a counted loop whose result is built
# by a loop-carried accumulator: `ListAppend(acc, contribution...)`, seeded
# from an empty ArrayLiteral and merged by a Phi.
#
# THE ARITY DOES NOT IDENTIFY THE SHAPE, and this is the trap the node's own
# documentation warns about. Measured against the producer:
#
#   grep { $_ > 1 } (3,1,2)   ListAppend(Phi:Array, Subscript:Int, NumGt:Boolean)
#   map  { $_ * 2 } (1,2)     ListAppend(Phi:Array, Multiply:Int)
#   map  { ($_,$_) } (1,2)    ListAppend(Phi:Array, Subscript:Int, Subscript:Int)
#
# The grep and the map-pair forms have THE SAME ARITY and mean different
# things: grep's last input is a BOOLEAN GATE deciding whether to append at
# all, map's is a SECOND ELEMENT to append. Nothing on the wire distinguishes
# them but the input's own stamp, so a lowering that counts inputs is wrong for
# one of the two whichever way it guesses.
#
# Each case below therefore pins a COUNT, which is the observable that
# separates them: grep over (3,1,2) keeps 2 elements, map-pair over (1,2)
# produces 4.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "lli not found at $LLI"        unless -x $LLI;

sub compile_and_run ($src) {
    my ($sfh, $spath) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$sfh} $src;
    close $sfh;

    my $oracle = qx($PERL $spath 2>/dev/null);

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $spath 2>/dev/null);
    return ($oracle, undef, 'producer emitted no JSON') unless $json =~ /\S/;

    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new
        ->run_detail($json, $select, program_mode => 1);
    return ($oracle, undef, "load: $err")        if $err;
    return ($oracle, undef, 'no lowerable unit') unless @$units;
    return ($oracle, undef, $units->[0]{err})    unless $units->[0]{ok};

    my ($lfh, $lpath) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lfh, ':utf8';
    print {$lfh} $units->[0]{ll};
    close $lfh;
    return ($oracle, scalar qx($LLI $lpath 2>&1), undef);
}

subtest 'map builds a result of the same length as its input' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my @m = map { $_ * 2 } (1,2,3);
say(scalar(@m));
PROG

    is $perl, "3\n", 'perl maps 3 elements to 3' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# THE GATE CASE. grep DROPS elements, so a lowering that appended
# unconditionally would produce 3 here and be wrong in a way the map case
# cannot see.
subtest 'grep keeps only the elements its predicate admits' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my @g = grep { $_ > 1 } (3,1,2);
say(scalar(@g));
PROG

    is $perl, "2\n", 'perl keeps 2 of 3' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- the predicate gates the append'
        or diag('  3 here means the Boolean third input was appended as an '
              . 'element instead of read as a gate');
};

# THE POLARITY THAT PROVES THE GATE IS READ, not merely that some elements are
# dropped: a predicate matching NOTHING must produce an empty result.
subtest 'a grep whose predicate never matches produces nothing' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my @g = grep { $_ > 99 } (3,1,2);
say(scalar(@g));
PROG

    is $perl, "0\n", 'perl keeps none' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# ...and the other polarity: a predicate matching EVERYTHING keeps all of them.
# Together with the two above, these pin that the gate is consulted rather than
# a constant.
subtest 'a grep whose predicate always matches keeps everything' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my @g = grep { $_ > 0 } (3,1,2);
say(scalar(@g));
PROG

    is $perl, "3\n", 'perl keeps all 3' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# THE SAME-ARITY TRAP, stated as a test. This has three inputs like the grep
# case and means something different: both trailing inputs are ELEMENTS.
# A lowering that treated input[2] as a gate would produce 2 here.
subtest 'map returning a pair appends BOTH, not one plus a gate' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my @m = map { ($_, $_) } (1,2);
say(scalar(@m));
PROG

    is $perl, "4\n", 'perl produces 2 elements per input' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- both contributions are appended'
        or diag('  2 here means input[2] was read as a gate, which is the '
              . 'grep shape wrongly applied to map');
};

# The VALUES, not just the count. A result of the right length holding the
# wrong elements would pass every subtest above.
subtest 'the accumulated elements are the right values' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my @m = map { $_ * 2 } (1,2,3);
say($m[0]);
say($m[2]);
PROG

    is $perl, "2\n6\n", 'perl doubles each element' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees on the element VALUES, not merely the count';
};

done_testing;
