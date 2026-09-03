# ABOUTME: A program printing Inf or NaN matches perl, whatever type the wire gives them.
# ABOUTME: The producer moved them Num -> Str; chalk must be right either way.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# perl5-son a7eadbf moved `9**9**9` and `9**9**9 - 9**9**9` from `Num` to
# `Str` on the wire, on the ground that both pass the SYNTACTIC component of
# Num membership and fail the SEMANTIC one. Verified here on 5.42.0:
#
#     NaN == NaN   false     an equality reporting x != x has failed AS one
#     NaN - NaN    NaN       v - v is not the additive identity
#     Inf - Inf    NaN       likewise
#
# CHALK CANNOT HAVE THE DEFECT THAT MOTIVATED THAT CHANGE, and it is worth
# saying why rather than assuming: the defect is classifying a float literal
# off the SV's NOK flag, and SVf_NOK is set identically for 3.14, Inf and NaN
# (measured). Chalk never classifies an SV -- it reads the wire's stamp -- so
# it has no place to make that mistake.
#
# What chalk DOES own is emitting the right bytes, and this file pins that
# END TO END rather than at the Coerce node: coerce-num-str-non-finite.t builds
# the IR by hand and checks the conversion, which cannot see whether a real
# program's constant reaches it at all.
#
# The test is deliberately INDIFFERENT to the wire type. It asserts agreement
# with perl, so it holds across the a7eadbf boundary in both directions -- a
# test pinned to `:Str` would have been red before that commit and green after
# for a reason unrelated to whether chalk works.

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

subtest 'perl really does violate the Num contracts for these values' => sub {
    # The premise of the producer's change, measured rather than cited. If perl
    # ever stopped doing this the change would need revisiting, and this
    # subtest is where that would show.
    no warnings;
    my $inf = 9**9**9;
    my $nan = $inf - $inf;

    ok !($nan == $nan), 'NaN == NaN is FALSE -- equality fails as an equality';
    ok !(($nan - $nan) == 0), 'NaN - NaN is not the additive identity';
    ok !(($inf - $inf) == 0), 'Inf - Inf is not either';
    ok +($inf == $inf), 'Inf == Inf does hold -- only one contract fails for it';
};

subtest 'Inf prints as perl prints it' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $x = 9**9**9;
print $x, "\n";
PROG

    is $perl, "Inf\n", 'perl prints Inf' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- not C\'s "inf"';
};

subtest 'NaN prints as perl prints it' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $x = 9**9**9 - 9**9**9;
print $x, "\n";
PROG

    is $perl, "NaN\n", 'perl prints NaN' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- not C\'s "nan"';
};

# THE CONTROL, and it is the important one. A producer "fix" that stopped
# stamping NOK constants Num would satisfy both subtests above and destroy all
# float typing. An ordinary float must still be a Num that prints as one.
subtest 'ordinary floats are unaffected' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $a = 3.14;
my $b = -0.5;
my $c = 1e10;
print $a, "\n";
print $b, "\n";
print $c, "\n";
PROG

    is $perl, "3.14\n-0.5\n10000000000\n", 'perl prints the three floats' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees on all three -- float typing survives';
};

# ZERO IS THE ADVERSARIAL CASE for the infinity test perl5-son used:
# `$v == $v/2` is TRUE for 0, so an unguarded halving check calls 0.0 infinite.
subtest 'zero is not infinity' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $z = 0.0;
my $n = -0.0;
print $z, "\n";
print $n, "\n";
PROG

    is $perl, "0\n0\n", 'perl prints both zeroes as 0' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- 0.0 was not classified as infinite';
};

done_testing;
