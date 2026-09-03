# ABOUTME: `&&` and `||` whose merge is Scalar lower through the %Slot ABI like any other repr.
# ABOUTME: The guard refusing them predated Scalar having a machine type at all.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `my $x = "a"; say($x eq $x && (print "y\n"))` refused with
# "And with repr=Scalar reached LLVM backend -- cannot lower runtime-free."
#
# THAT GUARD OUTLIVED ITS REASON. `Scalar` maps to `%Slot` in the repr->LLVM
# type map, `_emit_coercion` boxes any narrowed reading into one, and
# `_emit_read_slot_as` reads it back by tag. The one thing genuinely missing
# was at T1: `%_COERCIBLE_TO` had NO Scalar row, so `Scalar -> Boolean` did not
# exist as far as the type layer was concerned, and the backend's short-circuit
# path could not ask for the bridge it needed.
#
# perl coerces every scalar to a boolean and never dies doing it (measured, one
# witness per branch of Scalar, in scalar-has-a-truth-value.t). With that row
# added, `&&` over a tagged cell is the same shape as `&&` over any other pair
# of differing arms -- which this path already handles, because `A && B` yields
# one of its OPERANDS and the arms genuinely differ in type.
#
# THE MERGE IS WHY THIS SHAPE EXISTS AT ALL. `$x eq $x` is Boolean and
# `print` returns Boolean, but a failed print returns undef -- so the join is
# Scalar, not Boolean. That is not a defect to be narrowed away; it is the
# honest type of "one of these two values", and the %Slot ABI is what carries
# it.

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

# The corpus L5d shape. `$x eq $x` is always true, so the print arm RUNS and
# the && yields the print's return value.
subtest 'a Scalar-merged && lowers and matches perl' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $x = "a";
say($x eq $x && (print "y\n"));
PROG

    is $perl, "y\n1\n", 'perl runs the print arm and says 1' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees with perl';
};

# L5e, the other operator. `||` short-circuits on the OTHER polarity, so a fix
# that special-cased And would pass the subtest above and leave this one.
subtest 'a Scalar-merged || lowers and matches perl' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $x = "a";
say($x ne $x || (print "y\n"));
PROG

    is $perl, "y\n1\n", 'perl falls through to the print arm' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees with perl';
};

# THE SHORT-CIRCUIT MUST STILL SHORT-CIRCUIT. A merge that evaluated both arms
# would produce the right VALUE here and the wrong OUTPUT -- the print would
# run when perl skips it. Only the side effect can tell the difference, which
# is why this case prints from the arm that must not be taken.
subtest 'the skipped arm is not evaluated' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $x = "a";
my $r = ($x ne $x) && (print "SHOULD-NOT-RUN\n");
say("done");
PROG

    is $perl, "done\n", 'perl skips the print entirely' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli skips it too -- the branch is real, not a select'
        or diag('  SHOULD-NOT-RUN in the output means both arms were evaluated');
};

# The narrowed cases share this code path and are the regression risk: the
# guard being removed sat above them.
subtest 'Int and Boolean merges are unaffected' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $a = 5;
my $b = 7;
say($a && $b);
PROG

    is $perl, "7\n", 'perl yields the RHS operand' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- an Int-merged && still works';
};

done_testing;
