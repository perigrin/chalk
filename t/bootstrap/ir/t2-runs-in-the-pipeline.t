# ABOUTME: T2 runs between the loader and the backend, so the backend reads LLVM types.
# ABOUTME: Wiring it is what turns _repr_to_llvm_type from a lookup into a pass-through.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# WIRING T2 IN is what makes the pass mean anything: before this the graph the
# backend saw was still in Chalk vocabulary, and every consumer that needed a
# machine type computed one for itself.
#
# THE CONTRACT, from docs/plans/2026-08-31-t2-is-a-narrowing-analysis.md:
#
#   "T2 rewrites the graph; every node comes out carrying an LLVM type. The
#    backend then READS a type off the node instead of computing one."
#
# and the reason it beats a narrowed Chalk type:
#
#   "An LLVM-annotated graph is CHECKABLE on its own ... The alternative leaves
#    the final step scattered across 8 backend call sites and unverifiable,
#    which is exactly the shape that produced bc943e3b and ebdd6a23: consumers
#    deciding encoding one site at a time."
#
# WHAT THIS FILE PINS IS BEHAVIOUR, not stamps. A pass that rewrites every node
# in the compiler can produce a graph that still lowers and computes the wrong
# thing -- so these run real programs and compare against perl. The stamp-level
# contract is t2-emits-llvm-types.t; this is the end-to-end half.

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

# THE SPINE, one case per member, because T2's whole job is collapsing these to
# one machine type each. A pass that got Int right and Str wrong would look
# fine on any single case.
subtest 'Int arithmetic survives the narrowing' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $a = 2 + 3;
print $a, "\n";
PROG
    is $perl, "5\n", 'perl adds' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

subtest 'Num arithmetic survives the narrowing' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $a = 1.5 + 2.25;
print $a, "\n";
PROG
    is $perl, "3.75\n", 'perl adds floats' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- a Num narrowed to i64 would print 3';
};

subtest 'Str survives the narrowing' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $s = "hi";
print $s, "\n";
PROG
    is $perl, "hi\n", 'perl prints the string' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# THE MIXED CASE, which is where a narrowing pass earns its keep or breaks: an
# Int and a Num in one expression have DIFFERENT machine types, and the
# coercion between them has to survive T2 rewriting both ends.
subtest 'a mixed Int/Num expression keeps its coercion' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $i = 3;
my $n = 0.5;
print $i + $n, "\n";
PROG
    is $perl, "3.5\n", 'perl promotes' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- 3 here means the promotion was lost';
};

# CONTROL FLOW, because a Phi merges two arms and both must have narrowed to
# the SAME machine type or the phi is ill-typed. This is the shape most likely
# to break under a per-node rewrite.
subtest 'a branch merge survives the narrowing' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
my $c = 1;
my $x = $c ? 10 : 20;
print $x, "\n";
PROG
    is $perl, "10\n", 'perl picks the true arm' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# A CLASS, because field cells are %Slot -- the boxed fallback -- and the
# narrowing must not turn a boxed field into a bare word or vice versa.
subtest 'a class field round-trips through the narrowing' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG');
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field $n :param = 0;
    method get { $n }
}
package main;
say(C->new(n => 7)->get);
PROG
    is $perl, "7\n", 'perl reads the field' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

done_testing;
