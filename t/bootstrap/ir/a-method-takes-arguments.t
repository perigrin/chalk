# ABOUTME: `method plus($k)` -- the most common declaration in lib/Chalk -- must lower.
# ABOUTME: The vtable ABI was invocant-only, so every method with a signature refused.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `method plus($k) { ... }` refused with "cannot lower op=Parameter (not in
# literal-arithmetic slice)". Parameter IS handled -- but only in
# `_collect_positional_arg_reads`, the DIRECT-SUB INLINER path. A method call
# is a real vtable call, and the vtable ABI had no argument slots: every
# emitted method was `RET (i8*)`, invocant and nothing else.
#
# THIS IS THE SINGLE MOST COMMON DECLARATION FORM IN THE COMPILER'S OWN SOURCE
# -- 920 uses in lib/Chalk, against zero corpus coverage before the case that
# exposed it. Every method chalk must eventually compile to host itself has
# this shape.
#
# The tests below are all BEHAVIOURAL. An ABI change can produce a module that
# lowers, verifies, and passes the wrong value -- an argument read from the
# wrong slot is exactly that shape -- so "it lowered" proves nothing here.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "lli not found at $LLI"        unless -x $LLI;

sub compile_and_run ($src, $pkgs) {
    my ($sfh, $spath) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$sfh} $src;
    close $sfh;

    my $oracle = qx($PERL $spath 2>/dev/null);

    my $json = qx($PERL -I$SON -MO=SoN,json,$pkgs $spath 2>/dev/null);
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

subtest 'a method reads its one argument' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG', 'package=main,package=Counter');
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method plus($k) { $n + $k }
}
package main;
say(Counter->new(n => 10)->plus(32));
PROG

    is $perl, "42\n", 'perl adds the field and the argument' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees';
};

# THE ARGUMENT MUST BE THE ARGUMENT, not the invocant reinterpreted. A method
# that ignores its parameter and returns the field would print 10 here; one
# that read the wrong slot would print something else again. Only a case where
# the two differ can tell.
subtest 'the argument is distinguishable from the field' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG', 'package=main,package=Counter');
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method just_arg($k) { $k }
}
package main;
say(Counter->new(n => 10)->just_arg(7));
PROG

    is $perl, "7\n", 'perl returns the argument, not the field' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli returns the ARGUMENT'
        or diag('  10 here means the field was returned; anything else means\n'
              . '  the argument slot was read wrongly');
};

# TWO ARGUMENTS, IN ORDER. One argument cannot distinguish "slot 0" from "the
# only slot", so a lowering that always read the first would pass every
# subtest above. Subtraction is deliberate: it is not commutative, so a
# swapped pair gives a different answer rather than the same one.
subtest 'two arguments arrive in the right order' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG', 'package=main,package=Sub2');
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Sub2 {
    method diff($a, $b) { $a - $b }
}
package main;
say(Sub2->new->diff(10, 3));
PROG

    is $perl, "7\n", 'perl computes 10 - 3' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees -- not -7, which is the swapped pair';
};

# A NO-ARGUMENT METHOD ON THE SAME CLASS. The ABI change touches every emitted
# method, so the shape that already worked is the regression risk -- and a
# class holding both proves the two signatures coexist in one vtable.
subtest 'a no-argument method still works beside one that takes args' => sub {
    my ($perl, $lli, $err) = compile_and_run(<<'PROG', 'package=main,package=Both');
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Both {
    field $n :param = 5;
    method get { $n }
    method plus($k) { $n + $k }
}
package main;
my $o = Both->new(n => 5);
say($o->get);
say($o->plus(3));
PROG

    is $perl, "5\n8\n", 'perl runs both methods' or return;
    ok !defined $err, 'it lowers' or do { diag("  $err"); return };
    is $lli, $perl, 'lli agrees on both -- the vtable holds mixed arities';
};

done_testing;
