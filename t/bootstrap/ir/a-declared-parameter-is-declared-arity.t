# ABOUTME: A method's arity is what it DECLARES, not what its body happens to read.
# ABOUTME: Deriving it from Parameter nodes undercounts an unused or forwarded parameter.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

our $TODO;

# THE PRODUCER EMITS NO `Parameter` NODE FOR A PARAMETER THE BODY NEVER READS.
# Measured, `method m($k) { 42 }`:
#
#     C::m ops: Start Constant Return          <- no Parameter anywhere
#
# So an arity derived by scanning the graph for Parameter nodes reads 0, the
# call site passes 1, and the arity check refuses a program that compiled
# correctly before the method-parameter ABI landed:
#
#     parent 215ffee7  define internal i64 @C__m(i8* %self)   lli 42 == perl 42
#     cb16da6d         GAP: passes 1 argument(s) but 'C'::m declares 0
#
# THE GRAPH IS A LOSSY VIEW OF THE SIGNATURE. It records parameters that are
# USED; the declaration is a separate fact. The commit that introduced this
# asserted the opposite in its own comment -- "a method's parameters are exactly
# its Parameter nodes" -- and that premise is what these tests falsify.
#
# THE WIRE HAS CARRIED THE ANSWER ALL ALONG. `classes.C.method_signatures`
# ships `{kind, invocant, mandatory, optional, params:[{index,name,sigil}]}`,
# and chalk read it nowhere in lib/ -- it appeared only in test fixtures. This
# is the "producer holds the answer" shape recorded on 2026-08-27, where ~86% of
# wire Unknowns turned out to be the loader discarding a computed answer.
#
# Four shapes, each of which defeats a different narrower fix:
#   unused    -- no Parameter node at all
#   trailing  -- only the LAST parameter is read (index 1 present, 0 absent)
#   middle    -- a HOLE: indices {0,2}, so a dense list misnumbers %argN
#   forwarded -- the parameter reaches another call as PadAccess, not Parameter

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

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main,package=C $spath 2>/dev/null);
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

sub cls ($body, $call) {
    return <<"PROG";
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class C {
    field \$n :param = 0;
$body
}
package main;
$call
PROG
}

subtest 'an UNUSED parameter still counts toward arity' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls('    method m($k) { 42 }', 'say(C->new(n=>1)->m(7));'));
    is $perl, "42\n", 'perl ignores the argument and returns 42' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# ONLY THE LAST PARAMETER IS READ, so the graph holds a single Parameter whose
# index is 1. A fix that counts Parameter nodes gets 1 and still refuses; a fix
# that reads the DECLARED list gets 2. The two answers differ here, which is
# what makes this case worth its own subtest.
subtest 'a trailing parameter is bound to the right argument' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls('    method m($a, $b) { $b }', 'say(C->new(n=>1)->m(3,9));'));
    is $perl, "9\n", 'perl returns the SECOND argument' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- 3 here means it read argument 0';
};

# A HOLE IN THE MIDDLE. The graph holds indices {0,2}. Compacting those into a
# dense two-element list names them %arg0,%arg1 while the body reads %arg2 --
# an undeclared register. This is the case that turns a wrong arity into
# invalid IR rather than a refusal, so it must survive the fix.
subtest 'a hole in the middle does not misnumber the arguments' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls('    method m($a, $b, $c) { $a + $c }', 'say(C->new(n=>1)->m(1,2,3));'));
    is $perl, "4\n", 'perl adds the FIRST and THIRD arguments' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- 3 would mean it added arguments 0 and 1';
};

# THE PARAMETER IS PASSED ONWARD, not consumed. It arrives as PadAccess rather
# than Parameter, so a Parameter-scan sees nothing at all -- the same undercount
# as the unused case, reached a different way.
#
# THE ARITY HALF OF THIS IS FIXED; the subtest stays red on a SEPARATE defect.
# It no longer refuses with an arity mismatch -- the declared signature now says
# 1 and the call passes 1. It refuses one layer further in, with
#
#     GAP: PadAccess reached LLVM backend with NO representation (undef)
#
# because nothing types a PadAccess that reads a declared-but-unread parameter.
# That is a TypeInference gap, not an ABI one, and closing it means teaching the
# forwarding shape to seed its own type -- work with a different shape and its
# own risk of preempting a source. Marked TODO rather than deleted: the case is
# correct and it will pass when that lands. Deleting it would lose the only
# pin on the forwarding shape, which is pervasive in lib/Chalk.
$TODO = 'PadAccess for a forwarded parameter is untyped -- a TypeInference gap';
subtest 'a forwarded parameter counts toward arity' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls("    method inner(\$v) { \$v + 1 }\n    method outer(\$k) { \$self->inner(\$k) }",
            'say(C->new(n=>1)->outer(41));'));
    is $perl, "42\n", 'perl forwards the argument and adds 1' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};
$TODO = undef;

# THE CONTROLS. Every shape that worked before must still work -- these are the
# cases a "just count the declared params" fix could plausibly break, since they
# are the ones where declared and used arity AGREE.
subtest 'the shapes that already worked still do' => sub {
    my ($perl, $lli, $err) = compile_and_run(
        cls('    method plus($k) { $n + $k }', 'say(C->new(n=>10)->plus(32));'));
    is $perl, "42\n", 'a fully-used parameter' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';

    ($perl, $lli, $err) = compile_and_run(
        cls('    method get { $n }', 'say(C->new(n=>5)->get);'));
    is $perl, "5\n", 'a no-argument method' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- zero-arity is unaffected';
};

done_testing;
